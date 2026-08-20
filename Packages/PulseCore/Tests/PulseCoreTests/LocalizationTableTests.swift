import Foundation
import Testing
@testable import PulseCore

/// The shipped `.strings` tables, checked against each other.
///
/// Nothing at build time notices a key that only exists in one language: the
/// lookup falls back to the raw key, so the app shows `settings.title` where a
/// title belongs and only a reader of that language ever finds out. A new
/// language makes that failure mode certain rather than unlikely, so the tables
/// are compared directly.
@Suite("Localization tables")
struct LocalizationTableTests {
    /// Every language `PulseLanguagePreference` can resolve to, which is the set
    /// the app can actually ask for at runtime.
    private static var languages: [String] {
        PulseLanguagePreference.allCases
            .filter { $0 != .system }
            .map(\.localeIdentifier)
    }

    /// The app's tables live outside this package; when PulseCore is built alone
    /// they are absent and there is nothing to compare.
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
            guard parts.count >= 4, !parts[1].isEmpty else { continue }
            entries[String(parts[1])] = String(parts[3])
        }
        return entries.isEmpty ? nil : entries
    }

    /// `%@` and `%d` are positional contracts with the call site. A translation
    /// that drops one silently prints the wrong thing; one that adds one reads
    /// past the arguments it was given.
    private static func specifiers(in value: String) -> [String] {
        var found: [String] = []
        var characters = Array(value)
        var index = 0
        while index < characters.count - 1 {
            if characters[index] == "%" {
                let next = characters[index + 1]
                if next == "%" { index += 2; continue }
                if "@dfs".contains(next) { found.append("%\(next)") }
            }
            index += 1
        }
        return found.sorted()
    }

    @Test("Every language declares a table")
    func everyLanguageHasATable() throws {
        // English always ships; if it cannot be read, the package is being built
        // outside the app repository and the rest of this suite is moot.
        try #require(Self.table("en") != nil)
        for language in Self.languages {
            #expect(Self.table(language) != nil, "\(language) has no Localizable.strings")
        }
    }

    @Test("No language is missing a key English has, or invents one it does not")
    func keysMatchEnglish() throws {
        guard let english = Self.table("en") else { return }
        for language in Self.languages where language != "en" {
            guard let table = Self.table(language) else { continue }
            let missing = Set(english.keys).subtracting(table.keys).sorted()
            let extra = Set(table.keys).subtracting(english.keys).sorted()
            #expect(missing.isEmpty, "\(language) is missing: \(missing.prefix(5))")
            #expect(extra.isEmpty, "\(language) has keys English does not: \(extra.prefix(5))")
        }
    }

    @Test("Translations carry the same format specifiers as English")
    func formatSpecifiersMatch() throws {
        guard let english = Self.table("en") else { return }
        for language in Self.languages where language != "en" {
            guard let table = Self.table(language) else { continue }
            for (key, source) in english {
                guard let translated = table[key] else { continue }
                #expect(
                    Self.specifiers(in: source) == Self.specifiers(in: translated),
                    "\(language) \(key): expected \(Self.specifiers(in: source)), got \(Self.specifiers(in: translated))"
                )
            }
        }
    }

    @Test("No translation was left empty or untranslated as its own key")
    func valuesAreRealText() throws {
        for language in Self.languages {
            guard let table = Self.table(language) else { continue }
            for (key, value) in table {
                #expect(!value.isEmpty, "\(language) \(key) is empty")
                #expect(value != key, "\(language) \(key) still holds its key as the value")
            }
        }
    }

    /// The picker offers one row per case, so a duplicate label would show twice.
    @Test("Every language preference resolves to a distinct locale and label")
    func preferencesAreDistinct() {
        let identifiers = PulseLanguagePreference.allCases
            .filter { $0 != .system }
            .map(\.localeIdentifier)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.contains("ko"))

        let names = PulseLanguagePreference.allCases.map(\.localizedDisplayName)
        #expect(Set(names).count == names.count)
    }

    @Test("The system language falls back to the closest shipped table", arguments: [
        (["ko-KR", "en-US"], "ko"),
        (["ja-JP"], "ja"),
        (["zh-Hans-CN"], "zh-Hans"),
        (["zh-Hant-TW"], "zh-Hans"),
        (["fr-FR"], "en"),
        ([], "en"),
    ])
    func systemLanguage(preferred: [String], expected: String) {
        #expect(PulseLocalization.systemLanguageIdentifier(preferredLanguages: preferred) == expected)
    }
}
