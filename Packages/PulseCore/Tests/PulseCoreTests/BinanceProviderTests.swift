import Foundation
import Testing
@testable import PulseCore

@Suite("Binance market data parsing")
struct BinanceProviderTests {
    private static let tickerFixture = Data(#"""
    [
      {"symbol":"BTCUSDT","prevClosePrice":"62834.00","lastPrice":"64698.01",
       "openPrice":"62834.01","highPrice":"65277.37","lowPrice":"62780.84",
       "volume":"21579.82109","quoteVolume":"1390235919.27","closeTime":1784115503003}
    ]
    """#.utf8)

    private static let streamFixture = Data(#"""
    {
      "stream":"btcusdt@ticker",
      "data":{"s":"BTCUSDT","x":"62834.00","c":"64698.01","o":"62834.01",
              "h":"65277.37","l":"62780.84","v":"21579.82109",
              "q":"1390235919.27","C":1784115503003}
    }
    """#.utf8)

    private static let klineFixture = Data(#"""
    [
      [1784115420000,"64712.01","64712.01","64698.00","64698.01","15.88676",
       1784115479999,"1027999.38",1436,"5.37","347521.92","0"]
    ]
    """#.utf8)

    @Test("Pulse crypto pairs map to Binance spot symbols")
    func symbolMapping() {
        #expect(BinanceProvider.binanceSymbol(
            for: SymbolID(cryptoBase: "BTC", quote: "USDT")) == "BTCUSDT")
        #expect(BinanceProvider.binanceSymbol(
            for: SymbolID(cryptoBase: "ETH", quote: "BTC")) == "ETHBTC")
        #expect(BinanceProvider.binanceSymbol(
            for: SymbolID(market: .us, code: "COIN")) == nil)
    }

    @Test("24-hour ticker maps to a real-time Pulse quote")
    func tickerParsing() throws {
        let ticker = try #require(
            BinanceProvider.decode([BinanceTicker24Hour].self, from: Self.tickerFixture).first
        )
        let symbol = SymbolID(cryptoBase: "BTC", quote: "USDT")
        let quote = try #require(BinanceProvider.quote(from: ticker, symbol: symbol))

        #expect(quote.symbol == symbol)
        #expect(quote.price == 64_698.01)
        #expect(quote.previousClose == 62_834)
        #expect(quote.high == 65_277.37)
        #expect(quote.currencyCode == "USDT")
        #expect(quote.marketState == .regular)
    }

    @Test("Combined WebSocket ticker maps to the requested Pulse symbol")
    func streamParsing() throws {
        let event = try BinanceProvider.decode(BinanceCombinedTickerStream.self, from: Self.streamFixture)
        let symbol = SymbolID(cryptoBase: "BTC", quote: "USDT")
        let quote = try #require(BinanceProvider.quote(from: event.data, symbol: symbol))

        #expect(event.stream == "btcusdt@ticker")
        #expect(event.data.symbol == "BTCUSDT")
        #expect(quote.price == 64_698.01)
        #expect(quote.turnover == 1_390_235_919.27)
    }

    @Test("Klines decode in chronological candle shape")
    func klineParsing() throws {
        let kline = try #require(BinanceProvider.decode([BinanceKline].self, from: Self.klineFixture).first)
        let candle = kline.candle

        #expect(candle.open == 64_712.01)
        #expect(candle.high == 64_712.01)
        #expect(candle.low == 64_698)
        #expect(candle.close == 64_698.01)
        #expect(candle.volume == 15.88676)
    }
}
