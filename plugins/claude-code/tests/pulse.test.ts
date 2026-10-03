import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { SETTINGS_KEY } from '../hooks/watchlist'
import { MAC_SETTINGS_KEY, decodeMacQuotes, decodeWatchlists, readMacPreferences } from '../hooks/mac'
import type { MacGroup } from '../hooks/mac'
import type { McpToolResult } from 'claude-code'
import { decodeQuote, formatBandPrice, formatPrice, normalizeSymbol, quoteURL, YahooError } from '../hooks/yahoo'

const PLUGIN = 'pulse-cc'
const NOW = 1_790_965_500_000
const START = { surface: 'terminal', isInteractive: true, cwd: '/test' } as const
const PANE = {
  plugin: PLUGIN, component: 'Pane', requestId: 'pulse-quotes',
  viewport: { columns: 100, rows: 30 },
  props: { title: 'Pulse', isFocused: true, bodyColumns: 80, placement: 'inline', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const
const BAND = {
  plugin: PLUGIN, component: 'AbovePrompt', viewport: { columns: 80, rows: 30 },
  props: { hasSurvey: false, isWorking: false, maxRows: 2, bodyColumns: 80, scroll: { offset: 0, bodyRows: 2 }, view: {} },
} as const

function response(symbol = 'AAPL', price = 100, close: number | null = 80) {
  return {
    ok: true, status: 200, headers: {},
    text: JSON.stringify({ chart: { error: null, result: [{ meta: {
      symbol, shortName: 'Example', regularMarketPrice: price, chartPreviousClose: close,
      regularMarketTime: NOW / 1000 - 10, currency: 'USD',
    }, timestamp: [NOW / 1000 - 180, NOW / 1000 - 120, NOW / 1000 - 60],
    indicators: { quote: [{ open: [90, 95, 100], high: [94, 100, 105], low: [89, 94, 99],
      close: [92, 98, 103], volume: [100, 200, 300] }] }, }] } }),
  }
}

function host(on: On, symbols: string[] = [], paused = false) {
  const clock = mock.clock(on, { now: NOW })
  const saved = new Map<string, unknown>([[SETTINGS_KEY, { version: 1, symbols, paused }]])
  on('store.get', (_, e) => ({ value: saved.get(e.key) }))
  on('store.set', (_, e) => { saved.set(e.key, e.value); return { value: undefined } })
  on('command.register', () => ({ value: { command: 'pulse' } }))
  on('session.start', () => ({ cwd: '/test' }))
  on('session.end', () => ({ sessionId: 'test' }))
  let paneOpen = false
  on('ui.panes', () => ({ value: paneOpen ? [{ id: 'pulse-quotes', title: 'Pulse', isShown: true, isFocused: true, isPlaced: true }] : [] }))
  on('ui.open', () => { paneOpen = true; return { value: { isPlaced: true } } })
  on('ui.close', () => { paneOpen = false; return { value: undefined } })
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['Host content'] }))
  return { clock, saved }
}

const command = ($: Engine, args: string) => $.command.run({
  command: 'pulse', args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 },
})

test('Yahoo decoding uses previous close, preserves unknown delay, and rejects a mismatched instrument', () => {
  const quote = decodeQuote('AAPL', response(), NOW)
  expect(quote.changePercent).toBe(25)
  expect(quote.delaySeconds).toBe(null)
  expect(quote.timestamp).toBe(NOW - 10_000)
  expect(decodeQuote('AAPL', response('AAPL', 100, null), NOW).changePercent).toBe(null)
  expect(() => decodeQuote('AAPL', response('MSFT'), NOW)).toThrow('different ticker')
  expect(() => decodeQuote('AAPL', response('AAPL', 0), NOW)).toThrow('incomplete quote')
  expect(normalizeSymbol('00700.hk')).toBe('0700.HK')
  expect(normalizeSymbol('600519.SH')).toBe('600519.SS')
  expect(quoteURL('^GSPC')).toContain('%5EGSPC')
  expect(() => normalizeSymbol('https://example.com')).toThrow()
})

