import Cocoa
import CoreLoggerKit
import CoreModelKit
import UniformTypeIdentifiers

struct SettingsManager {
    private static let exportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".meridian")
    private static let defaultExportFilename = "meridian_settings.json"

    // Every user-settable preference. Each appears in some Settings tab
    // (General/Appearance/About) and survives export → import.
    // (defaultMenubarMode / "com.tpak.meridian.shouldDefaultToCompactMode"
    //  is intentionally omitted — it's a dead key with no readers.)
    // startAtLogin is exported alongside the rest, but APPLIED via StartupManager
    // (SMAppService.mainApp) during import so the system actually registers/unregisters
    // the login item — writing UserDefaults alone wouldn't change behavior.
    private static let startAtLoginKey = UserDefaultKeys.startAtLogin

    private enum ExportKey {
        static let version = "version"
        static let timezones = "timezones"
        static let preferences = "preferences"
        static let startAtLogin = "startAtLogin"
        static let sparkle = "sparkle"
    }

    private enum SparkleExportField {
        static let automaticallyChecksForUpdates = "automaticallyChecksForUpdates"
        static let automaticallyDownloadsUpdates = "automaticallyDownloadsUpdates"
        static let updateCheckInterval = "updateCheckIntervalSeconds"
    }

    private enum ImportError: LocalizedError {
        case invalidFormat
        case unsupportedVersion
        case invalidTimezoneData

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "The file is not a valid Meridian settings file."
            case .unsupportedVersion: return "This settings file was created by a newer version of Meridian."
            case .invalidTimezoneData: return "The settings file contains invalid timezone data."
            }
        }
    }

    // MARK: - Public API

    static func exportSettings() {
        guard let jsonData = buildJSON() else { return }
        try? FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let panel = NSSavePanel()
        panel.directoryURL = exportDirectory
        panel.nameFieldStringValue = defaultExportFilename
        panel.allowedContentTypes = [UTType.json]
        panel.prompt = "Export"
        panel.title = "Export Meridian Settings"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try jsonData.write(to: url, options: .atomic)
        } catch {
            Logger.debug("Settings export failed: \(error)")
            showAlert("Export failed", detail: error.localizedDescription)
        }
    }

    static func copySettingsToClipboard() {
        guard let jsonData = buildJSON(),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonString, forType: .string)
        NSApp.keyWindow?.contentView?.makeToast("Settings copied to clipboard")
    }

    static func importSettings() {
        let panel = NSOpenPanel()
        panel.directoryURL = exportDirectory
        panel.allowedContentTypes = [UTType.json]
        panel.prompt = "Import"
        panel.title = "Import Meridian Settings"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            try applySettings(from: data)
        } catch {
            Logger.debug("Settings import failed: \(error)")
            showAlert("Import failed", detail: error.localizedDescription)
        }
    }

    // MARK: - Private

    // Issue #97 — v2 JSON keys. Stable string identifiers used in the
    // exported file. Keep these constants frozen across releases since
    // users' export files persist them.
    private enum V2Key {
        static let showSunriseSunset = "showSunriseSunset"
        static let showFutureSlider = "showFutureSlider"
        static let showDayInMenubar = "showDayInMenubar"
        static let showDateInMenubar = "showDateInMenubar"
        static let showPlaceNameInMenubar = "showPlaceNameInMenubar"
        static let floatOnTop = "floatOnTop"
        static let menubarMode = "menubarMode"
        static let theme = "theme"
        static let relativeDateDisplay = "relativeDateDisplay"
        static let appPresentation = "appPresentation"
        static let timeFormat = "timeFormat"
        static let userFontSize = "userFontSize"
        static let truncateTextLength = "truncateTextLength"
        static let futureSliderRange = "futureSliderRange"
        static let debugLoggingEnabled = "debugLoggingEnabled"
    }

    // Build a v2 JSON payload — bools are emitted as bools, enums as named
    // case strings ("compact", "twelveHour", etc.) instead of raw ints.
    // The user's complaint that motivated issue #97 — exported settings
    // showing "showSunriseSetTime: 0" for a setting that was on — is
    // resolved here: same value is now exported as "showSunriseSunset": true.
    // Internal so SettingsManagerVersioningTests can verify the v2 schema
    // and v1-back-compat decoding without going through the file picker.
    static func buildJSON() -> Data? {
        let store = DataStore.shared()
        let timezoneBase64 = store.timezones().map { $0.base64EncodedString() }
        let defaults = UserDefaults.standard

        let prefs: [String: Any] = [
            V2Key.showSunriseSunset: store.showSunriseSunset,
            V2Key.showFutureSlider: store.showFutureSlider,
            V2Key.showDayInMenubar: store.showDayInMenubar,
            V2Key.showDateInMenubar: store.showDateInMenubar,
            V2Key.showPlaceNameInMenubar: store.showPlaceNameInMenubar,
            V2Key.floatOnTop: store.floatOnTop,
            V2Key.menubarMode: store.menubarMode.jsonName,
            V2Key.theme: store.theme.jsonName,
            V2Key.relativeDateDisplay: store.relativeDateDisplay.jsonName,
            V2Key.appPresentation: store.appPresentation.jsonName,
            V2Key.timeFormat: store.timeFormat.jsonName,
            V2Key.userFontSize: defaults.integer(forKey: UserDefaultKeys.userFontSizePreference),
            V2Key.truncateTextLength: defaults.integer(forKey: UserDefaultKeys.truncateTextLength),
            V2Key.futureSliderRange: defaults.integer(forKey: UserDefaultKeys.futureSliderRange),
            V2Key.debugLoggingEnabled: defaults.bool(forKey: UserDefaultKeys.debugLoggingEnabled)
        ]

        // startAtLogin reflects the actual SMAppService state, not UserDefaults.
        let startAtLoginEnabled = StartupManager.isLoginItemEnabled()

        // Sparkle prefs come from the live updater because Sparkle registers
        // its defaults lazily — UserDefaults can be nil even when the updater
        // has a real running interval value.
        var sparkle: [String: Any] = [:]
        if let updater = (NSApp.delegate as? AppDelegate)?.updaterController.updater {
            sparkle[SparkleExportField.automaticallyChecksForUpdates] = updater.automaticallyChecksForUpdates
            sparkle[SparkleExportField.automaticallyDownloadsUpdates] = updater.automaticallyDownloadsUpdates
            sparkle[SparkleExportField.updateCheckInterval] = updater.updateCheckInterval
        }

        let payload: [String: Any] = [
            ExportKey.version: 2,
            ExportKey.timezones: timezoneBase64,
            ExportKey.preferences: prefs,
            ExportKey.startAtLogin: startAtLoginEnabled,
            ExportKey.sparkle: sparkle
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    static func applySettings(from data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }

        // version: 1 came from 2.19/2.20; version: 2 is post-#97. We accept
        // either so users importing older export files still get correct
        // values (with the inversion undone).
        let version = json[ExportKey.version] as? Int ?? 0

        // Validate and decode timezones (format unchanged across versions).
        var timezoneBlobs: [Data] = []
        if let encoded = json[ExportKey.timezones] as? [String] {
            for base64 in encoded {
                guard let blob = Data(base64Encoded: base64),
                      TimezoneData.customObject(from: blob) != nil else {
                    throw ImportError.invalidTimezoneData
                }
                timezoneBlobs.append(blob)
            }
        }

        if let prefs = json[ExportKey.preferences] as? [String: Any] {
            switch version {
            case 1: applyV1Preferences(prefs)
            case 2: applyV2Preferences(prefs)
            default: throw ImportError.unsupportedVersion
            }
        }

        // Apply startAtLogin via StartupManager — UserDefaults alone won't
        // register/unregister the SMAppService login item.
        if let startAtLogin = json[ExportKey.startAtLogin] as? Bool {
            UserDefaults.standard.set(startAtLogin, forKey: startAtLoginKey)
            StartupManager().toggleLogin(startAtLogin)
        }

        DataStore.shared().setTimezones(timezoneBlobs)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .customLabelChanged, object: nil)
            if let panel = PanelController.panel() {
                panel.updateDefaultPreferences()
                panel.updateTableContent()
            }
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.statusItemForPanel().refresh()
                if let sparkle = json[ExportKey.sparkle] as? [String: Any] {
                    let updater = appDelegate.updaterController.updater
                    if let v = sparkle[SparkleExportField.automaticallyChecksForUpdates] as? Bool {
                        updater.automaticallyChecksForUpdates = v
                    }
                    if let v = sparkle[SparkleExportField.automaticallyDownloadsUpdates] as? Bool {
                        updater.automaticallyDownloadsUpdates = v
                    }
                    if let v = sparkle[SparkleExportField.updateCheckInterval] as? TimeInterval {
                        updater.updateCheckInterval = v
                    }
                }
            }
            NSApp.keyWindow?.contentView?.makeToast("Settings imported")
        }
    }

    // v1 — legacy raw-int preferences from 2.19/2.20 export files.
    // Read the legacy keys, apply via typed accessors so the inversion is
    // undone exactly once on import. We do NOT write the legacy UserDefaults
    // keys here — migration runs at every launch, but post-2.21 imports
    // should put data directly into the modernized schema.
    private static func applyV1Preferences(_ prefs: [String: Any]) {
        let store = DataStore.shared()
        let defaults = UserDefaults.standard

        // Inverted bools — legacy 0 = show, 1 = hide.
        if let v = prefs["showSunriseSetTime"] as? Int { store.showSunriseSunset = (v == 0) }
        if let v = prefs["displayFutureSlider"] as? Int { store.showFutureSlider = (v == 0) }
        if let v = prefs["showDay"] as? Int { store.showDayInMenubar = (v == 0) }
        if let v = prefs["showDate"] as? Int { store.showDateInMenubar = (v == 0) }
        if let v = prefs["showPlaceName"] as? Int { store.showPlaceNameInMenubar = (v == 0) }

        // Non-inverted bool — legacy 1 = float.
        if let v = prefs["displayAppAsForegroundApp"] as? Int { store.floatOnTop = (v == 1) }

        // Time format — value semantics unchanged, just key rename.
        if let v = prefs["is24HourFormatSelected"] as? Int { store.timeFormat = TimeFormat(rawValue: v) ?? .twelveHour }

        // Already-correct enum keys (kept by name in the legacy export too).
        if let v = prefs["defaultTheme"] as? Int { store.theme = Theme(rawValue: v) ?? .light }
        if let v = prefs["relativeDate"] as? Int { store.relativeDateDisplay = RelativeDateDisplay(rawValue: v) ?? .relative }
        if let v = prefs["com.tpak.meridian.appDisplayOptions"] as? Int { store.appPresentation = AppPresentation(rawValue: v) ?? .menubarOnly }
        if let v = prefs["com.tpak.meridian.menubarCompactMode"] as? Int { store.menubarMode = MenubarMode(rawValue: v) ?? .standard }

        // Untouched — copy raw values.
        if let v = prefs["userFontSize"] { defaults.set(v, forKey: UserDefaultKeys.userFontSizePreference) }
        if let v = prefs["truncateTextLength"] { defaults.set(v, forKey: UserDefaultKeys.truncateTextLength) }
        if let v = prefs["sliderDayRange"] { defaults.set(v, forKey: UserDefaultKeys.futureSliderRange) }
        if let v = prefs["com.tpak.meridian.debugLoggingEnabled"] as? Bool {
            defaults.set(v, forKey: UserDefaultKeys.debugLoggingEnabled)
        }
    }

    // v2 — typed bools and named enums, no inversion.
    private static func applyV2Preferences(_ prefs: [String: Any]) {
        let store = DataStore.shared()
        let defaults = UserDefaults.standard

        // Bools — write directly.
        if let v = prefs[V2Key.showSunriseSunset] as? Bool { store.showSunriseSunset = v }
        if let v = prefs[V2Key.showFutureSlider] as? Bool { store.showFutureSlider = v }
        if let v = prefs[V2Key.showDayInMenubar] as? Bool { store.showDayInMenubar = v }
        if let v = prefs[V2Key.showDateInMenubar] as? Bool { store.showDateInMenubar = v }
        if let v = prefs[V2Key.showPlaceNameInMenubar] as? Bool { store.showPlaceNameInMenubar = v }
        if let v = prefs[V2Key.floatOnTop] as? Bool { store.floatOnTop = v }

        // Enums — parse the case name string. Unknown names fall through to
        // existing value (typed accessor leaves the underlying key alone).
        if let s = prefs[V2Key.menubarMode] as? String, let m = MenubarMode(jsonName: s) { store.menubarMode = m }
        if let s = prefs[V2Key.theme] as? String, let t = Theme(jsonName: s) { store.theme = t }
        if let s = prefs[V2Key.relativeDateDisplay] as? String, let r = RelativeDateDisplay(jsonName: s) { store.relativeDateDisplay = r }
        if let s = prefs[V2Key.appPresentation] as? String, let a = AppPresentation(jsonName: s) { store.appPresentation = a }
        if let s = prefs[V2Key.timeFormat] as? String, let t = TimeFormat(jsonName: s) { store.timeFormat = t }

        // Untouched — copy raw values.
        if let v = prefs[V2Key.userFontSize] { defaults.set(v, forKey: UserDefaultKeys.userFontSizePreference) }
        if let v = prefs[V2Key.truncateTextLength] { defaults.set(v, forKey: UserDefaultKeys.truncateTextLength) }
        if let v = prefs[V2Key.futureSliderRange] { defaults.set(v, forKey: UserDefaultKeys.futureSliderRange) }
        if let v = prefs[V2Key.debugLoggingEnabled] as? Bool {
            defaults.set(v, forKey: UserDefaultKeys.debugLoggingEnabled)
        }
    }

    private static func showAlert(_ message: String, detail: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = detail
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
