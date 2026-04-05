// Copyright © 2015 Abhishek Banthia

import Cocoa
import os
import OSLog

public enum Logger {
    private static let lifecycle = OSLog(subsystem: "com.tpak.Meridian", category: "lifecycle")
    private static let debugLog = OSLog(subsystem: "com.tpak.Meridian", category: "debug")

    /// Always-on logging for critical lifecycle events. Visible in Console.app.
    public static func production(_ message: String) {
        os_log(.default, log: lifecycle, "%{public}@", message)
    }

    /// Opt-in verbose logging for debugging. Visible in Console.app when enabled.
    public static func debug(_ message: String) {
        guard debugLoggingEnabled else { return }
        os_log(.default, log: debugLog, "%{private}@", message)
    }

    public static var debugLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "com.tpak.meridian.debugLoggingEnabled")
    }

    /// Export recent log entries to a file for sharing. Uses OSLogStore.
    public static func exportLog(to url: URL) throws {
        let store = try OSLogStore(scope: .system)
        let cutoff = store.position(date: Date().addingTimeInterval(-7 * 24 * 3600))
        let entries = try store.getEntries(at: cutoff, matching: NSPredicate(format: "subsystem == 'com.tpak.Meridian'"))
        let lines = entries.compactMap { entry -> String? in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            return "[\(logEntry.date.ISO8601Format())] [\(logEntry.category)] \(logEntry.composedMessage)"
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

public class PerfLogger: NSObject {
    static var panelLog = OSLog(subsystem: "com.tpak.Meridian",
                                category: "Open Panel")
    static let signpostID = OSSignpostID(log: panelLog)

    public class func disable() {
        panelLog = .disabled
    }

    public class func startMarker(_ name: StaticString) {
        os_signpost(.begin,
                    log: panelLog,
                    name: name,
                    signpostID: signpostID)
    }

    public class func endMarker(_ name: StaticString) {
        os_signpost(.end,
                    log: panelLog,
                    name: name,
                    signpostID: signpostID)
    }
}
