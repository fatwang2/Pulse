import type { EngineInterface, Register } from 'claude-code'
import { SETTINGS_KEY, Watchlist } from './watchlist'
import { formatChange, formatPrice, formatBandPrice, formatStaleDate } from './yahoo'
import { MAC_SETTINGS_KEY, MacError, symbolKey } from './mac'
import { isCryptoPair } from './binance'

export const PANE = 'pulse-quotes'
const HELP = '/pulse · /pulse source cc|mac · /pulse add AAPL · /pulse remove AAPL · /pulse refresh · /pulse off · /pulse on'

export const register: Register = (on, options) => {
  const intervalSeconds = 60
  const macIntervalSeconds = 5
  let hasToken = typeof options.macToken === 'string' && !!options.macToken.trim()
  const link: MacLink = { server: 'plugin:pulse-cc:pulse', hasToken }
  const watch = new Watchlist(intervalSeconds * 1000, macIntervalSeconds * 1000)
  let input = ''
  // Desktop cannot show the /plugin configure dialog, so its token field saves
  // through the same host command non-interactively (secure storage). The typed
  // value travels only on that command's stdin and is never kept or shown.
  let token = ''
  // Desktop keeps a field's typed text while the drawn value stays '', so a
  // cleared field is redrawn under a new key to discard it.
  let fieldRound = 0
  let editingToken = false
  let notice = ''
  let error = ''
  let macGroupID: string | undefined

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
      name: 'pulse', description: 'Watch stocks and crypto, or your Pulse Mac watchlists',
      argumentHint: '[source cc|mac | add <ticker> | remove <ticker> | refresh | off | on]',
      immediate: true,
    })
    interactive = e.isInteractive
    if (interactive) await startWatch($, watch, link)
    return next(e)
  })

  on('session.attach', { surface: 'desktop' }, async ($, e, next) => {
    // A second desktop window shares the running refresh loop.
    const first = !interactive && !desktops.size
    desktops.add(e.clientId)
    if (first) await startWatch($, watch, link)
    return next(e)
  })

  on('session.detach', { surface: 'desktop' }, async ($, e, next) => {
    if (desktops.delete(e.clientId) && !interactive && !desktops.size) watch.stop()
    return next(e)
  })

  // $.mcp.call still passes through the permission check, and Desktop's auto
  // mode refuses a call no user request asked for. Allow only this plugin's own
  // read-only reads; the model's calls and every write tool keep their checks.
  on('tool.check', async ($, e, next) => {
    if (next.origin.plugin === $.plugin.name && /^mcp__.+__(list_watchlists|get_quotes)$/.test(e.tool)) {
      return { decision: 'allow', reason: 'Pulse CC reads your Pulse Mac watchlists and quotes to display them.' }
    }
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
        const needsSetup = watch.source === 'mac' && !watch.macConnected && !watch.groups.length
        await $.ui.open({ id: PANE, title: 'Pulse', focus: true, columns: 80,
          rows: needsSetup ? (e.presentation.columns < 64 ? 44 : 36) : Math.min(30, Math.max(22, watch.symbols.length * 3 + 20)) })
        return { text: 'Pulse panel opened.' }
      }
      if (args[0] === 'source' && args.length === 2 && (args[1] === 'cc' || args[1] === 'mac')) {
        return { text: await watch.setSource(args[1]) }
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
    const offline = watch.source === 'mac' && !watch.macConnected && !watch.loading
    const blocked = watch.source === 'mac' && !!watch.macBlocked
    const state = watch.preferences.paused ? 'Paused' : blocked ? 'Blocked' : offline ? 'Offline' : ''
    const symbols = watch.symbols
    const label = (symbol: string) => {
      const quote = watch.quotes[symbol]
      const cached = watch.errors[symbol] && quote ? ' cached' : ''
      return quote ? `${watch.label(symbol)} ${formatBandPrice(quote)} ${formatChange(quote.changePercent)}${cached}` : `${watch.label(symbol)} unavailable`
    }
    const more = (list: string[]) => list.length < symbols.length ? `   +${symbols.length - list.length} more`.length : 0
    const fits = (list: string[]) => 8 + (state ? state.length + 3 : 0) + list.map(symbol => label(symbol).length).reduce((a, b) => a + b, 0)
      + Math.max(0, list.length - 1) * 3 + more(list) <= width
    let visible = symbols.slice(0, 5)
    while (visible.length > 1 && !fits(visible)) visible = visible.slice(0, -1)
    return <Box><Text wrap="truncate">
      <Text dimColor>Pulse</Text>
      {state && <Text color="warning">{` ${state}`}</Text>}{'   '}
      {!visible.length && <Text dimColor>{watch.source === 'mac' ? 'Choose Mac tickers in /pulse' : 'Add a ticker with /pulse add AAPL'}</Text>}
      {visible.map((symbol, index) => {
        const quote = watch.quotes[symbol]
        const failed = !!watch.errors[symbol]
        return <Text key={symbol}>
          {index ? <Text dimColor>{' · '}</Text> : ''}<Text bold>{watch.label(symbol)}</Text>{' '}
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
    const { Box, Text, Button, Input, Link, Code } = $.ui.resolve(e)
    // Desktop measures cells in its code font but draws proportional text, so
    // its rows fit side by side at fewer reported columns than the terminal's.
    const compact = e.props.bodyColumns < (e.surface === 'desktop' ? 44 : 64)
    // Desktop draws native controls (hotkey badges, the field's own submit
    // button, a close button); the terminal spells those out in text.
    const desktop = e.surface === 'desktop'
    const redraw = () => $.ui.invalidate('ui.render')
    const action = (task: () => Promise<unknown>) => { void act(task).finally(redraw) }
    const addTicker = () => action(async () => { await watch.add(input); input = ''; fieldRound++ })
    const configure = () => action(async () => {
      if (desktop) { editingToken = true; return }
      await $.ui.close({ id: PANE })
      await $.command.run({ command: 'plugin', args: `configure ${$.plugin.name}` })
    })
    const saveToken = (value: string) => action(async () => {
      const typed = value.trim()
      token = ''
      fieldRound++
      notice = ''
      if (!typed) throw new Error('Paste the token from Pulse Mac → Settings → Agent access.')
      const claude = await $.env.get('CLAUDE_CODE_EXECPATH') || 'claude'
      const listed = await $.process.run([claude, 'plugin', 'list', '--json'], { stdin: '', timeoutMs: 20_000 })
      const id = listed.exitCode === 0 ? pluginID(listed.stdout, $.plugin.root) : undefined
      if (!id) throw new Error('Could not find this plugin\'s settings. Run /plugin configure pulse-cc in a terminal.')
      const saved = await $.process.run([claude, 'plugin', 'configure', id, '--values-stdin'],
        { stdin: JSON.stringify({ macToken: typed }), timeoutMs: 20_000 })
      if (saved.exitCode !== 0) throw new Error('Could not save the token. Run /plugin configure pulse-cc in a terminal.')
      hasToken = link.hasToken = true
      editingToken = false
      // The plugin's options and its MCP server read the token when a session
      // loads them, and Desktop cannot run /reload-plugins.
      notice = 'Token saved. Start a new session to connect.'
    })
    const tokenField = <Box key={`token-field-${fieldRound}`} gap={1} alignItems="center" marginTop={1}>
      <Box flexGrow={1} flexShrink={1}>
        <Input key={`mac-token-${fieldRound}`} placeholder="Paste the Pulse Mac token" value={token} submitLabel="Save" autoFocus
          onInput={value => { token = value }} onSubmit={saveToken} />
      </Box>
    </Box>
    const mac = watch.source === 'mac'
    const paused = watch.preferences.paused
    const needsSetup = mac && !watch.macConnected && !watch.groups.length
    const block = mac ? watch.macBlocked : undefined
    const showLoading = watch.loading && (!mac || (!watch.macConnected && hasToken))
    const currentGroup = watch.groups.find(group => group.id === macGroupID) ?? watch.groups[0]
    const statusColor = paused || block ? 'warning' : showLoading ? 'cyan' : mac && !watch.macConnected ? 'warning' : 'success'
    const status = paused ? '● Auto-refresh paused' : block ? '● Blocked by Claude Code permissions'
      : showLoading ? (mac ? '● Reading Pulse Mac…' : '● Refreshing quotes…')
      : mac ? (watch.macConnected ? `● Connected · Updates every ${macIntervalSeconds}s`
        : needsSetup && !hasToken ? '● Paste token to connect' : '● Not connected · Check /mcp')
        : `● Auto-refresh every ${intervalSeconds}s`
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
    // the insets stay small enough for the token field to fit a docked pane.
    const padX = desktop ? 4 : 1
    const cardX = desktop ? 2 : 1

    return <Box flexDirection="column" paddingX={padX} paddingY={desktop ? 2 : 0}>
      <Box key="source" flexDirection="column">
        {section('Quote source')}
        <Box key="source-actions" gap={1} marginTop={gap}>
          <Button key="source-cc" label="Pulse CC" variant={mac ? 'secondary' : 'primary'}
            onPress={() => action(() => watch.setSource('cc'))} />
          <Button key="source-mac" label="Pulse Mac" variant={mac ? 'primary' : 'secondary'}
            onPress={() => action(async () => {
              await watch.setSource('mac')
              if (!watch.macConnected && !watch.groups.length) await $.ui.open({ id: PANE, title: 'Pulse', focus: true,
                columns: 80, rows: compact ? 40 : 32 })
            })} />
        </Box>
        <Box marginTop={gap}><Text dimColor wrap="wrap">{mac ? 'Quotes from your Pulse Mac watchlists. Choose which ones Claude Code shows.'
          : 'An independent Claude Code watchlist for stocks and crypto.'}</Text></Box>
      </Box>

      <Box key="status-section" flexDirection="column" marginTop={space}>
        <Box justifyContent="space-between" alignItems="center" gap={2} flexWrap="wrap">
          {section(mac ? 'Pulse Mac' : `Watchlist · ${ccCount} ${ccCount === 1 ? 'ticker' : 'tickers'}`)}
          {!desktop && (!needsSetup || hasToken) && <Box key="watchlist-actions" gap={1}>
            <Button key="refresh" label="Refresh (r)" hotkey="r" dimColor onPress={() => action(() => watch.refresh())} />
            <Button key="pause" label={paused ? 'Resume (p)' : 'Pause (p)'} hotkey="p" dimColor
              onPress={() => action(() => watch.pause(!paused))} />
          </Box>}
        </Box>
        <Box marginTop={gap}><Text key="refresh-status" color={statusColor}>{status}</Text></Box>
        {desktop && (!needsSetup || hasToken) && <Box key="watchlist-actions" gap={1} marginTop={rowGap}>
          <Button key="refresh" label="Refresh" hotkey="r" onPress={() => action(() => watch.refresh())} />
          <Button key="pause" label={paused ? 'Resume' : 'Pause'} hotkey="p" onPress={() => action(() => watch.pause(!paused))} />
        </Box>}
      </Box>

      {!mac && <Box key={`add-section-${fieldRound}`} gap={1} alignItems="center" marginTop={rowGap}>
        <Box flexGrow={1} flexShrink={1}>
          <Input key="add-ticker" placeholder={compact ? 'AAPL, BTC/USDT' : 'Add a ticker: AAPL, 0700.HK, BTC/USDT'} value={input}
            submitLabel={desktop ? 'Add' : 'add'} autoFocus onInput={value => { input = value }}
            onSubmit={value => { input = value; addTicker() }} />
        </Box>
        {!desktop && <Button key="add" label="Add" onPress={addTicker} />}
      </Box>}
      {error && <Box marginTop={rowGap}><Text color="error" wrap="wrap">{error}</Text></Box>}
      {watch.message && !needsSetup && <Box marginTop={1}>
        <Text color={watch.message.includes('rate limited') ? 'warning' : undefined} dimColor={!watch.message.includes('rate limited')} wrap="wrap">{watch.message}</Text>
      </Box>}

      {!mac && <Box key="watchlist" flexDirection="column" marginTop={rowGap}>
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
      </Box>}

      {block && <Box key="mac-permission" flexDirection="column" borderStyle="round" borderColor="warning"
        paddingX={cardX} paddingY={desktop ? 2 : 0} marginTop={rowGap}>
        <Text bold>Claude Code blocked the Pulse Mac read</Text>
        <Box marginTop={gap}><Text dimColor wrap="wrap">Your token is set and the connection is up, but Claude Code's
          permission check refused the background read.</Text></Box>
        <Box key="mac-permission-error" flexDirection="column" marginTop={rowGap}>
          <Text dimColor>Error</Text>
          <Text color="warning" wrap="wrap">{block.detail}</Text>
        </Box>
        <Box flexDirection="column" marginTop={rowGap}>
          <Text wrap="wrap">Allow these read-only tools in <Text bold>~/.claude/settings.json</Text>
            {desktop ? '' : ' or with /permissions'}, then start a new session:</Text>
          <Box marginTop={gap}>
            <Code language="json"
              source={JSON.stringify({ permissions: { allow: block.rules } }, null, 2)} />
          </Box>
        </Box>
        <Box marginTop={gap}><Text dimColor wrap="wrap">Writes such as adding tickers or recording trades still ask first.</Text></Box>
      </Box>}

      {needsSetup && !block && <Box key="mac-setup" flexDirection="column" borderStyle="round" borderColor="cyan"
        paddingX={cardX} paddingY={desktop ? 2 : 0} marginTop={rowGap}>
        <Text bold>Connect Pulse Mac</Text>
        <Box marginTop={gap}><Text dimColor wrap="wrap">Your markets in the Mac menu bar: stocks, crypto, charts and positions.</Text></Box>
        <Box flexDirection="column" marginTop={rowGap}>
          <Text wrap="wrap"><Text color="cyan">{'1  '}</Text><Link href="https://www.pulseticker.app/"><Text color="cyan">Download Pulse Mac ↗</Text></Link>, then open it.</Text>
          <Text wrap="wrap"><Text color="cyan">{'2  '}</Text>Enable MCP in <Text bold>Settings → Agent access</Text> and copy the token.</Text>
          {desktop ? <Text wrap="wrap"><Text color="cyan">{'3  '}</Text>Paste it below and press <Text bold>Save</Text>.</Text>
            : <Text wrap="wrap"><Text color="cyan">{'3  '}</Text>Click <Text bold>{hasToken ? 'Update token' : 'Paste token'}</Text> below to open configuration.</Text>}
        </Box>
        {desktop ? <Box marginTop={1}>{tokenField}</Box> : <Box marginTop={1}>
          <Button key="mac-configure" label={hasToken ? 'Update token' : 'Paste token'} variant="primary" onPress={configure} />
        </Box>}
        <Box marginTop={gap}><Text dimColor wrap="wrap">{desktop ? 'Saved in Claude Code\'s secure storage, never in Pulse settings.'
          : 'In the window that opens, paste into Pulse Mac token and save. Then reopen /pulse.'}
          {' The local connection is included; keep Pulse Mac open.'}</Text></Box>
        {notice && <Box marginTop={gap}><Text color="success" wrap="wrap">{notice}</Text></Box>}
        {watch.message && !watch.message.startsWith('Could not reach Pulse Mac.') && !watch.message.startsWith('Paste your Pulse Mac token')
          && <Text color="warning" wrap="wrap">{watch.message}</Text>}
      </Box>}

      {mac && watch.macConnected && !watch.groups.length && <Box marginTop={1}><Text dimColor wrap="wrap">No watchlist groups in Pulse Mac.</Text></Box>}
      {mac && watch.groups.length > 0 && <Box key="mac-groups" gap={1} flexWrap="wrap" marginTop={rowGap}>
        {watch.groups.map(group => <Button key={`mac-group-select-${group.id}`} label={group.name}
          variant={currentGroup?.id === group.id ? 'primary' : 'secondary'}
          onPress={() => { macGroupID = group.id; redraw() }} />)}
      </Box>}
      {mac && currentGroup && [currentGroup].map(group => <Box key={`mac-group-${group.id}`} flexDirection="column" marginTop={rowGap}>
        <Box gap={1}>
          <Text bold>{group.name}</Text>
          <Text dimColor>{`${group.symbols.length} tickers`}</Text>
        </Box>
        {!group.symbols.length && <Text dimColor>Empty group</Text>}
        {group.symbols.map(item => {
          const key = symbolKey(item)
          const selected = watch.macPreferences.selected.some(ref => symbolKey(ref) === key)
          const quote = watch.quotes[key], failed = watch.errors[key]
          const price = selected && quote ? <Text dimColor={!!failed}>{formatPrice(quote)}</Text> : undefined
          const change = selected && quote ? <Text color={changeColor(quote.changePercent)}>{formatChange(quote.changePercent)}</Text> : undefined
          const stale = selected && quote ? formatStaleDate(quote.timestamp, now) : ''
          const meta = stale ? `${item.name} · As of ${stale}` : item.name
          return <Box key={`mac-row-${group.id}-${key}`} flexDirection="column" width="100%" marginTop={rowGap}>
            <Box gap={2} alignItems="center" width="100%">
              <Box flexDirection="column" flexGrow={1} flexShrink={1} minWidth={0}>
                <Text bold wrap="truncate">{`${item.displayCode} · ${item.market.toUpperCase()}`}</Text>
                {!compact && <Text dimColor wrap="truncate">{meta}</Text>}
              </Box>
              {!compact && price && <Box flexDirection="column" alignItems="flex-end" flexShrink={0}>{price}{change}</Box>}
              <Button key={`mac-toggle-${group.id}-${key}`} label={selected ? '✓ Shown' : 'Show'}
                variant={selected ? 'primary' : 'secondary'} onPress={() => action(() => watch.toggleMac({ market: item.market, code: item.code }))} />
            </Box>
            {compact && price && <Box gap={2}>{price}{change}</Box>}
            {compact && <Text dimColor wrap="truncate">{meta}</Text>}
            {selected && failed && <Text color="warning" wrap="wrap">{quote ? 'Cached quote · ' : ''}{failed}</Text>}
          </Box>
        })}
      </Box>)}

      <Box key="footer" flexDirection="column" marginTop={space}>
        {mac && !needsSetup && <Box gap={2} alignItems="center" flexWrap="wrap">
          <Text dimColor wrap="wrap">{`MCP ${link.server} · Keep Pulse Mac open with Agent access enabled.`}</Text>
          {!(desktop && editingToken) && <Button key="mac-configure" label="Update token" dimColor onPress={configure} />}
          {!watch.macConnected && <Link href="https://github.com/fatwang2/Pulse/tree/main/plugins/claude-code#connect-pulse-mac"><Text color="cyan">Connection guide ↗</Text></Link>}
        </Box>}
        {mac && !needsSetup && desktop && editingToken && tokenField}
        {mac && !needsSetup && notice && <Text color="success" wrap="wrap">{notice}</Text>}
        <Text dimColor wrap="wrap">
          {mac ? 'Pulse Mac · Cached app quotes · Provider timestamps · Times are local · '
            : watch.preferences.symbols.some(isCryptoPair)
              ? 'Yahoo Finance · Binance Spot · Stocks: regular session, exchange delays vary · Crypto: 24h change · Times are local · '
              : 'Yahoo Finance · Regular-session quotes · Exchange delays vary · Times are local · '}
          <Link href="https://www.pulseticker.app/">pulseticker.app</Link>
        </Text>
        {!desktop && <Text dimColor wrap="wrap">Tab: move between controls · Enter: activate · Esc: return to prompt</Text>}
      </Box>
    </Box>
  })
}

// The full plugin id (name@marketplace, or name@inline for a local folder) is
// what `claude plugin configure` takes; match it by this plugin's own root.
function pluginID(listJSON: string, root: string): string | undefined {
  try {
    const listed: unknown = JSON.parse(listJSON)
    const plugins = Array.isArray(listed) ? listed : []
    const match = plugins.find((plugin: { installPath?: unknown, enabled?: unknown }) =>
      plugin.installPath === root && plugin.enabled !== false) as { id?: unknown } | undefined
    return typeof match?.id === 'string' ? match.id : undefined
  } catch { return undefined }
}

function changeColor(change: number | null): string | undefined {
  return change === null ? undefined : change >= 0 ? 'green' : 'red'
}

type MacLink = { server: string, hasToken: boolean }

function startWatch($: EngineInterface, watch: Watchlist, mac: MacLink): Promise<void> {
  return watch.start({
    load: () => $.store.get(SETTINGS_KEY),
    save: preferences => $.store.set(SETTINGS_KEY, preferences),
    loadMac: () => $.store.get(MAC_SETTINGS_KEY),
    saveMac: preferences => $.store.set(MAC_SETTINGS_KEY, preferences),
    listMac: async () => {
      const connection = await $.mcp.connect('pulse')
      if (!connection.isConnected) throw new MacError(macConnectionMessage(connection.reason, mac.hasToken))
      mac.server = connection.server
      return $.mcp.call(mac.server, 'list_watchlists', {})
    },
    quoteMac: symbols => $.mcp.call(mac.server, 'get_quotes', { symbols }),
    now: () => $.clock.now(),
    sleep: ms => $.clock.sleep(ms),
    after: (ms, callback) => $.clock.after(ms, callback),
    fetch: url => $.http.fetch(url, {
      headers: { 'User-Agent': 'Pulse-CC/0.3.6', Accept: 'application/json' },
    }),
    redraw: () => $.ui.invalidate('ui.render'),
  })
}

function macConnectionMessage(reason: string, hasToken: boolean): string {
  if (reason === 'disabled') return 'Pulse Mac connection is disabled. Enable it in /mcp to reconnect.'
  if (reason === 'policy') return 'Pulse Mac connection is blocked by your Claude Code organization policy.'
  if (reason === 'unapproved') return 'Approve the Pulse Mac connection in /mcp, then refresh.'
  if (!hasToken) return 'Paste your Pulse Mac token to connect.'
  return 'Could not connect. Keep Pulse Mac open with MCP enabled and check your token.'
}
