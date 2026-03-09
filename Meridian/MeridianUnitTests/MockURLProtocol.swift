// Copyright © 2015 Abhishek Banthia

import Foundation

/// A URLProtocol subclass that intercepts network requests for testing purposes.
/// Register mock responses by URL path pattern before running tests.
class MockURLProtocol: URLProtocol {
    /// Maps URL path patterns to (data, response, error) tuples.
    static var mockResponses: [String: (Data?, HTTPURLResponse?, Error?)] = [:]

    /// Convenience: register a successful JSON response for a given path substring.
    static func register(pathContaining path: String, statusCode: Int = 200, data: Data?) {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        mockResponses[path] = (data, response, nil)
    }

    /// Convenience: register an error response for a given path substring.
    static func registerError(pathContaining path: String, error: Error) {
        mockResponses[path] = (nil, nil, error)
    }

    /// Remove all registered mock responses.
    static func reset() {
        mockResponses.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let urlString = url.absoluteString

        for (pathPattern, mockResponse) in MockURLProtocol.mockResponses {
            if urlString.contains(pathPattern) {
                if let error = mockResponse.2 {
                    client?.urlProtocol(self, didFailWithError: error)
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }

                if let response = mockResponse.1 {
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }

                if let data = mockResponse.0 {
                    client?.urlProtocol(self, didLoad: data)
                }

                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }

        // No matching mock — fail with a clear error
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
