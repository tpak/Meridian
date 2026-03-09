// Copyright © 2015 Abhishek Banthia

import Cocoa
import os
public class Logger: NSObject {
    let logObjc = OSLog(subsystem: "com.tpak.Meridian", category: "app")

    public class func log(object annotations: [String: Any]?, for event: NSString) {
        #if DEBUG
            os_log(.default, "[%@] - [%@]", event, annotations ?? [:])
        #endif
    }

    public class func info(_ message: String) {
        #if DEBUG
            os_log(.info, "%@", message)
        #endif
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
