import type { Register } from 'claude-code'
import { SETTINGS_KEY, Watchlist } from './watchlist'
import { formatChange, formatPrice, formatBandPrice, formatTime } from './yahoo'

export const PANE = 'pulse-quotes'
const HELP = '/pulse · /pulse add AAPL · /pulse remove AAPL · /pulse refresh · /pulse off · /pulse on'

export const register: Register = (on, options) => {
  const intervalSeconds = watchInterval(options)
  const watch = new Watchlist(intervalSeconds * 1000)
  let input = ''
  let error = ''

  const act = async (action: () => Promise<unknown>) => {
    error = ''
    try { await action() } catch (cause) {
      error = cause instanceof Error ? cause.message : 'Could not save settings. Please try again.'
    }
  }

  on('session.start', async ($, e, next) => {
    // Headless sessions have no ticker surface and must not poll Yahoo.
    if (!e.isInteractive) return next(e)
    await watch.start({
      load: () => $.store.get(SETTINGS_KEY),
      save: preferences => $.store.set(SETTINGS_KEY, preferences),
      now: () => $.clock.now(),
      sleep: ms => $.clock.sleep(ms),
      after: (ms, callback) => $.clock.after(ms, callback),
      fetch: url => $.http.fetch(url, {
        headers: { 'User-Agent': 'Pulse-Claude/0.2.0', Accept: 'application/json' },
      }),
      redraw: () => $.ui.invalidate('ui.render'),
    })
    await $.command.register({
      name: 'pulse', description: 'Watch Yahoo Finance quotes and manage your watchlist',
      argumentHint: '[add <ticker> | remove <ticker> | refresh | off | on]',
      immediate: true,
    })
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    // /clear and /resume end a conversation, not the loaded mod's session.
    if (e.reason !== 'clear' && e.reason !== 'resume') watch.stop()
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
        await $.ui.open({ id: PANE, title: 'Pulse', focus: true, columns: 80, rows: Math.min(30, Math.max(18, watch.preferences.symbols.length * 3 + 16)) })
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
    const prefix = watch.preferences.paused ? 15 : 8
    const symbols = watch.preferences.symbols
    const label = (symbol: string) => {
      const quote = watch.quotes[symbol]
      const cached = watch.errors[symbol] && quote ? ' cached' : ''
      return quote ? `${symbol} ${formatBandPrice(quote)} ${formatChange(quote.changePercent)}${cached}` : `${symbol} unavailable`
    }
    const fits = (list: string[]) => prefix + list.map(symbol => label(symbol).length).reduce((a, b) => a + b, 0)
      + Math.max(0, list.length - 1) * 3 + (list.length < symbols.length ? ` · +${symbols.length - list.length}`.length : 0) <= width
    let visible = symbols.slice(0, 5)
    while (visible.length > 1 && !fits(visible)) visible = visible.slice(0, -1)
    return <Box><Text wrap="truncate">
      <Text bold>Pulse</Text>{watch.preferences.paused ? ' paused' : ''}{' · '}
      {!visible.length && <Text dimColor>/pulse add AAPL</Text>}
      {visible.map((symbol, index) => {
        const quote = watch.quotes[symbol]
        const failed = !!watch.errors[symbol]
        return <Text key={symbol}>
          {index ? ' · ' : ''}<Text bold>{symbol}</Text>{' '}
          {quote ? <Text dimColor={failed}>{formatBandPrice(quote)}{' '}
            <Text color={quote.changePercent === null ? undefined : quote.changePercent >= 0 ? 'green' : 'red'}>
              {formatChange(quote.changePercent)}
            </Text>{failed ? ' cached' : ''}
          </Text> : <Text dimColor>{failed ? 'unavailable' : '…'}</Text>}
        </Text>
      })}
      {visible.length < watch.preferences.symbols.length && <Text dimColor>{` · +${watch.preferences.symbols.length - visible.length}`}</Text>}
    </Text></Box>
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const { Box, Text, Button, Input } = $.ui.resolve(e)
    const compact = e.props.bodyColumns < 64
    const redraw = () => $.ui.invalidate('ui.render')
    const action = (task: () => Promise<unknown>) => { void act(task).finally(redraw) }
    const addTicker = () => action(async () => { await watch.add(input); input = '' })
    const rule = '─'.repeat(Math.max(8, e.props.bodyColumns - 2))
    return <Box flexDirection="column" paddingX={1}>
      <Box gap={2}>
        <Text bold>Watchlist</Text>
        <Text dimColor>{`${watch.preferences.symbols.length} ${watch.preferences.symbols.length === 1 ? 'ticker' : 'tickers'}`}</Text>
      </Box>
      <Text color={watch.preferences.paused ? 'yellow' : 'green'}>
        {watch.preferences.paused ? '● Auto-refresh paused' : watch.loading ? '● Refreshing quotes…' : `● Auto-refresh every ${intervalSeconds}s`}
      </Text>
      <Box key="watchlist-actions" gap={2} marginTop={1} marginBottom={1} flexWrap="wrap">
        <Button key="refresh" label="Refresh (r)" hotkey="r" onPress={() => action(() => watch.refresh())} />
        <Button key="pause" label={watch.preferences.paused ? 'Resume (p)' : 'Pause (p)'} hotkey="p"
          onPress={() => action(() => watch.pause(!watch.preferences.paused))} />
      </Box>
      <Box key="add-section" flexDirection="column" borderStyle="round" borderColor="cyan" paddingX={1} marginBottom={1}>
        <Text bold color="cyan">Add ticker</Text>
        <Box gap={2} alignItems="center">
          <Box flexGrow={1} flexShrink={1}>
            <Input key="add-ticker" placeholder={compact ? 'AAPL, 0700.HK' : 'AAPL, 0700.HK, ^GSPC'} value={input}
              submitLabel="add" autoFocus onInput={value => { input = value }}
              onSubmit={value => { input = value; addTicker() }} />
          </Box>
          <Button key="add" label="Add" onPress={addTicker} />
        </Box>
      </Box>
      {error && <Box marginBottom={1}><Text color="red" wrap="wrap">{error}</Text></Box>}
      {watch.message && <Box marginBottom={1}><Text color={watch.message.includes('rate limited') ? 'yellow' : undefined} wrap="wrap">{watch.message}</Text></Box>}
      {!watch.preferences.symbols.length && <Box marginY={1}><Text dimColor>Your watchlist is empty. Add a ticker above.</Text></Box>}
      {watch.preferences.symbols.length > 0 && !compact && <Box marginBottom={1} justifyContent="space-between">
        <Box gap={2}>
          <Box width={12}><Text dimColor>TICKER</Text></Box>
          <Box width={16} justifyContent="flex-end"><Text dimColor>PRICE</Text></Box>
          <Box width={10} justifyContent="flex-end"><Text dimColor>CHANGE</Text></Box>
        </Box>
        <Text dimColor>ACTION</Text>
      </Box>}
      {watch.preferences.symbols.map(symbol => {
        const quote = watch.quotes[symbol]
        const failed = watch.errors[symbol]
        const price = quote ? formatPrice(quote) : failed ? 'Unavailable' : watch.preferences.paused ? 'Not fetched' : 'Waiting…'
        const change = quote ? <Text color={quote.changePercent === null ? undefined : quote.changePercent >= 0 ? 'green' : 'red'}>
          {formatChange(quote.changePercent)}
        </Text> : <Text dimColor>—</Text>
        return <Box key={`ticker-${symbol}`} flexDirection="column" marginBottom={1}>
          <Box gap={2} justifyContent="space-between" alignItems="center">
            {compact ? <Box flexGrow={1} flexShrink={1}><Text bold wrap="truncate">{symbol}</Text></Box>
              : <Box gap={2} flexShrink={1}>
                <Box width={12}><Text bold wrap="truncate">{symbol}</Text></Box>
                <Box width={16} justifyContent="flex-end"><Text dimColor={!quote || !!failed} wrap="truncate">{price}</Text></Box>
                <Box width={10} justifyContent="flex-end">{change}</Box>
              </Box>}
            <Button key={`remove-${symbol}`} label="Remove" onPress={() => action(() => watch.remove(symbol))} />
          </Box>
          {compact && <Box gap={2}><Text dimColor={!quote || !!failed}>{price}</Text>{change}</Box>}
          {quote && <Text dimColor wrap="truncate">
            {compact ? '' : `${quote.name} · `}{`As of ${formatTime(quote.timestamp)}`}
            {quote.delaySeconds !== null ? ` · Delay ${Math.ceil(quote.delaySeconds / 60)}m` : ''}
          </Text>}
          {failed && <Text color="yellow" wrap="wrap">{quote ? 'Cached quote · ' : ''}{failed}</Text>}
        </Box>
      })}
      <Text dimColor wrap="truncate">{rule}</Text>
      <Text dimColor wrap="wrap">Yahoo Finance · Regular-session quotes · Exchange delays vary · Times are local.</Text>
      <Text dimColor wrap="wrap">Tab: move between controls · Enter: activate · Esc: return to prompt</Text>
    </Box>
  })
}

function watchInterval(options: Record<string, unknown>): number {
  const value = Number(options.refreshSeconds ?? 60)
  return Number.isFinite(value) ? Math.min(3600, Math.max(60, value)) : 60
}
