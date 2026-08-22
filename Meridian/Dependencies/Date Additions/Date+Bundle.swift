//
//  Date+Bundle.swift
//  DateTools
//
//  Created by Matthew York on 8/26/16.
//  Copyright © 2016 Matthew York. All rights reserved.
//

import Foundation

public extension Bundle {
    class func dateToolsBundle() -> Bundle {
        // Upstream anchored this on `Bundle(for: Constants.self)` because DateTools shipped as its
        // own framework. Here the sources compile straight into the app target, so any class from
        // that target resolves to the same bundle — and AppDelegate is one that already exists,
        // unlike Constants, which survived only to be pointed at (issue #198).
        //
        // Deliberately NOT Bundle.main: under XCTest the main bundle is the test runner, not
        // Meridian.app, and the Bundle(path:) below force-unwraps.
        let assetPath = Bundle(for: AppDelegate.self).resourcePath!
        return Bundle(path: NSString(string: assetPath).appendingPathComponent("DateTools.bundle"))!
    }
}
