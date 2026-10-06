import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { SETTINGS_KEY } from '../hooks/watchlist'
import { decodeQuote, formatBandPrice, formatPrice, formatStaleDate, normalizeSymbol, quotePath, YahooError } from '../hooks/yahoo'
import { BinanceError, decodeTickers, isCryptoPair, tickersQuery } from '../hooks/binance'

// The URL the mod's one Binance call builds from its fixed address.
const tickersURL = (pairs: string[]) => `https://data-api.binance.vision/api/v3/ticker/24hr?${tickersQuery(pairs)}`

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
  const commands: string[] = []
  on('command.register', (_, e) => { commands.push(e.name); return { value: { command: e.name } } })
  on('session.start', () => ({ cwd: '/test' }))
  on('session.attach', (_, e) => ({ clientId: e.clientId }))
  on('session.detach', (_, e) => ({ clientId: e.clientId }))
  on('session.end', () => ({ sessionId: 'test' }))
  let paneOpen = false
  on('ui.panes', () => ({ value: paneOpen ? [{ id: 'pulse-quotes', title: 'Pulse', isShown: true, isFocused: true, isPlaced: true }] : [] }))
  on('ui.open', () => { paneOpen = true; return { value: { isPlaced: true } } })
  on('ui.close', () => { paneOpen = false; return { value: undefined } })
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['Host content'] }))
  return { clock, saved, commands }
}

function binance(url: string, prices: Record<string, [number, number]> = {}) {
  const requested = JSON.parse(decodeURIComponent(url.split('symbols=')[1])) as string[]
  if (requested.some(symbol => !(symbol in prices))) {
    return { ok: false, status: 400, headers: {}, text: '{"code":-1121,"msg":"Invalid symbol."}' }
  }
  return { ok: true, status: 200, headers: {}, text: JSON.stringify(requested.map(symbol => ({
    symbol, lastPrice: String(prices[symbol][0]), prevClosePrice: String(prices[symbol][1]), closeTime: NOW - 1000,
  }))) }
}
const PRICES: Record<string, [number, number]> = { BTCUSDT: [86594, 84820], ETHUSDT: [3200.5, 3300], PEPEUSDT: [0.00000441, 0.0000042] }

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
  expect(quotePath('^GSPC').startsWith('%5EGSPC?')).toBe(true)
  expect(() => normalizeSymbol('https://example.com')).toThrow()
  expect(formatStaleDate(NOW - 60_000, NOW)).toBe('')
  expect(formatStaleDate(NOW - 3 * 86_400_000, NOW)).toMatch(/^[A-Z][a-z]{2} \d{1,2}$/)
})

test('Binance pairs parse, batch, decode and format', () => {
  expect(normalizeSymbol(' btc/usdt ')).toBe('BTC/USDT')
  expect(normalizeSymbol('BTC-USD')).toBe('BTC-USD') // A dash stays a Yahoo symbol.
  expect(isCryptoPair('BTC/USDT')).toBe(true)
  expect(isCryptoPair('BTC-USD')).toBe(false)
  expect(() => normalizeSymbol('BTC/USDT/X')).toThrow('Binance pair')
  expect(tickersURL(['BTC/USDT', 'ETH/USDT'])).toBe('https://data-api.binance.vision/api/v3/ticker/24hr?symbols='
    + encodeURIComponent('["BTCUSDT","ETHUSDT"]'))
  const url = tickersURL(['BTC/USDT', 'PEPE/USDT'])
  const quotes = decodeTickers(['BTC/USDT', 'PEPE/USDT'], binance(url, PRICES), NOW)
  expect(Math.abs(quotes['BTC/USDT'].changePercent! - (86594 - 84820) / 84820 * 100) < 1e-9).toBe(true)
  expect(quotes['BTC/USDT'].currency).toBe('USDT')
  expect(quotes['BTC/USDT'].delaySeconds).toBe(0)
  expect(formatPrice(quotes['BTC/USDT'])).toBe('86,594.00 USDT')
  expect(formatBandPrice(quotes['BTC/USDT'])).toBe('86,594.00') // The pair already names USDT.
  expect(formatPrice(quotes['PEPE/USDT'])).toBe('0.00000441 USDT')
  let caught: unknown
  try { decodeTickers(['NOPE/USDT'], binance(tickersURL(['NOPE/USDT']), PRICES), NOW) } catch (error) { caught = error }
  expect(caught instanceof BinanceError && caught.invalidSymbol).toBe(true)
})

