import Foundation
import Testing
@testable import PulseCore

/// Metal names live in three `.strings` tables and, as a fallback, in Swift.
/// Two copies of the same truth drift: the Japanese table once gave the Shanghai
/// spot contract and the Shanghai futures contract the identical name, which the
/// fallback did not, so nothing failed until someone looked. These checks read
/// the shipped tables directly.
@Suite("Metal display names")
struct MetalDisplayNameTests {
    private static let languages = ["en", "zh-Hans", "ja", "ko"]

    /// The app's tables live outside this package. When PulseCore is built on its
    /// own they are simply absent, and there is nothing to check.
    private static func table(_ language: String) -> [String: String]? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PulseCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // PulseCore
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("PulseMac/Resources/\(language).lproj/Localizable.strings")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var entries: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 4, parts[1].hasPrefix("metal.") else { continue }
            entries[String(parts[1])] = String(parts[3])
        }
        return entries.isEmpty ? nil : entries
    }

    @Test("Every metal is named in every language")
    func everyMetalIsNamed() throws {
        for language in Self.languages {
            guard let table = Self.table(language) else { continue }
            for metal in PreciousMetalID.allCases {
                let key = "metal.\(metal.rawValue)"
                #expect(table[key] != nil, "\(language) is missing \(key)")
                #expect(table[key]?.isEmpty == false, "\(language) has an empty \(key)")
            }
        }
    }

    @Test("No two metals share a name in the same language")
    func namesAreDistinct() throws {
        for language in Self.languages {
            guard let table = Self.table(language) else { continue }
            let names = PreciousMetalID.allCases.compactMap { table["metal.\($0.rawValue)"] }
            #expect(Set(names).count == names.count, "\(language) reuses a metal name")
        }
    }

    /// The fallback only runs when a key is missing, which is exactly when nobody
    /// is watching — so it has to agree with the table it stands in for.
    @Test("The Swift fallback matches the shipped Chinese and English names")
    func fallbackMatchesTables() throws {
        for (language, isChinese) in [("zh-Hans", true), ("en", false)] {
            guard let table = Self.table(language) else { continue }
            for metal in PreciousMetalID.allCases {
                let shipped = try #require(table["metal.\(metal.rawValue)"])
                #expect(
                    metal.fallbackDisplayName(chinese: isChinese) == shipped,
                    "\(language) fallback for \(metal.rawValue) drifted from the table"
                )
            }
        }
    }
}
