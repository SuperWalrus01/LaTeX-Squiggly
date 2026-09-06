import Foundation
import LaTeXUnicodeChecks

// Runs the Phase 0 suite without XCTest, which on macOS ships only inside
// Xcode.app. Exits non-zero on the first failing group's failures so this can
// gate a commit.

var totalChecks = 0
var totalFailures = 0

for group in CheckSuite.groups {
    let checker = CheckSuite.run(group)
    totalChecks += checker.count
    totalFailures += checker.failures.count

    let status = checker.failures.isEmpty ? "PASS" : "FAIL"
    print("\(status)  \(group.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(checker.count) checks")

    for failure in checker.failures {
        let file = URL(fileURLWithPath: "\(failure.file)").lastPathComponent
        print("      \(file):\(failure.line): \(failure.message)")
    }
}

print("")
if totalFailures == 0 {
    print("\(totalChecks) checks passed.")
} else {
    print("\(totalFailures) of \(totalChecks) checks FAILED.")
    exit(1)
}