test('a mixed list reads every pair in one Binance request and stocks from Yahoo', async ($, on) => {
  const { clock } = host(on, ['AAPL', 'BTC/USDT', 'ETH/USDT'])
  const yahoo: string[] = [], crypto: string[] = []
  on('http.fetch', (_, e) => {
    if (e.url.includes('binance')) { crypto.push(e.url); return { value: binance(e.url, PRICES) } }
    yahoo.push(e.url); return { value: response('AAPL') }
  })
  await $.session.start(START); await clock.settle()
  expect(crypto).toEqual([tickersURL(['BTC/USDT', 'ETH/USDT'])])
  expect(yahoo.length).toBe(1)
  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: /AAPL.*100\.00.*BTC\/USDT.*86,594\.00/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /86,594\.00 USDT/ })).toBe(undefined)
    await band.unmount()
    const pane = await $.ui.mount({ ...PANE, surface })
    expect(await pane.find({ type: 'Text', text: '86,594.00 USDT' })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /Binance Spot/ })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /Delay/ })).toBe(undefined)
    expect(await pane.find({ type: 'Text', text: /Crypto: 24h change/ })).toBeDefined()
    await pane.unmount()
  }
})

test('an unknown or delisted pair fails alone instead of failing the whole Binance batch', async ($, on) => {
  const { clock } = host(on, ['BTC/USDT', 'OLD/USDT'])
  const crypto: string[] = []
  on('http.fetch', (_, e) => { crypto.push(e.url); return { value: binance(e.url, PRICES) } })
  await $.session.start(START); await clock.settle()
  expect(crypto).toEqual([tickersURL(['BTC/USDT', 'OLD/USDT']), tickersURL(['BTC/USDT']), tickersURL(['OLD/USDT'])])
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await pane.find({ type: 'Text', text: '86,594.00 USDT' })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /Binance has no Spot pair/ })).toBeDefined()
  await pane.unmount()
})

test('Binance pairs keep refreshing while Yahoo waits out a rate limit', async ($, on) => {
  const { clock } = host(on, ['AAPL', 'BTC/USDT'])
  let yahoo = 0, crypto = 0
  on('http.fetch', (_, e) => {
    if (e.url.includes('binance')) { crypto++; return { value: binance(e.url, PRICES) } }
    yahoo++; return { value: { ok: false, status: 429, headers: { 'retry-after': '600' }, text: '' } }
  })
  await $.session.start(START); await clock.settle()
  expect([yahoo, crypto]).toEqual([1, 1])
  await clock.advance(60_000)
  expect([yahoo, crypto]).toEqual([1, 2])
  await clock.advance(60_000)
  expect([yahoo, crypto]).toEqual([1, 3])
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await pane.find({ type: 'Text', text: '86,594.00 USDT' })).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /Yahoo rate limited/ })).toBeDefined()
  await pane.unmount()
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
    // Today's quotes carry no per-row time; only an earlier day's quote is dated.
    expect(await ui.find({ type: 'Text', text: /As of/ })).toBe(undefined)
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

