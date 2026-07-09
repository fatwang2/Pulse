import Foundation

public enum PulseLanguagePreference: String, Codable, CaseIterable, Sendable {
    case system
    case english
    case simplifiedChinese

    public var localeIdentifier: String {
        switch self {
        case .system:
            PulseLocalization.systemLanguageIdentifier()
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        }
    }

    public var localizedDisplayName: String {
        switch self {
        case .system:
            PulseLocalization.localizedString("language.system")
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        }
    }
}

public enum PulseLocalization {
    public static let languagePreferenceKey = "pulse.language.v1"

    public static var currentPreference: PulseLanguagePreference {
        let rawValue = UserDefaults.standard.string(forKey: languagePreferenceKey)
        return rawValue.flatMap(PulseLanguagePreference.init(rawValue:)) ?? .system
    }

    public static var currentLanguageIdentifier: String {
        currentPreference.localeIdentifier
    }

    public static var currentLocale: Locale {
        Locale(identifier: currentLanguageIdentifier)
    }

    public static func systemLanguageIdentifier(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        guard let preferred = preferredLanguages.first else { return "en" }
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }

    public static func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        let language = currentLanguageIdentifier
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language), arguments: arguments)
    }
}
