// Diagnostic test to verify Preferences storyboard loads correctly.
// This helps identify whether the empty Settings window is caused by
// storyboard loading failures or runtime rendering issues.

@testable import Meridian
import XCTest

class PreferencesStoryboardTests: XCTestCase {

    func testStoryboardLoads() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        XCTAssertNotNil(storyboard, "Preferences storyboard should load")
    }

    func testInitialControllerIsOneWindowController() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let controller = storyboard.instantiateInitialController()
        XCTAssertNotNil(controller, "Initial controller should not be nil")
        XCTAssertTrue(controller is OneWindowController,
                      "Initial controller should be OneWindowController, got \(type(of: controller as Any))")
    }

    func testWindowControllerHasWindow() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let wc = storyboard.instantiateInitialController() as? OneWindowController
        XCTAssertNotNil(wc, "Should cast to OneWindowController")
        XCTAssertNotNil(wc?.window, "Window controller should have a window")
    }

    func testContentViewControllerIsCenteredTabViewController() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let wc = storyboard.instantiateInitialController() as? OneWindowController
        XCTAssertNotNil(wc?.contentViewController,
                        "contentViewController should not be nil")
        XCTAssertTrue(wc?.contentViewController is CenteredTabViewController,
                      "contentViewController should be CenteredTabViewController, got \(type(of: wc?.contentViewController as Any))")
    }

    func testTabViewControllerHasThreeTabs() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let wc = storyboard.instantiateInitialController() as? OneWindowController
        let tabVC = wc?.contentViewController as? CenteredTabViewController
        XCTAssertNotNil(tabVC, "Tab view controller should not be nil")
        XCTAssertEqual(tabVC?.tabViewItems.count, 3,
                       "Should have 3 tab items, got \(tabVC?.tabViewItems.count ?? 0)")
    }

    func testFirstTabIsPreferencesViewController() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let wc = storyboard.instantiateInitialController() as? OneWindowController
        let tabVC = wc?.contentViewController as? CenteredTabViewController
        let firstTabVC = tabVC?.tabViewItems.first?.viewController
        XCTAssertNotNil(firstTabVC, "First tab's view controller should not be nil")
        XCTAssertTrue(firstTabVC is PreferencesViewController,
                      "First tab should be PreferencesViewController, got \(type(of: firstTabVC as Any))")
    }

    func testFirstTabViewLoads() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let wc = storyboard.instantiateInitialController() as? OneWindowController
        let tabVC = wc?.contentViewController as? CenteredTabViewController
        let firstTabVC = tabVC?.tabViewItems.first?.viewController
        // Force load the view
        _ = firstTabVC?.view
        XCTAssertNotNil(firstTabVC?.view, "First tab's view should load without crashing")
    }

    func testAllTabViewsLoad() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let wc = storyboard.instantiateInitialController() as? OneWindowController
        let tabVC = wc?.contentViewController as? CenteredTabViewController

        for (index, item) in (tabVC?.tabViewItems ?? []).enumerated() {
            let vc = item.viewController
            XCTAssertNotNil(vc, "Tab \(index) (\(item.label)) should have a view controller")
            _ = vc?.view
            XCTAssertNotNil(vc?.view, "Tab \(index) (\(item.label)) view should load")
        }
    }

    func testTabViewControllerViewLoads() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let wc = storyboard.instantiateInitialController() as? OneWindowController
        let tabVC = wc?.contentViewController as? CenteredTabViewController
        // Force load the tab VC's view — this triggers toolbar creation
        _ = tabVC?.view
        XCTAssertNotNil(tabVC?.view, "Tab view controller's view should load")
    }

    func testWindowHasToolbarAfterShow() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: Bundle(for: OneWindowController.self))
        let wc = storyboard.instantiateInitialController() as? OneWindowController
        // Trigger window loading
        wc?.loadWindow()
        _ = wc?.contentViewController?.view
        XCTAssertNotNil(wc?.window?.toolbar, "Window should have a toolbar after content loads")
    }
}
