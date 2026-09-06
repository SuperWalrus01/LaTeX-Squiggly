import XCTest
@testable import LaTeXUnicodeChecks

/// Exposes the suite to `swift test`. The expectations themselves live in
/// `Sources/LaTeXUnicodeChecks` so that they can also run without Xcode, via
/// `swift run latex-unicode-check`. This wrapper only reports.
final class CheckSuiteTests: XCTestCase {

    func test_allGroups() {
        for group in CheckSuite.groups {
            let checker = CheckSuite.run(group)
            XCTAssertGreaterThan(checker.count, 0, "\(group.name) ran no checks")
            for failure in checker.failures {
                XCTFail("[\(group.name)] \(failure.message)",
                        file: failure.file, line: failure.line)
            }
        }
    }
}
