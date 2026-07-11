import Testing
@testable import PulseCore

@Suite("Derived quote metrics")
struct QuoteMetricsTests {
    @Test("Amplitude uses high-low range relative to previous close")
    func amplitude() throws {
        let quote = Quote(
            symbol: SymbolID(market: .us, code: "TEST"),
            price: 102,
            previousClose: 100,
            high: 105,
            low: 95
        )

        let amplitude = try #require(quote.amplitudePercent)
        #expect(abs(amplitude - 10) < 0.000_001)
    }

    @Test("Amplitude is unavailable without a valid daily range")
    func unavailableAmplitude() {
        let missingHigh = Quote(
            symbol: SymbolID(market: .us, code: "TEST"),
            price: 102,
            previousClose: 100,
            low: 95
        )
        let zeroPreviousClose = Quote(
            symbol: SymbolID(market: .us, code: "TEST"),
            price: 102,
            previousClose: 0,
            high: 105,
            low: 95
        )
        let invalidRange = Quote(
            symbol: SymbolID(market: .us, code: "TEST"),
            price: 102,
            previousClose: 100,
            high: 95,
            low: 105
        )

        #expect(missingHigh.amplitudePercent == nil)
        #expect(zeroPreviousClose.amplitudePercent == nil)
        #expect(invalidRange.amplitudePercent == nil)
    }
}
