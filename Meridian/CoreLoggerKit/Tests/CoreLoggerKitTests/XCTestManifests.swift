import XCTest

#if !canImport(ObjectiveC)
    public func allTests() -> [XCTestCaseEntry] {
        return [
            testCase(LoggerTests.allTests),
            testCase(PerfLoggerTests.allTests)
        ]
    }
#endif
