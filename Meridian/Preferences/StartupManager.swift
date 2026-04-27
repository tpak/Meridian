// Copyright © 2015 Abhishek Banthia

import CoreLoggerKit
import ServiceManagement

struct StartupManager {
    func toggleLogin(_ shouldStartAtLogin: Bool) {
        do {
            if shouldStartAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.production("Failed to toggle login item: \(error)")
        }
    }

    static func isLoginItemEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
}