test('a new installation is empty; adding, de-duplicating and removing tickers persists locally', async ($, on) => {
  const { clock, saved } = host(on)
  let requests = 0
  on('http.fetch', () => { requests++; return { value: response() } })
  await $.session.start(START)
  await clock.advance(60_000)
  expect(requests).toBe(0)
  expect((await command($, 'add aapl')).text).toBe('Added AAPL.')
  await clock.settle()
  expect(requests).toBe(1)
  expect((await command($, 'add AAPL')).text).toContain('already')
  expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: ['AAPL'], paused: false })
  await command($, 'remove AAPL')
  await clock.advance(120_000)
  expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: [], paused: false })
  expect(requests).toBe(1)
})

test('quotes are spaced apart, refreshed on a timer, and show source times in both surfaces', async ($, on) => {
  const { clock } = host(on, ['AAPL', 'MSFT'])
  const requests: number[] = []
  on('http.fetch', (_, e) => {
    requests.push(clock.now())
    return { value: response(e.url.includes('MSFT') ? 'MSFT' : 'AAPL') }
  })
  await $.session.start(START)
  await clock.settle()
  expect(requests).toEqual([NOW])
  await clock.advance(1000)
  expect(requests).toEqual([NOW, NOW + 1000])
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /As of/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Exchange delays vary/ })).toBeDefined()
    await ui.unmount()
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: /AAPL.*100\.00/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /USD/ })).toBe(undefined)
    await band.unmount()
  }
  await clock.advance(60_000)
  expect(requests.length).toBe(3)
  await clock.advance(1000)
  expect(requests.length).toBe(4)
})

test('pause persists across session starts; manual refresh fetches once without resuming polling', async ($, on) => {
  const { clock, saved } = host(on, ['AAPL'], true)
  let requests = 0
  on('http.fetch', () => { requests++; return { value: response() } })
  await $.session.start(START)
  await clock.advance(120_000)
  expect(requests).toBe(0)
  await command($, 'refresh')
  await clock.settle()
  expect(requests).toBe(1)
  await clock.advance(120_000)
  expect(requests).toBe(1)
  expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: ['AAPL'], paused: true })
  await command($, 'on')
  await clock.settle()
  expect(requests).toBe(2)
  await command($, 'off')
  await clock.advance(120_000)
  expect(requests).toBe(2)
})

test('429 defers the whole round, honors Retry-After, and manual refresh cannot bypass cooldown', async ($, on) => {
  const { clock } = host(on, ['AAPL', 'MSFT'])
  const requests: number[] = []
  on('http.fetch', (_, e) => {
    requests.push(clock.now())
    return { value: requests.length === 1
      ? { ok: false, status: 429, headers: { 'retry-after': '120' }, text: '' }
      : response(e.url.includes('MSFT') ? 'MSFT' : 'AAPL') }
  })
  await $.session.start(START)
  await clock.settle()
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Refresh deferred/ })).toBeDefined()
  await command($, 'refresh')
  await clock.settle()
  await clock.advance(119_999)
  expect(requests).toEqual([NOW])
  await clock.advance(1)
  expect(requests).toEqual([NOW, NOW + 120_000])
  await clock.advance(1000)
  expect(requests.length).toBe(3)
  expect(await ui.find({ type: 'Text', text: /Refresh deferred/ })).toBe(undefined)
  await ui.unmount()
})

test('a failed refresh keeps the last quote but clearly labels it cached', async ($, on) => {
  const { clock } = host(on, ['AAPL'])
  let requests = 0
  on('http.fetch', () => ({ value: ++requests === 1 ? response()
    : { ok: false, status: 503, headers: {}, text: 'untrusted server body' } }))
  await $.session.start(START)
  await clock.settle()
  await clock.advance(60_000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /100\.00 USD/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Cached quote.*HTTP 503/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /untrusted server body/ })).toBe(undefined)
  await ui.unmount()
})

test('removal during a request discards its late result and stops the remaining round', async ($, on) => {
  const { clock } = host(on, ['AAPL', 'MSFT'])
  let requests = 0
  on('http.fetch', async () => {
    requests++
    await clock.sleep(2000)
    return { value: response() }
  })
  await $.session.start(START)
  await clock.settle()
  await command($, 'remove AAPL')
  await command($, 'off')
  await clock.advance(2000)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /100\.00 USD/ })).toBe(undefined)
  expect(requests).toBe(1)
  await clock.advance(120_000)
  expect(requests).toBe(1)
  await ui.unmount()
})

