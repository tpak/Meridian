// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

@testable import Meridian
import XCTest

class NetworkManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Error Sentinel Tests

    func testInternalServerErrorProperties() {
        let error = NetworkManager.internalServerError
        XCTAssertEqual(error.domain, "APIError")
        XCTAssertEqual(error.code, 100)
    }

    func testUnableToGenerateURLErrorProperties() {
        let error = NetworkManager.unableToGenerateURL
        XCTAssertEqual(error.domain, "APIError")
        XCTAssertEqual(error.code, 100)
    }
}
