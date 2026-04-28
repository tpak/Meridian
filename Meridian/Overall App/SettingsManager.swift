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
    // Modernized typed keys (issue #97). The bool semantics migration in
    // AppDefaults moves user data to these on first launch of 2.21+ and
    // deletes the legacy showSunriseSetTime / displayFutureSlider / showDay
    // / showDate / showPlaceName / displayAppAsForegroundApp /
    // is24HourFormatSelected keys. Export/import operate on the new keys.
    // Commit 5/5 of issue #97 layers a typed JSON schema (named bools and
    // enum cases) over this; for now the values are still raw Bool / Int.
    private static let preferenceKeys: [String] = [
        // Appearance tab — time/theme/format
        UserDefaultKeys.timeFormat,
        UserDefaultKeys.themeKey,
        UserDefaultKeys.relativeDateKey,
        // Appearance tab — display toggles
        UserDefaultKeys.showFutureSlider,
        UserDefaultKeys.showSunriseSunset,
        UserDefaultKeys.floatOnTop,
        UserDefaultKeys.userFontSizePreference,
        UserDefaultKeys.truncateTextLength,
        UserDefaultKeys.futureSliderRange,
        UserDefaultKeys.appDisplayOptions,
        // Appearance tab — menubar
        UserDefaultKeys.showDayInMenubar,
        UserDefaultKeys.showDateInMenubar,
        UserDefaultKeys.showPlaceNameInMenubar,
        UserDefaultKeys.menubarCompactMode,
        // About tab — debug logging
        UserDefaultKeys.debugLoggingEnabled
    ]

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

    private static func buildJSON() -> Data? {
        let timezoneBase64 = DataStore.shared().timezones().map { $0.base64EncodedString() }

        // For UserDefaults-backed prefs, fall back to the registered default
        // (see AppDefaults.defaultsDictionary) so we never silently drop a key
        // the user has never explicitly touched.
        var prefs: [String: Any] = [:]
        for key in preferenceKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                prefs[key] = value
            }
        }

        // startAtLogin is the actual SMAppService state, not what's in UserDefaults
        // (UserDefaults can drift from the system state if the user toggled it elsewhere).
        let startAtLoginEnabled = StartupManager.isLoginItemEnabled()

        // Sparkle prefs are read from the live updater, NOT from UserDefaults.
        // Sparkle uses lazy registration — if the user has never opened the
        // schedule picker, SUScheduledCheckInterval is nil in UserDefaults
        // even though the updater has a real running value (typically 86400).
        var sparkle: [String: Any] = [:]
        if let updater = (NSApp.delegate as? AppDelegate)?.updaterController.updater {
            sparkle[SparkleExportField.automaticallyChecksForUpdates] = updater.automaticallyChecksForUpdates
            sparkle[SparkleExportField.automaticallyDownloadsUpdates] = updater.automaticallyDownloadsUpdates
            sparkle[SparkleExportField.updateCheckInterval] = updater.updateCheckInterval
        }

        let payload: [String: Any] = [
            ExportKey.version: 1,
            ExportKey.timezones: timezoneBase64,
            ExportKey.preferences: prefs,
            ExportKey.startAtLogin: startAtLoginEnabled,
            ExportKey.sparkle: sparkle,
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func applySettings(from data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }
        guard let version = json[ExportKey.version] as? Int, version == 1 else {
            throw ImportError.unsupportedVersion
        }

        // Validate and decode timezones
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

        // Apply UserDefaults preferences (Appearance + About debug logging)
        if let prefs = json[ExportKey.preferences] as? [String: Any] {
            for key in preferenceKeys {
                if let value = prefs[key] {
                    UserDefaults.standard.set(value, forKey: key)
                }
            }
        }

        // Apply startAtLogin via StartupManager — UserDefaults alone won't register/unregister
        // the SMAppService login item, so toggle it explicitly.
        if let startAtLogin = json[ExportKey.startAtLogin] as? Bool {
            UserDefaults.standard.set(startAtLogin, forKey: startAtLoginKey)
            StartupManager().toggleLogin(startAtLogin)
        }

        // Apply timezones
        DataStore.shared().setTimezones(timezoneBlobs)

        // Refresh UI + apply Sparkle prefs to the live updater
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .customLabelChanged, object: nil)
            if let panel = PanelController.panel() {
                panel.updateDefaultPreferences()
                panel.updateTableContent()
            }
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.statusItemForPanel().refresh()
                // Apply Sparkle prefs from the import payload directly to the live
                // updater so the new schedule takes effect immediately. Setting these
                // on the updater also writes them to UserDefaults under Sparkle's keys.
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