test('simultaneous manual refreshes share the active request', async ($, on) => {
  const { clock } = host(on, ['AAPL'], true)
  let requests = 0
  on('http.fetch', async () => { requests++; await clock.sleep(2000); return { value: response() } })
  await $.session.start(START)
  await command($, 'refresh')
  await command($, 'refresh')
  await clock.settle()
  expect(requests).toBe(1)
  await clock.advance(2000)
  expect(requests).toBe(1)
})

test('panel input and remove button work on terminal and desktop, including narrow layouts', async ($, on) => {
  const { clock, saved } = host(on, [], true)
  on('http.fetch', () => ({ value: response() }))
  await $.session.start(START)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns: 40 }, surface })
    await ui.input({ key: 'add-ticker', text: 'AAPL' })
    await clock.settle()
    expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: ['AAPL'], paused: true })
    expect(await ui.find({ key: 'remove-AAPL' })).toBeDefined()
    await ui.press({ key: 'remove-AAPL' })
    await clock.settle()
    expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: [], paused: true })
    await ui.unmount()
  }
})

test('the explicit Add button uses the edited field and management controls remain usable on both layouts', async ($, on) => {
  const { clock, saved } = host(on, [], true)
  on('http.fetch', () => ({ value: response() }))
  await $.session.start(START)
  for (const surface of ['terminal', 'desktop'] as const) {
    for (const bodyColumns of [40, 100]) {
      const ui = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns }, surface })
      await ui.press({ key: 'add' })
      await clock.settle()
      expect(await ui.find({ type: 'Text', text: /Enter a Yahoo ticker/ }), `empty Add should show validation on ${surface}/${bodyColumns}`).toBeDefined()
      await ui.input({ key: 'add-ticker', text: 'aapl', kind: 'change' })
      await ui.press({ key: 'add' })
      await clock.settle()
      expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: ['AAPL'], paused: true })
      expect((await ui.find({ key: 'add-ticker' }))?.props.value).toBe('')
      expect(await ui.find({ type: 'Text', text: /Enter a Yahoo ticker/ })).toBe(undefined)
      expect(await ui.find({ key: 'remove-AAPL' })).toBeDefined()
      await ui.press({ key: 'pause' })
      await clock.settle()
      expect((await ui.find({ key: 'pause' }))?.text).toBe('Pause (p)')
      await clock.advance(1000)
      expect(await ui.find({ type: 'Text', text: /Auto-refresh every 60s/ })).toBeDefined()
      await ui.press({ key: 'pause' })
      await clock.settle()
      expect((await ui.find({ key: 'pause' }))?.text).toBe('Resume (p)')
      await ui.press({ key: 'remove-AAPL' })
      await clock.settle()
      expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: [], paused: true })
      await ui.unmount()
    }
  }
})

test('headless sessions never fetch; exiting cancels polling; clearing retains it', async ($, on) => {
  const { clock } = host(on, ['AAPL'])
  let requests = 0
  on('http.fetch', () => { requests++; return { value: response() } })
  await $.session.start({ ...START, isInteractive: false })
  await clock.advance(120_000)
  expect(requests).toBe(0)
  await $.session.start(START)
  await clock.settle()
  expect(requests).toBe(1)
  await $.session.end({ reason: 'clear', sessionId: 'test', resume: { id: 'test' } })
  await clock.advance(60_000)
  expect(requests).toBe(2)
  await $.session.end({ reason: 'prompt_input_exit', sessionId: 'test', resume: { id: 'test' } })
  await clock.advance(120_000)
  expect(requests).toBe(2)
})

test('Retry-After accepts an HTTP date and malformed values use a safe minimum', () => {
  for (const [retry, expected] of [['garbage', 60_000], ['0', 60_000], [new Date(NOW + 120_000).toUTCString(), 120_000]] as const) {
    let caught: unknown
    try { decodeQuote('AAPL', { ok: false, status: 429, headers: { 'retry-after': retry }, text: '' }, NOW) }
    catch (error) { caught = error }
    expect(caught instanceof YahooError).toBe(true)
    expect((caught as YahooError).retryAfterMs).toBe(expected)
  }
})