test('Add uses the edited field (terminal button, desktop native submit) and management controls remain usable on both layouts', async ($, on) => {
  const { clock, saved } = host(on, [], true)
  on('http.fetch', () => ({ value: response() }))
  await $.session.start(START)
  for (const surface of ['terminal', 'desktop'] as const) {
    for (const bodyColumns of [40, 100]) {
      const ui = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns }, surface })
      const desktop = surface === 'desktop'
      // Desktop draws the field's own submit button, so Pulse draws no second Add.
      expect(!!(await ui.find({ key: 'add' })), `Add button on ${surface}`).toBe(!desktop)
      const add = async (text: string) => {
        if (desktop) return ui.input({ key: 'add-ticker', text })
        await ui.input({ key: 'add-ticker', text, kind: 'change' })
        await ui.press({ key: 'add' })
      }
      await add('')
      await clock.settle()
      expect(await ui.find({ type: 'Text', text: /Enter a Yahoo ticker/ }), `empty Add should show validation on ${surface}/${bodyColumns}`).toBeDefined()
      await add('aapl')
      await clock.settle()
      expect(saved.get(SETTINGS_KEY)).toEqual({ version: 1, symbols: ['AAPL'], paused: true })
      expect((await ui.find({ key: 'add-ticker' }))?.props.value).toBe('')
      expect(await ui.find({ type: 'Text', text: /Enter a Yahoo ticker/ })).toBe(undefined)
      expect(await ui.find({ key: 'remove-AAPL' })).toBeDefined()
      await ui.press({ key: 'pause' })
      await clock.settle()
      expect((await ui.find({ key: 'pause' }))?.text).toBe(desktop ? 'Pause' : 'Pause (p)')
      await clock.advance(1000)
      expect(await ui.find({ type: 'Text', text: /Auto-refresh every 60s/ })).toBeDefined()
      await ui.press({ key: 'pause' })
      await clock.settle()
      expect((await ui.find({ key: 'pause' }))?.text).toBe(desktop ? 'Resume' : 'Resume (p)')
      expect((await ui.find({ key: 'refresh' }))?.text).toBe(desktop ? 'Refresh' : 'Refresh (r)')
      expect(!!(await ui.find({ type: 'Text', text: /Tab: move between controls/ })), `keyboard hint on ${surface}`).toBe(!desktop)
      expect(await ui.find({ type: 'Text', text: /^─+$/ }), `no character-drawn rule on ${surface}`).toBe(undefined)
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

test('Claude Desktop starts headless, registers /pulse at once, and polls only while attached', async ($, on) => {
  const { clock, commands } = host(on, ['AAPL'])
  let requests = 0
  on('http.fetch', () => { requests++; return { value: response() } })
  await $.session.start({ ...START, surface: null, isInteractive: false })
  expect(commands).toEqual(['pulse'])
  await clock.advance(120_000)
  expect(requests).toBe(0)
  await $.session.attach({ surface: 'desktop', clientId: 'desktop:one' })
  await clock.settle()
  expect(requests).toBe(1)
  await $.session.attach({ surface: 'desktop', clientId: 'desktop:two' })
  await clock.advance(60_000)
  expect(requests, 'a second window must not start another refresh loop').toBe(2)
  expect((await command($, '')).text).toBe('Pulse panel opened.')
  const band = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await band.find({ type: 'Text', text: /AAPL.*100\.00/ })).toBeDefined()
  await band.unmount()
  await $.session.detach({ surface: 'desktop', clientId: 'desktop:one', reason: 'detach' })
  await clock.advance(60_000)
  expect(requests).toBe(3)
  await $.session.detach({ surface: 'desktop', clientId: 'desktop:two', reason: 'detach' })
  await clock.advance(120_000)
  expect(requests).toBe(3)
  await $.session.attach({ surface: 'desktop', clientId: 'desktop:one' })
  await clock.settle()
  expect(requests).toBe(4)
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

test('a saved Pulse Mac selection from 0.3 falls back to the independent watchlist', async ($, on) => {
  const { clock, saved } = host(on, ['AAPL'])
  saved.set('mac-view.v1', { version: 1, source: 'mac', selected: [{ market: 'us', code: 'MSFT' }] })
  const requests: string[] = []
  on('http.fetch', (_, e) => { requests.push(e.url); return { value: response() } })
  await $.session.start(START)
  await clock.settle()
  expect(requests.length).toBe(1)
  expect(requests[0]).toContain('/chart/AAPL?')
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await band.find({ type: 'Text', text: /AAPL.*100\.00/ })).toBeDefined()
  await band.unmount()
  expect(await command($, 'source mac')).toEqual({ text: expect.stringContaining('/pulse add AAPL') })
})
