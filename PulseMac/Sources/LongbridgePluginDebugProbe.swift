import Darwin
import Foundation
import MachO

/// Boundary test for packaging the official Longbridge C SDK as a separately
/// loadable plugin. This deliberately validates only the bundle and ABI boundary;
/// live transport behavior is covered by the SDK live self-test.
enum LongbridgePluginDebugProbe {
    static let bundleName = "PulseLongbridgePlugin.bundle"
    static let executableName = "PulseLongbridgePlugin"
    static let expectedPluginAPIVersion = 1
    static let expectedSDKVersion = "4.4.1"

    static let requiredSymbols = [
        "lb_oauth_new",
        "lb_config_from_apikey",
        "lb_config_from_oauth",
        "lb_config_from_oauth_token",
        "lb_config_enable_overnight",
        "lb_config_disable_print_quote_packages",
        "lb_config_free",
        "lb_quote_context_new",
        "lb_quote_context_static_info",
        "lb_quote_context_quote",
        "lb_quote_context_candlesticks",
        "lb_quote_context_set_on_quote",
        "lb_quote_context_subscribe",
        "lb_quote_context_unsubscribe",
        "lb_quote_context_release",
        "lb_decimal_to_double",
        "lb_error_message",
        "lb_error_code",
    ]

    struct Result {
        let sdkVersion: String
        let sdkCommit: String
        let wasLoadedBeforeProbe: Bool
        let isLoadedAfterProbe: Bool
        let symbols: [String]
        let executablePath: String
    }

    enum ProbeError: LocalizedError {
        case pluginsDirectoryMissing
        case bundleMissing(URL)
        case invalidBundle(URL)
        case invalidPluginAPIVersion(expected: Int, actual: String)
        case invalidSDKVersion(expected: String, actual: String)
        case executableMissing(URL)
        case loadFailed(String)
        case symbolsMissing([String])
        case imageNotVisibleAfterLoad

        var errorDescription: String? {
            switch self {
            case .pluginsDirectoryMissing:
                "The app has no built-in PlugIns directory."
            case let .bundleMissing(url):
                "The Longbridge plugin bundle is missing at \(url.path)."
            case let .invalidBundle(url):
                "The Longbridge plugin bundle is invalid at \(url.path)."
            case let .invalidPluginAPIVersion(expected, actual):
                "Plugin API mismatch: expected \(expected), found \(String(describing: actual))."
            case let .invalidSDKVersion(expected, actual):
                "Longbridge SDK mismatch: expected \(expected), found \(String(describing: actual))."
            case let .executableMissing(url):
                "The Longbridge plugin executable is missing at \(url.path)."
            case let .loadFailed(message):
                "dlopen failed: \(message)"
            case let .symbolsMissing(symbols):
                "The Longbridge plugin is missing C ABI symbols: \(symbols.joined(separator: ", "))."
            case .imageNotVisibleAfterLoad:
                "The plugin passed dlopen but is not present in the process image list."
            }
        }
    }

    static func isLoaded() -> Bool {
        let imageCount = _dyld_image_count()
        for index in 0..<imageCount {
            guard let imageName = _dyld_get_image_name(index) else { continue }
            let path = String(cString: imageName)
            if path.hasSuffix("/\(bundleName)/Contents/MacOS/\(executableName)") {
                return true
            }
        }
        return false
    }

    /// Loads the official SDK locally and leaves it resident for the process
    /// lifetime. Unloading a Rust runtime-backed dylib is intentionally avoided.
    static func loadAndValidate() throws -> Result {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else {
            throw ProbeError.pluginsDirectoryMissing
        }

        let bundleURL = pluginsURL.appendingPathComponent(bundleName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw ProbeError.bundleMissing(bundleURL)
        }
        guard let pluginBundle = Bundle(url: bundleURL) else {
            throw ProbeError.invalidBundle(bundleURL)
        }

        let apiVersion = pluginBundle.object(forInfoDictionaryKey: "PulsePluginAPIVersion")
        guard (apiVersion as? NSNumber)?.intValue == expectedPluginAPIVersion else {
            throw ProbeError.invalidPluginAPIVersion(
                expected: expectedPluginAPIVersion,
                actual: String(describing: apiVersion)
            )
        }

        let sdkVersion = pluginBundle.object(forInfoDictionaryKey: "LongbridgeSDKVersion") as? String
        guard sdkVersion == expectedSDKVersion else {
            throw ProbeError.invalidSDKVersion(
                expected: expectedSDKVersion,
                actual: String(describing: sdkVersion)
            )
        }

        let executableURL = bundleURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ProbeError.executableMissing(executableURL)
        }

        let wasLoaded = isLoaded()
        dlerror()
        guard let handle = dlopen(executableURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "unknown loader error"
            throw ProbeError.loadFailed(message)
        }

        let missingSymbols = requiredSymbols.filter { symbol in
            dlsym(handle, symbol) == nil
        }
        guard missingSymbols.isEmpty else {
            throw ProbeError.symbolsMissing(missingSymbols)
        }
        guard isLoaded() else {
            throw ProbeError.imageNotVisibleAfterLoad
        }

        return Result(
            sdkVersion: sdkVersion ?? "unknown",
            sdkCommit: pluginBundle.object(forInfoDictionaryKey: "LongbridgeSDKCommit") as? String ?? "unknown",
            wasLoadedBeforeProbe: wasLoaded,
            isLoadedAfterProbe: true,
            symbols: requiredSymbols,
            executablePath: executableURL.path
        )
    }
}