test('the prompt omits USD, preserves other currencies, and the panel keeps currency labels', async ($, on) => {
  const usd = decodeQuote('AAPL', response(), NOW)
  expect(formatBandPrice(usd)).toBe('100.00')
  expect(formatPrice(usd)).toBe('100.00 USD')
  expect(formatBandPrice({ ...usd, currency: 'HKD' })).toBe('100.00 HKD')
  const { clock } = host(on, ['AAPL', '0700.HK'])
  on('http.fetch', (_, e) => {
    const hk = e.url.includes('0700.HK')
    const wire = response(hk ? '0700.HK' : 'AAPL')
    if (hk) wire.text = wire.text.replace('"currency":"USD"', '"currency":"HKD"')
    return { value: wire }
  })
  await $.session.start(START)
  await clock.advance(1000)
  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: /USD/ })).toBe(undefined)
    expect(await band.find({ type: 'Text', text: /0700.HK.*HKD/ })).toBeDefined()
    await band.unmount()
    const pane = await $.ui.mount({ ...PANE, surface })
    expect(await pane.find({ type: 'Text', text: /100\.00 USD/ })).toBeDefined()
    await pane.unmount()
  }
})

test('opening and closing management panels adds no requests or chart surfaces', async ($, on) => {
  const { clock } = host(on, ['AAPL', 'MSFT'])
  const requests: string[] = []
  on('http.fetch', (_, e) => { requests.push(e.url); return { value: response(e.url.includes('MSFT') ? 'MSFT' : 'AAPL') } })
  await $.session.start(START)
  await clock.advance(1000)
  expect(requests.length).toBe(2)
  expect(requests.every(url => url.includes('interval=1d&range=1d'))).toBe(true)
  for (const surface of ['terminal', 'desktop'] as const) {
    await command($, '')
    const pane = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns: 40 }, surface })
    expect(await pane.find({ key: 'add-ticker' })).toBeDefined()
    expect(await pane.find({ key: 'remove-AAPL' })).toBeDefined()
    expect(await pane.find({ type: 'Raster' })).toBe(undefined)
    expect(await pane.find({ type: 'Svg' })).toBe(undefined)
    expect(await pane.find({ key: 'period-1D' })).toBe(undefined)
    expect(await pane.find({ key: 'select-AAPL' })).toBe(undefined)
    await clock.advance(1000)
    expect(requests.length).toBe(2)
    await command($, '')
    await pane.unmount()
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: /AAPL.*100\.00.*MSFT/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /[▁-█\u2800-\u28ff]/ })).toBe(undefined)
    await band.unmount()
  }
})

test('quote metadata is sufficient without price history arrays', async ($, on) => {
  const { clock } = host(on, ['AAPL'])
  const requests: string[] = []
  on('http.fetch', (_, e) => {
    requests.push(e.url)
    const wire = response()
    const body = JSON.parse(wire.text)
    delete body.chart.result[0].timestamp
    delete body.chart.result[0].indicators
    return { value: { ...wire, text: JSON.stringify(body) } }
  })
  await $.session.start(START)
  await clock.settle()
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /AAPL.*100\.00/ })).toBeDefined()
  expect(requests.length).toBe(1)
  expect(requests[0]).toContain('interval=1d&range=1d')
  await band.unmount()
})

const APPLE = { market: 'us', code: 'AAPL', displayCode: 'AAPL', name: 'Apple Inc.' }
const TENCENT = { market: 'hk', code: '700', displayCode: '00700', name: 'Tencent' }
const GROUP_A = '00000000-0000-4000-8000-000000000001'
const GROUP_B = '00000000-0000-4000-8000-000000000002'
const macResult = (data: unknown): McpToolResult => ({ isError: false, content: [{ type: 'text', text: JSON.stringify(data) }] })
const macQuote = (ref = APPLE, price = 123) => ({
  symbol: { market: ref.market, code: ref.code },
  quote: { price, previousClose: 100, changePercent: price - 100, currencyCode: ref.market === 'hk' ? 'HKD' : 'USD',
    timestamp: new Date(NOW - 20_000).toISOString(), marketState: 'open' },
})

