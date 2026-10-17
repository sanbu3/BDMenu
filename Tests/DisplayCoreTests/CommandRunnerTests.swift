import XCTest
@testable import DisplayCore

final class CommandRunnerTests: XCTestCase {
    func testNonzeroExitIsFailureAndPreservesBothStreams() {
        let result = CommandRunner.run("/bin/sh", ["-c", "printf output; printf failure >&2; exit 7"])
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.output, "output")
        XCTAssertEqual(result.error, "failure")
    }
    func testLargeStdoutAndStderrCannotDeadlock() {
        let result = CommandRunner.run("/bin/sh", ["-c", "awk 'BEGIN {for(i=0;i<20000;i++) print \"abcdefghij\"}'; awk 'BEGIN {for(i=0;i<20000;i++) print \"abcdefghij\"}' >&2"])
        XCTAssertTrue(result.succeeded)
        XCTAssertGreaterThan(result.output.count, 100000)
        XCTAssertGreaterThan(result.error.count, 100000)
    }
    func testTimeoutKillsAProcessIgnoringTermination() {
        let start = Date()
        let result = CommandRunner.run("/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.1)
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testArgumentsAreNotInterpretedByShell() {
        let value = "a b; $(echo executed)"
        let result = CommandRunner.run("/usr/bin/printf", ["%s", value])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, value)
    }
    func testMissingExecutableReportsError() {
        let result = CommandRunner.run("/nonexistent/BDMenu-helper", [])
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.error.isEmpty)
    }
}
