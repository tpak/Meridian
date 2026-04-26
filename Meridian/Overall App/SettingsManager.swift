import Cocoa
import CoreLoggerKit
import CoreModelKit
import UniformTypeIdentifiers

struct SettingsManager {
    private static let exportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".meridian")
    private static let defaultExportFilename = "meridian_settings.json"

    // Sparkle stores the auto-update prefs in UserDefaults under these keys.
    // We round-trip them so imported settings reproduce the user's update cadence.
    private enum SparkleDefaultKey {
        static let enableAutomaticChecks = "SUEnableAutomaticChecks"
        static let automaticallyUpdate = "SUAutomaticallyUpdate"
        static let scheduledCheckInterval = "SUScheduledCheckInterval"
    }

    // Every user-settable preference. Each appears in some Settings tab
    // (General/Appearance/About) and survives export → import.
    private static let preferenceKeys: [String] = [
        // Appearance tab — time/theme/format
        UserDefaultKeys.selectedTimeZoneFormatKey,
        UserDefaultKeys.themeKey,
        UserDefaultKeys.relativeDateKey,
        // Appearance tab — display toggles
        UserDefaultKeys.displayFutureSliderKey,
        UserDefaultKeys.sunriseSunsetTime,
        UserDefaultKeys.showAppInForeground,
        UserDefaultKeys.userFontSizePreference,
        UserDefaultKeys.truncateTextLength,
        UserDefaultKeys.futureSliderRange,
        UserDefaultKeys.appDisplayOptions,
        // Appearance tab — menubar
        UserDefaultKeys.showDayInMenu,
        UserDefaultKeys.showDateInMenu,
        UserDefaultKeys.showPlaceInMenu,
        UserDefaultKeys.menubarCompactMode,
        UserDefaultKeys.defaultMenubarMode,
        // About tab — debug logging
        UserDefaultKeys.debugLoggingEnabled,
        // About tab — Sparkle auto-update settings
        SparkleDefaultKey.enableAutomaticChecks,
        SparkleDefaultKey.automaticallyUpdate,
        SparkleDefaultKey.scheduledCheckInterval,
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

        var prefs: [String: Any] = [:]
        for key in preferenceKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                prefs[key] = value
            }
        }

        // startAtLogin is the actual SMAppService state, not what's in UserDefaults
        // (UserDefaults can drift from the system state if the user toggled it elsewhere).
        let startAtLoginEnabled = StartupManager.isLoginItemEnabled()

        let payload: [String: Any] = [
            ExportKey.version: 1,
            ExportKey.timezones: timezoneBase64,
            ExportKey.preferences: prefs,
            ExportKey.startAtLogin: startAtLoginEnabled,
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

        // Apply UserDefaults preferences (Appearance + About + Sparkle)
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

        // Refresh UI + Sparkle in-memory state from imported UserDefaults
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .customLabelChanged, object: nil)
            if let panel = PanelController.panel() {
                panel.updateDefaultPreferences()
                panel.updateTableContent()
            }
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.statusItemForPanel().refresh()
                // Re-read Sparkle prefs into the live updater so the new schedule
                // takes effect immediately rather than next launch.
                let updater = appDelegate.updaterController.updater
                if let v = UserDefaults.standard.object(forKey: SparkleDefaultKey.enableAutomaticChecks) as? Bool {
                    updater.automaticallyChecksForUpdates = v
                }
                if let v = UserDefaults.standard.object(forKey: SparkleDefaultKey.automaticallyUpdate) as? Bool {
                    updater.automaticallyDownloadsUpdates = v
                }
                if let v = UserDefaults.standard.object(forKey: SparkleDefaultKey.scheduledCheckInterval) as? TimeInterval {
                    updater.updateCheckInterval = v
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