function macHost(on: On, saved: Map<string, unknown>, selected = false) {
  saved.set(MAC_SETTINGS_KEY, { version: 1, source: 'mac', selected: selected ? [APPLE] : [] })
  const state = {
    groups: [{ id: GROUP_A, name: 'Main', symbols: [APPLE, TENCENT] }, { id: GROUP_B, name: 'Tech', symbols: [APPLE] }] as MacGroup[],
    calls: [] as { server: string; tool: string; args: Record<string, unknown> }[],
    unavailable: false, missing: false,
    beforeCall: undefined as (() => Promise<void>) | undefined,
  }
  on('mcp.call', async (_, e) => {
    state.calls.push(e)
    if (state.beforeCall) await state.beforeCall()
    if (state.unavailable) throw new Error('private-token must not be echoed')
    if (e.tool === 'list_watchlists') return { value: macResult({ groups: state.groups }) }
    if (e.tool === 'get_quotes') {
      const refs = e.args.symbols as { market: string; code: string }[]
      return { value: macResult(refs.map(ref => state.missing ? { symbol: ref, quote: null }
        : macQuote({ ...ref, displayCode: ref.code, name: ref.code }))) }
    }
    throw new Error('Unexpected tool; Mac mode must remain read-only')
  })
  return state
}

test('Mac mode preserves the independent list and only requests quotes for checked instruments', async ($, on) => {
  const { clock, saved } = host(on, ['MSFT'])
  const state = macHost(on, saved)
  let yahoo = 0
  on('http.fetch', () => { yahoo++; return { value: response('MSFT') } })
  await $.session.start(START)
  await clock.settle()
  expect(state.calls.map(call => call.tool)).toEqual(['list_watchlists'])
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ key: 'add-ticker' })).toBe(undefined)
  expect(await ui.find({ key: 'remove-MSFT' })).toBe(undefined)
  expect(await ui.find({ key: `mac-group-select-${GROUP_B}` })).toBeDefined()
  await ui.press({ key: `mac-toggle-${GROUP_A}-us:AAPL` })
  await clock.settle()
  expect(state.calls[state.calls.length - 1].args).toEqual({ symbols: [{ market: 'us', code: 'AAPL' }] })
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /AAPL US.*123\.00/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /MSFT|Tencent/ })).toBe(undefined)
  expect(yahoo).toBe(0)
  expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: ['MSFT'], paused: false })
  await ui.press({ key: 'source-cc' })
  await clock.settle()
  expect(await ui.find({ key: 'add-ticker' })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /MSFT.*100\.00/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /AAPL/ })).toBe(undefined)
  expect(yahoo).toBe(1)
  await ui.press({ key: 'source-mac' })
  await clock.settle()
  expect(await band.find({ type: 'Text', text: /AAPL US.*123\.00/ })).toBeDefined()
  expect(state.calls.every(call => ['list_watchlists', 'get_quotes'].includes(call.tool))).toBe(true)
  await ui.unmount(); await band.unmount()
})

test('Mac selection is shared across groups, local only, and usable on both surfaces at narrow widths', async ($, on) => {
  const { clock, saved } = host(on, ['MSFT'])
  const state = macHost(on, saved)
  await $.session.start(START)
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    for (const bodyColumns of [40, 100]) {
      const ui = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns }, surface })
      expect(await ui.find({ key: 'add-ticker' })).toBe(undefined)
      expect(await ui.find({ type: 'Button', text: 'Remove' })).toBe(undefined)
      await ui.press({ key: `mac-group-select-${GROUP_A}` })
      await ui.press({ key: `mac-toggle-${GROUP_A}-us:AAPL` })
      await clock.settle()
      await ui.press({ key: `mac-group-select-${GROUP_B}` })
      expect((await ui.find({ key: `mac-toggle-${GROUP_B}-us:AAPL` }))?.text).toBe('✓ Shown')
      const last = state.calls[state.calls.length - 1]
      expect(last.args).toEqual({ symbols: [{ market: 'us', code: 'AAPL' }] })
      await ui.press({ key: `mac-toggle-${GROUP_B}-us:AAPL` })
      await clock.settle()
      await ui.press({ key: `mac-group-select-${GROUP_A}` })
      expect((await ui.find({ key: `mac-toggle-${GROUP_A}-us:AAPL` }))?.text).toBe('Show')
      expect((saved.get(MAC_SETTINGS_KEY) as { selected: unknown[] }).selected).toEqual([])
      expect(state.groups[0].symbols.length).toBe(2)
      await ui.unmount()
    }
  }
  expect(state.calls.every(call => call.server === 'pulse' && ['list_watchlists', 'get_quotes'].includes(call.tool))).toBe(true)
  expect((await command($, 'add NVDA')).text).toContain('Add tickers in Pulse Mac')
  expect((await command($, 'remove AAPL')).text).toContain('Uncheck')
  expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: ['MSFT'], paused: false })
})

