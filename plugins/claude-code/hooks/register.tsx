import type { Register } from 'claude-code'
import { SETTINGS_KEY, Watchlist } from './watchlist'
import { formatChange, formatPrice, formatBandPrice, formatTime } from './yahoo'
import { MAC_SETTINGS_KEY, MacError, symbolKey } from './mac'

export const PANE = 'pulse-quotes'
const HELP = '/pulse · /pulse source cc|mac · /pulse add AAPL · /pulse remove AAPL · /pulse refresh · /pulse off · /pulse on'

export const register: Register = (on, options) => {
  const intervalSeconds = 60
  const macIntervalSeconds = 5
  const hasToken = typeof options.macToken === 'string' && !!options.macToken.trim()
  let server = 'plugin:pulse-cc:pulse'
  const watch = new Watchlist(intervalSeconds * 1000, macIntervalSeconds * 1000)
  let input = ''
  let error = ''
  let macGroupID: string | undefined

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
      loadMac: () => $.store.get(MAC_SETTINGS_KEY),
      saveMac: preferences => $.store.set(MAC_SETTINGS_KEY, preferences),
      listMac: async () => {
        const connection = await $.mcp.connect('pulse')
        if (!connection.isConnected) throw new MacError(macConnectionMessage(connection.reason, hasToken))
        server = connection.server
        return $.mcp.call(server, 'list_watchlists', {})
      },
      quoteMac: symbols => $.mcp.call(server, 'get_quotes', { symbols }),
      now: () => $.clock.now(),
      sleep: ms => $.clock.sleep(ms),
      after: (ms, callback) => $.clock.after(ms, callback),
      fetch: url => $.http.fetch(url, {
        headers: { 'User-Agent': 'Pulse-CC/0.3.1', Accept: 'application/json' },
      }),
      redraw: () => $.ui.invalidate('ui.render'),
    })
    await $.command.register({
      name: 'pulse', description: 'Watch quotes from Yahoo Finance or your Pulse Mac watchlists',
      argumentHint: '[source cc|mac | add <ticker> | remove <ticker> | refresh | off | on]',
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
    const prefix = watch.preferences.paused || offline ? 16 : 8
    const symbols = watch.symbols
    const label = (symbol: string) => {
      const quote = watch.quotes[symbol]
      const cached = watch.errors[symbol] && quote ? ' cached' : ''
      return quote ? `${watch.label(symbol)} ${formatBandPrice(quote)} ${formatChange(quote.changePercent)}${cached}` : `${watch.label(symbol)} unavailable`
    }
    const fits = (list: string[]) => prefix + list.map(symbol => label(symbol).length).reduce((a, b) => a + b, 0)
      + Math.max(0, list.length - 1) * 3 + (list.length < symbols.length ? ` · +${symbols.length - list.length}`.length : 0) <= width
    let visible = symbols.slice(0, 5)
    while (visible.length > 1 && !fits(visible)) visible = visible.slice(0, -1)
    return <Box><Text wrap="truncate">
      <Text bold>Pulse</Text>{watch.preferences.paused ? ' paused' : offline ? ' offline' : ''}{' · '}
      {!visible.length && <Text dimColor>{watch.source === 'mac' ? '/pulse · select Mac tickers' : '/pulse add AAPL'}</Text>}
      {visible.map((symbol, index) => {
        const quote = watch.quotes[symbol]
        const failed = !!watch.errors[symbol]
        return <Text key={symbol}>
          {index ? ' · ' : ''}<Text bold>{watch.label(symbol)}</Text>{' '}
          {quote ? <Text dimColor={failed}>{formatBandPrice(quote)}{' '}
            <Text color={quote.changePercent === null ? undefined : quote.changePercent >= 0 ? 'green' : 'red'}>
              {formatChange(quote.changePercent)}
            </Text>{failed ? ' cached' : ''}
          </Text> : <Text dimColor>{failed ? 'unavailable' : '…'}</Text>}
        </Text>
      })}
      {visible.length < symbols.length && <Text dimColor>{` · +${symbols.length - visible.length}`}</Text>}
    </Text></Box>
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const { Box, Text, Button, Input, Link } = $.ui.resolve(e)
    const compact = e.props.bodyColumns < 64
    const redraw = () => $.ui.invalidate('ui.render')
    const action = (task: () => Promise<unknown>) => { void act(task).finally(redraw) }
    const addTicker = () => action(async () => { await watch.add(input); input = '' })
    const rule = '─'.repeat(Math.max(8, e.props.bodyColumns - 2))
    const sourceWidth = Math.max(14, Math.floor((e.props.bodyColumns - 3) / 2))
    const mac = watch.source === 'mac'
    const needsSetup = mac && !watch.macConnected && !watch.groups.length
    const showLoading = watch.loading && (!mac || (!watch.macConnected && hasToken))
    const currentGroup = watch.groups.find(group => group.id === macGroupID) ?? watch.groups[0]
    return <Box flexDirection="column" paddingX={1}>
      <Text bold color="cyan">Quote source</Text>
      <Box key="source-actions" gap={1} marginBottom={1} flexWrap="wrap">
        <Box key="source-cc-card" width={sourceWidth} flexDirection="column" borderStyle="round"
          borderColor={mac ? 'gray' : 'cyan'} paddingX={1}>
          <Button key="source-cc" label="Pulse CC" variant={mac ? 'secondary' : 'primary'}
            onPress={() => action(() => watch.setSource('cc'))} />
          <Text color={mac ? undefined : 'cyan'} dimColor={mac} wrap="wrap">Yahoo Finance</Text>
        </Box>
        <Box key="source-mac-card" width={sourceWidth} flexDirection="column" borderStyle="round"
          borderColor={mac ? 'cyan' : 'gray'} paddingX={1}>
          <Button key="source-mac" label="Pulse Mac" variant={mac ? 'primary' : 'secondary'}
            onPress={() => action(async () => {
              await watch.setSource('mac')
              if (!watch.macConnected && !watch.groups.length) await $.ui.open({ id: PANE, title: 'Pulse', focus: true,
                columns: 80, rows: compact ? 44 : 36 })
            })} />
          <Text color={mac ? 'cyan' : undefined} dimColor={!mac} wrap="wrap">From your Mac app</Text>
        </Box>
      </Box>
      <Box gap={2} flexWrap="wrap">
        <Text bold>{mac ? 'Pulse Mac watchlists' : 'Pulse CC watchlist'}</Text>
        {!needsSetup && <Text bold color="cyan">{mac ? `${watch.symbols.length} selected`
          : `${watch.preferences.symbols.length} ${watch.preferences.symbols.length === 1 ? 'ticker' : 'tickers'}`}</Text>}
      </Box>
      {!mac && <Text dimColor wrap="wrap">Manage an independent watchlist.</Text>}
      <Text key="refresh-status" color={watch.preferences.paused ? 'yellow' : showLoading ? 'cyan' : mac && !watch.macConnected ? 'yellow' : 'green'}>
        {watch.preferences.paused ? '● Auto-refresh paused' : showLoading ? (mac ? '● Reading Pulse Mac…' : '● Refreshing quotes…')
          : mac ? (watch.macConnected ? `● Connected · Updates every ${macIntervalSeconds}s`
            : needsSetup && !hasToken ? '● Paste token to connect' : '● Not connected · Check /mcp')
            : `● Auto-refresh every ${intervalSeconds}s`}
      </Text>
      {(!needsSetup || hasToken) && <Box key="watchlist-actions" gap={2} marginTop={1} marginBottom={1} flexWrap="wrap">
        <Button key="refresh" label="Refresh (r)" hotkey="r" onPress={() => action(() => watch.refresh())} />
        <Button key="pause" label={watch.preferences.paused ? 'Resume (p)' : 'Pause (p)'} hotkey="p"
          onPress={() => action(() => watch.pause(!watch.preferences.paused))} />
      </Box>}
      {!mac && <Box key="add-section" flexDirection="column" borderStyle="round" borderColor="cyan" paddingX={1} marginBottom={1}>
        <Text bold color="cyan">Add ticker</Text>
        <Box gap={2} alignItems="center">
          <Box flexGrow={1} flexShrink={1}>
            <Input key="add-ticker" placeholder={compact ? 'AAPL, 0700.HK' : 'AAPL, 0700.HK, ^GSPC'} value={input}
              submitLabel="add" autoFocus onInput={value => { input = value }}
              onSubmit={value => { input = value; addTicker() }} />
          </Box>
          <Button key="add" label="Add" onPress={addTicker} />
        </Box>
      </Box>}
      {error && <Box marginBottom={1}><Text color="red" wrap="wrap">{error}</Text></Box>}
      {watch.message && !needsSetup && <Box marginBottom={1}><Text color={watch.message.includes('rate limited') ? 'yellow' : undefined} wrap="wrap">{watch.message}</Text></Box>}
      {needsSetup && <Box key="mac-setup" flexDirection="column" borderStyle="round" borderColor="cyan" paddingX={1} marginY={1}>
        <Text bold color="cyan">Connect Pulse Mac</Text>
        <Text bold wrap="wrap">Your markets, right in your Mac menu bar.</Text>
        <Text dimColor wrap="wrap">Watch stocks and crypto, explore charts, and track positions.</Text>
        <Box flexDirection="column" marginY={1}>
          <Text wrap="wrap"><Link href="https://www.pulseticker.app/"><Text bold color="cyan">Download Pulse Mac ↗</Text></Link></Text>
        </Box>
        <Text wrap="wrap"><Text bold color="cyan">1. </Text>Install and open Pulse Mac.</Text>
        <Text wrap="wrap"><Text bold color="cyan">2. </Text>Enable MCP in <Text bold>Settings → Agent access</Text> and copy the token.</Text>
        <Text wrap="wrap"><Text bold color="cyan">3. </Text>Click <Text bold>{hasToken ? 'Update token' : 'Paste token'}</Text> below to open configuration.</Text>
        <Box marginY={1}>
          <Button key="mac-configure" label={hasToken ? 'Update token' : 'Paste token'} variant="primary"
            onPress={() => action(async () => {
              await $.ui.close({ id: PANE })
              await $.command.run({ command: e.surface === 'terminal' ? 'plugin' : 'config',
                args: e.surface === 'terminal' ? `configure ${$.plugin.name}` : '' })
            })} />
        </Box>
        <Text dimColor wrap="wrap">{e.surface === 'terminal'
          ? 'In the window that opens, paste into Pulse Mac token and save. Then reopen /pulse.'
          : 'In /config → pulse-cc, paste the Pulse Mac token, then reload the plugin.'}</Text>
        <Text dimColor wrap="wrap">The local connection is included. Keep Pulse Mac open.</Text>
        {watch.message && !watch.message.startsWith('Could not reach Pulse Mac.') && !watch.message.startsWith('Paste your Pulse Mac token')
          && <Text color="yellow" wrap="wrap">{watch.message}</Text>}
      </Box>}
      {mac && !needsSetup && <Box key="mac-notes" flexDirection="column" borderStyle="round" borderColor="cyan" paddingX={1} marginBottom={1}>
        <Text bold color="cyan">Choose which Mac tickers to display</Text>
        <Text dimColor wrap="wrap">Manage tickers and groups in Pulse Mac. These controls only change this display.</Text>
        <Text dimColor wrap="wrap">{`MCP server: ${server} · Keep Pulse Mac open with Agent access enabled.`}</Text>
        <Box marginTop={1} gap={2} flexWrap="wrap">
          <Button key="mac-configure" label="Update token" onPress={() => action(async () => {
            await $.ui.close({ id: PANE })
            await $.command.run({ command: e.surface === 'terminal' ? 'plugin' : 'config',
              args: e.surface === 'terminal' ? `configure ${$.plugin.name}` : '' })
          })} />
          {!watch.macConnected && <Link href="https://github.com/fatwang2/Pulse/tree/main/plugins/claude-code#connect-pulse-mac"><Text color="cyan">Connection guide ↗</Text></Link>}
        </Box>
      </Box>}
      {mac && watch.macConnected && !watch.groups.length && <Text dimColor wrap="wrap">No watchlist groups in Pulse Mac.</Text>}
      {mac && watch.groups.length > 0 && <Box key="mac-groups" gap={1} flexWrap="wrap" marginBottom={1}>
        {watch.groups.map(group => <Button key={`mac-group-select-${group.id}`} label={group.name}
          variant={currentGroup?.id === group.id ? 'primary' : 'secondary'}
          onPress={() => { macGroupID = group.id; redraw() }} />)}
      </Box>}
      {mac && currentGroup && [currentGroup].map(group => <Box key={`mac-group-${group.id}`} flexDirection="column" marginBottom={1}>
        <Box gap={2} marginBottom={1}><Text bold color="cyan">{group.name}</Text><Text dimColor>{`${group.symbols.length} tickers`}</Text></Box>
        {!group.symbols.length && <Text dimColor>Empty group</Text>}
        {group.symbols.map(item => {
          const key = symbolKey(item)
          const selected = watch.macPreferences.selected.some(ref => symbolKey(ref) === key)
          const quote = watch.quotes[key], failed = watch.errors[key]
          return <Box key={`mac-row-${group.id}-${key}`} flexDirection="column" marginBottom={1}>
            <Box gap={2} justifyContent="space-between" alignItems="center">
              <Box flexGrow={1} flexShrink={1}><Text bold wrap="truncate">{`${item.displayCode} · ${item.market.toUpperCase()}`}</Text></Box>
              {!compact && selected && <Text dimColor={!quote || !!failed}>{quote ? formatPrice(quote) : '—'}</Text>}
              <Button key={`mac-toggle-${group.id}-${key}`} label={selected ? '✓ Shown' : 'Show'}
                variant={selected ? 'primary' : 'secondary'} onPress={() => action(() => watch.toggleMac({ market: item.market, code: item.code }))} />
            </Box>
            <Text dimColor wrap="truncate">{item.name}</Text>
            {selected && quote && <Text wrap="wrap">
              {compact && <Text dimColor={!!failed}>{`${formatPrice(quote)} · `}</Text>}
              <Text color={quote.changePercent === null ? undefined : quote.changePercent >= 0 ? 'green' : 'red'}>
                {formatChange(quote.changePercent)}
              </Text><Text dimColor>{` · As of ${formatTime(quote.timestamp)}`}</Text>
            </Text>}
            {selected && failed && <Text color="yellow" wrap="wrap">{quote ? 'Cached quote · ' : ''}{failed}</Text>}
          </Box>
        })}
      </Box>)}
      {!mac && !watch.preferences.symbols.length && <Box marginY={1}><Text dimColor>Your watchlist is empty. Add a ticker above.</Text></Box>}
      {!mac && watch.preferences.symbols.length > 0 && !compact && <Box marginBottom={1} justifyContent="space-between">
        <Box gap={2}>
          <Box width={12}><Text dimColor>TICKER</Text></Box>
          <Box width={16} justifyContent="flex-end"><Text dimColor>PRICE</Text></Box>
          <Box width={10} justifyContent="flex-end"><Text dimColor>CHANGE</Text></Box>
        </Box>
        <Text dimColor>ACTION</Text>
      </Box>}
      {!mac && watch.preferences.symbols.map(symbol => {
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
      <Text dimColor wrap="wrap">{mac ? 'Pulse Mac · Cached app quotes · Provider timestamps · Times are local.'
        : 'Yahoo Finance · Regular-session quotes · Exchange delays vary · Times are local.'}</Text>
      <Text dimColor wrap="wrap">Tab: move between controls · Enter: activate · Esc: return to prompt</Text>
      <Text><Text dimColor>Website: </Text><Link href="https://www.pulseticker.app/"><Text color="cyan">pulseticker.app</Text></Link></Text>
    </Box>
  })
}

function macConnectionMessage(reason: string, hasToken: boolean): string {
  if (reason === 'disabled') return 'Pulse Mac connection is disabled. Enable it in /mcp to reconnect.'
  if (reason === 'policy') return 'Pulse Mac connection is blocked by your Claude Code organization policy.'
  if (reason === 'unapproved') return 'Approve the Pulse Mac connection in /mcp, then refresh.'
  if (!hasToken) return 'Paste your Pulse Mac token to connect.'
  return 'Could not connect. Keep Pulse Mac open with MCP enabled and check your token.'
}
