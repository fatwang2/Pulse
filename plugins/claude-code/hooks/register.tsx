import type { EngineInterface, Register } from 'claude-code'
import { SETTINGS_KEY, Watchlist } from './watchlist'
import { formatChange, formatPrice, formatBandPrice, formatStaleDate } from './yahoo'
import { isCryptoPair } from './binance'

export const PANE = 'pulse-quotes'
const HELP = '/pulse · /pulse add AAPL · /pulse remove AAPL · /pulse refresh · /pulse off · /pulse on'

export const register: Register = on => {
  const intervalSeconds = 60
  const watch = new Watchlist(intervalSeconds * 1000)
  let input = ''
  // Desktop keeps a field's typed text while the drawn value stays '', so a
  // cleared field is redrawn under a new key to discard it.
  let fieldRound = 0
  let error = ''

  const act = async (action: () => Promise<unknown>) => {
    error = ''
    try { await action() } catch (cause) {
      error = cause instanceof Error ? cause.message : 'Could not save settings. Please try again.'
    }
  }

  // The terminal REPL draws from session.start. Claude Desktop runs a headless
  // session and attaches later; a plain -p run never draws and never polls.
  let interactive = false
  const desktops = new Set<string>()
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'pulse', description: 'Watch stock and crypto quotes above the prompt',
      argumentHint: '[add <ticker> | remove <ticker> | refresh | off | on]',
      immediate: true,
    })
    interactive = e.isInteractive
    if (interactive) await startWatch($, watch)
    return next(e)
  })

  on('session.attach', { surface: 'desktop' }, async ($, e, next) => {
    // A second desktop window shares the running refresh loop.
    const first = !interactive && !desktops.size
    desktops.add(e.clientId)
    if (first) await startWatch($, watch)
    return next(e)
  })

  on('session.detach', { surface: 'desktop' }, async ($, e, next) => {
    if (desktops.delete(e.clientId) && !interactive && !desktops.size) watch.stop()
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    // /clear and /resume end a conversation, not the loaded mod's session.
    if (e.reason !== 'clear' && e.reason !== 'resume') {
      watch.stop()
      interactive = false
      desktops.clear()
    }
    return next(e)
  })

  on('command.run', { command: 'pulse' }, async ($, e) => {
    const args = e.args.trim().split(/\s+/).filter(Boolean)
    try {
      if (!args.length) {
        if ((await $.ui.panes()).some(pane => pane.id === PANE)) {
          await $.ui.close({ id: PANE })
          return { text: 'Pulse panel closed.' }
        }
        await $.ui.open({ id: PANE, title: 'Pulse', focus: true, columns: 80,
          rows: Math.min(30, Math.max(22, watch.preferences.symbols.length * 3 + 20)) })
        return { text: 'Pulse panel opened.' }
      }
      if (args[0] === 'add' && args.length === 2) return { text: await watch.add(args[1]) }
      if (args[0] === 'remove' && args.length === 2) return { text: await watch.remove(args[1]) }
      if (args[0] === 'off' && args.length === 1) return { text: await watch.pause(true) }
      if (args[0] === 'on' && args.length === 1) return { text: await watch.pause(false) }
      if (args[0] === 'refresh' && args.length === 1) {
        // Refresh on a background timer, so a long watchlist never blocks input.
        $.clock.after(0, () => watch.refresh())
        return { text: 'Refresh requested.' }
      }
      return { text: HELP }
    } catch (cause) {
      return { text: cause instanceof Error ? cause.message : 'Could not save settings. Please try again.' }
    }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const width = Math.max(20, e.props.bodyColumns || e.viewport?.columns || 80)
    const state = watch.preferences.paused ? 'Paused' : ''
    const symbols = watch.preferences.symbols
    const label = (symbol: string) => {
      const quote = watch.quotes[symbol]
      const cached = watch.errors[symbol] && quote ? ' cached' : ''
      return quote ? `${symbol} ${formatBandPrice(quote)} ${formatChange(quote.changePercent)}${cached}` : `${symbol} unavailable`
    }
    const more = (list: string[]) => list.length < symbols.length ? `   +${symbols.length - list.length} more`.length : 0
    const fits = (list: string[]) => 8 + (state ? state.length + 3 : 0) + list.map(symbol => label(symbol).length).reduce((a, b) => a + b, 0)
      + Math.max(0, list.length - 1) * 3 + more(list) <= width
    let visible = symbols.slice(0, 5)
    while (visible.length > 1 && !fits(visible)) visible = visible.slice(0, -1)
    return <Box><Text wrap="truncate">
      <Text dimColor>Pulse</Text>
      {state && <Text color="warning">{` ${state}`}</Text>}{'   '}
      {!visible.length && <Text dimColor>Add a ticker with /pulse add AAPL</Text>}
      {visible.map((symbol, index) => {
        const quote = watch.quotes[symbol]
        const failed = !!watch.errors[symbol]
        return <Text key={symbol}>
          {index ? <Text dimColor>{' · '}</Text> : ''}<Text bold>{symbol}</Text>{' '}
          {quote ? <Text>
            <Text dimColor={failed}>{formatBandPrice(quote)}</Text>{' '}
            <Text color={changeColor(quote.changePercent)}>{formatChange(quote.changePercent)}</Text>
            {failed && <Text dimColor>{' cached'}</Text>}
          </Text> : <Text dimColor>{failed ? 'unavailable' : '…'}</Text>}
        </Text>
      })}
      {visible.length < symbols.length && <Text dimColor>{`   +${symbols.length - visible.length} more`}</Text>}
    </Text></Box>
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const { Box, Text, Button, Input, Link } = $.ui.resolve(e)
    // Desktop measures cells in its code font but draws proportional text, so
    // its rows fit side by side at fewer reported columns than the terminal's.
    const compact = e.props.bodyColumns < (e.surface === 'desktop' ? 44 : 64)
    // Desktop draws native controls (hotkey badges, the field's own submit
    // button, a close button); the terminal spells those out in text.
    const desktop = e.surface === 'desktop'
    const redraw = () => $.ui.invalidate('ui.render')
    const action = (task: () => Promise<unknown>) => { void act(task).finally(redraw) }
    const addTicker = () => action(async () => { await watch.add(input); input = ''; fieldRound++ })
    const paused = watch.preferences.paused
    const statusColor = paused ? 'warning' : watch.loading ? 'cyan' : 'success'
    const status = paused ? '● Auto-refresh paused' : watch.loading ? '● Refreshing quotes…' : `● Auto-refresh every ${intervalSeconds}s`
    const ccCount = watch.preferences.symbols.length
    const now = await $.clock.now()

    const section = (title: string) => <Text dimColor bold>{title.toUpperCase()}</Text>
    // Spacing is in cells. Desktop converts a cell to a code-font character, far
    // smaller than a terminal row, so it needs more of them for the same air. A
    // docked terminal pane has the full height; an inline one shares the prompt's.
    // Desktop draws a horizontal cell only a few pixels wide, so its horizontal
    // padding takes several.
    const space = desktop ? 3 : e.props.placement === 'dock' ? 2 : 1
    const gap = desktop ? 1 : 0
    const rowGap = desktop ? 2 : 1
    // Desktop text fields keep a fixed width (their submit button included), so
    // the insets stay small enough for the add field to fit a docked pane.
    const padX = desktop ? 4 : 1

    return <Box flexDirection="column" paddingX={padX} paddingY={desktop ? 2 : 0}>
      <Box key="status-section" flexDirection="column">
        <Box justifyContent="space-between" alignItems="center" gap={2} flexWrap="wrap">
          {section(`Watchlist · ${ccCount} ${ccCount === 1 ? 'ticker' : 'tickers'}`)}
          {!desktop && <Box key="watchlist-actions" gap={1}>
            <Button key="refresh" label="Refresh (r)" hotkey="r" dimColor onPress={() => action(() => watch.refresh())} />
            <Button key="pause" label={paused ? 'Resume (p)' : 'Pause (p)'} hotkey="p" dimColor
              onPress={() => action(() => watch.pause(!paused))} />
          </Box>}
        </Box>
        <Box marginTop={gap}><Text key="refresh-status" color={statusColor}>{status}</Text></Box>
        {desktop && <Box key="watchlist-actions" gap={1} marginTop={rowGap}>
          <Button key="refresh" label="Refresh" hotkey="r" onPress={() => action(() => watch.refresh())} />
          <Button key="pause" label={paused ? 'Resume' : 'Pause'} hotkey="p" onPress={() => action(() => watch.pause(!paused))} />
        </Box>}
      </Box>

      <Box key={`add-section-${fieldRound}`} gap={1} alignItems="center" marginTop={rowGap}>
        <Box flexGrow={1} flexShrink={1}>
          <Input key="add-ticker" placeholder={compact ? 'AAPL, BTC/USDT' : 'Add a ticker: AAPL, 0700.HK, BTC/USDT'} value={input}
            submitLabel={desktop ? 'Add' : 'add'} autoFocus onInput={value => { input = value }}
            onSubmit={value => { input = value; addTicker() }} />
        </Box>
        {!desktop && <Button key="add" label="Add" onPress={addTicker} />}
      </Box>
      {error && <Box marginTop={rowGap}><Text color="error" wrap="wrap">{error}</Text></Box>}
      {watch.message && <Box marginTop={1}>
        <Text color={watch.message.includes('rate limited') ? 'warning' : undefined} dimColor={!watch.message.includes('rate limited')} wrap="wrap">{watch.message}</Text>
      </Box>}

      <Box key="watchlist" flexDirection="column" marginTop={rowGap}>
        {!ccCount && <Text dimColor wrap="wrap">Your watchlist is empty. Add a ticker above.</Text>}
        {watch.preferences.symbols.map((symbol, index) => {
          const quote = watch.quotes[symbol]
          const failed = watch.errors[symbol]
          const price = <Text dimColor={!quote || !!failed} wrap="truncate">
            {quote ? formatPrice(quote) : failed ? 'Unavailable' : paused ? 'Not fetched' : 'Waiting…'}
          </Text>
          const change = <Text color={quote ? changeColor(quote.changePercent) : undefined} dimColor={!quote}>
            {quote ? formatChange(quote.changePercent) : '—'}
          </Text>
          const stale = quote ? formatStaleDate(quote.timestamp, now) : ''
          const meta = quote ? [quote.name, stale && `As of ${stale}`,
            !!quote.delaySeconds && `Delay ${Math.ceil(quote.delaySeconds / 60)}m`].filter(Boolean).join(' · ') : ''
          // minWidth 0 lets a long name truncate instead of pushing the row's
          // button out of a narrow Desktop pane (flex items default to content width).
          return <Box key={`ticker-${symbol}`} flexDirection="column" width="100%" marginTop={index ? rowGap : 0}>
            <Box gap={2} alignItems="center" width="100%">
              <Box flexDirection="column" flexGrow={1} flexShrink={1} minWidth={0}>
                <Text bold wrap="truncate">{symbol}</Text>
                {!compact && meta && <Text dimColor wrap="truncate">{meta}</Text>}
              </Box>
              {!compact && <Box flexDirection="column" alignItems="flex-end" flexShrink={0}>{price}{change}</Box>}
              <Button key={`remove-${symbol}`} label="Remove" dimColor={!desktop} onPress={() => action(() => watch.remove(symbol))} />
            </Box>
            {compact && <Box gap={2}>{price}{change}</Box>}
            {compact && meta && <Text dimColor wrap="truncate">{meta}</Text>}
            {failed && <Text color="warning" wrap="wrap">{quote ? 'Cached quote · ' : ''}{failed}</Text>}
          </Box>
        })}
      </Box>

      <Box key="footer" flexDirection="column" marginTop={space}>
        <Text dimColor wrap="wrap">
          {watch.preferences.symbols.some(isCryptoPair)
            ? 'Yahoo Finance · Binance Spot · Stocks: regular session, exchange delays vary · Crypto: 24h change · Times are local · '
            : 'Yahoo Finance · Regular-session quotes · Exchange delays vary · Times are local · '}
          <Link href="https://www.pulseticker.app/">pulseticker.app</Link>
        </Text>
        {!desktop && <Text dimColor wrap="wrap">Tab: move between controls · Enter: activate · Esc: return to prompt</Text>}
      </Box>
    </Box>
  })
}

function changeColor(change: number | null): string | undefined {
  return change === null ? undefined : change >= 0 ? 'green' : 'red'
}

function startWatch($: EngineInterface, watch: Watchlist): Promise<void> {
  return watch.start({
    load: () => $.store.get(SETTINGS_KEY),
    save: preferences => $.store.set(SETTINGS_KEY, preferences),
    now: () => $.clock.now(),
    sleep: ms => $.clock.sleep(ms),
    after: (ms, callback) => $.clock.after(ms, callback),
    // The only two hosts the mod contacts, each written whole at its call.
    fetchYahoo: path => $.http.fetch(`https://query1.finance.yahoo.com/v8/finance/chart/${path}`, {
      headers: { 'User-Agent': 'Pulse-CC/0.4.1', Accept: 'application/json' },
    }),
    fetchBinance: query => $.http.fetch(`https://data-api.binance.vision/api/v3/ticker/24hr?${query}`, {
      headers: { 'User-Agent': 'Pulse-CC/0.4.1', Accept: 'application/json' },
    }),
    redraw: () => $.ui.invalidate('ui.render'),
  })
}