test('Mac list changes follow stable identities; new tickers stay unchecked and removed tickers leave the band', async ($, on) => {
  const { clock, saved } = host(on)
  const state = macHost(on, saved, true)
  await $.session.start(START); await clock.settle()
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  state.groups = [{ id: GROUP_A, name: 'Renamed', symbols: [APPLE, { ...APPLE, market: 'jp', name: 'Other market' }] }]
  await clock.advance(5000)
  expect(await ui.find({ type: 'Text', text: 'Renamed' })).toBeDefined()
  expect((await ui.find({ key: `mac-toggle-${GROUP_A}-jp:AAPL` }))?.text).toBe('Show')
  expect(state.calls[state.calls.length - 1].args).toEqual({ symbols: [{ market: 'us', code: 'AAPL' }] })
  state.groups = [{ id: GROUP_A, name: 'Renamed', symbols: [TENCENT] }]
  await clock.advance(5000)
  expect(await band.find({ type: 'Text', text: /AAPL/ })).toBe(undefined)
  expect((await ui.find({ key: `mac-toggle-${GROUP_A}-hk:700` }))?.text).toBe('Show')
  expect(state.calls[state.calls.length - 1].tool).toBe('list_watchlists')
  await ui.unmount(); await band.unmount()
})

test('Mac connection status stays stable during background reads while quotes still update', async ($, on) => {
  const { clock, saved } = host(on)
  const state = macHost(on, saved, true)
  await $.session.start(START); await clock.settle()
  const panes = await Promise.all((['terminal', 'desktop'] as const).map(surface => $.ui.mount({ ...PANE, surface })))
  const connected = '● Connected · Updates every 5s'
  const checkStatus = async () => {
    for (const pane of panes) {
      const status = await pane.find({ type: 'Text', text: connected })
      expect(status?.text).toBe(connected)
      expect(status?.props.color).toBe('green')
    }
  }
  await checkStatus()
  state.beforeCall = () => clock.sleep(1000)
  await clock.advance(5000) // List read is in flight.
  expect(state.calls.length).toBe(3)
  await checkStatus()
  await clock.advance(1000) // Quote read is in flight.
  expect(state.calls.length).toBe(4)
  await checkStatus()
  await clock.advance(1000)
  await checkStatus()
  for (const pane of panes) expect(await pane.find({ type: 'Text', text: '123.00 USD' })).toBeDefined()
  state.unavailable = true
  await clock.advance(6000)
  for (const pane of panes) {
    const status = await pane.find({ type: 'Text', text: '● Not connected · Check /mcp' })
    expect(status?.text).toBe('● Not connected · Check /mcp')
    expect(status?.props.color).toBe('yellow')
    await pane.unmount()
  }
})

test('Mac failures retain labeled cached quotes without Yahoo fallback; null quotes retain provider timestamps', async ($, on) => {
  const { clock, saved } = host(on, ['MSFT'])
  const state = macHost(on, saved, true)
  let yahoo = 0
  on('http.fetch', () => { yahoo++; return { value: response() } })
  await $.session.start(START); await clock.settle()
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const band = await $.ui.mount({ ...BAND, surface: 'desktop' })
  state.unavailable = true
  await clock.advance(5000)
  expect(await band.find({ type: 'Text', text: /offline.*AAPL US.*123\.00.*cached/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Cached quote.*Could not reach Pulse Mac/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /private-token/ })).toBe(undefined)
  state.unavailable = false; state.missing = true
  await clock.advance(5000)
  expect(await ui.find({ type: 'Text', text: /No quote cached in Pulse Mac yet/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /123\.00.*cached/ })).toBeDefined()
  state.missing = false
  await clock.advance(5000)
  expect(await band.find({ type: 'Text', text: /cached/ })).toBe(undefined)
  expect(yahoo).toBe(0)
  await ui.unmount(); await band.unmount()
})

test('switching sources during an MCP call discards its late result and resumes the independent list', async ($, on) => {
  const { clock, saved } = host(on, ['MSFT'])
  const state = macHost(on, saved, true)
  state.beforeCall = () => clock.sleep(2000)
  on('http.fetch', () => ({ value: response('MSFT') }))
  await $.session.start(START); await clock.settle()
  await command($, 'source cc')
  await clock.advance(2000)
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /MSFT.*100\.00/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /AAPL|123/ })).toBe(undefined)
  await band.unmount()
})

test('Yahoo cooldown cannot delay Mac reads; Mac pause and exit stop polling and headless sessions never call MCP', async ($, on) => {
  const { clock, saved } = host(on, ['MSFT'])
  const state = macHost(on, saved, true)
  saved.set(MAC_SETTINGS_KEY, { version: 1, source: 'cc', selected: [APPLE] })
  on('http.fetch', () => ({ value: { ok: false, status: 429, headers: { 'retry-after': '120' }, text: '' } }))
  await $.session.start({ ...START, isInteractive: false }); await clock.advance(120_000)
  expect(state.calls.length).toBe(0)
  await $.session.start(START); await clock.settle()
  await command($, 'source mac'); await clock.settle()
  expect(state.calls.map(call => call.tool)).toEqual(['list_watchlists', 'get_quotes'])
  await command($, 'off')
  await clock.advance(20_000)
  expect(state.calls.length).toBe(2)
  await command($, 'refresh'); await clock.settle()
  expect(state.calls.length).toBe(4)
  await clock.advance(20_000)
  expect(state.calls.length).toBe(4)
  await command($, 'on'); await clock.settle()
  expect(state.calls.length).toBe(6)
  await $.session.end({ reason: 'prompt_input_exit', sessionId: 'test', resume: { id: 'test' } })
  await clock.advance(30_000)
  expect(state.calls.length).toBe(6)
})

test('Mac decoding rejects mismatched or malformed data and preserves sanitized display text', () => {
  const groups = decodeWatchlists(macResult({ groups: [{ id: GROUP_A, name: '\u001bMain', symbols: [APPLE] }] }))
  expect(groups[0].name).toBe('Main')
  expect(() => decodeWatchlists(macResult({ groups: null }))).toThrow('invalid watchlist')
  expect(() => decodeMacQuotes(macResult([macQuote(TENCENT)]), [APPLE], NOW)).toThrow('different instrument')
  expect(decodeMacQuotes(macResult([{ symbol: APPLE, quote: null }]), [APPLE], NOW)).toEqual({ 'us:AAPL': null })
  const quote = decodeMacQuotes(macResult([macQuote()]), [APPLE], NOW)['us:AAPL']!
  expect(quote.timestamp).toBe(NOW - 20_000)
  expect(quote.fetchedAt).toBe(NOW)
  expect(quote.delaySeconds).toBe(null)
  expect(readMacPreferences({ version: 1, source: 'mac', selected: [APPLE, APPLE] }).selected).toEqual([{ market: 'us', code: 'AAPL' }])
})

test('Mac source and display selection survive reload while quotes are read anew', { options: { macServer: 'my-pulse' } }, async ($, on) => {
  const { clock, saved } = host(on, ['MSFT'])
  const state = macHost(on, saved, true)
  await $.session.start(START); await clock.settle()
  expect(state.calls.every(call => call.server === 'my-pulse')).toBe(true)
  await $.session.end({ reason: 'prompt_input_exit', sessionId: 'test', resume: { id: 'test' } })
  await $.session.start(START); await clock.settle()
  expect(state.calls.map(call => call.tool)).toEqual(['list_watchlists', 'get_quotes', 'list_watchlists', 'get_quotes'])
  expect((saved.get(MAC_SETTINGS_KEY) as { source: string }).source).toBe('mac')
  expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: ['MSFT'], paused: false })
})
