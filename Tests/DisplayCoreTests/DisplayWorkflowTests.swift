import XCTest
@testable import DisplayCore

final class DisplayWorkflowTests: XCTestCase {
    func testHotPlugGapDoesNotCountAsUnplug() {
        // External attached but not active yet: presence alone must block recovery.
        XCTAssertFalse(DisplayWorkflow.shouldRecoverBuiltin(externalPresent: true,
                                                            secondsSinceExternalSeen: 30,
                                                            builtinEnabled: false,
                                                            workflowClearedBuiltin: true))
    }

    func testUnplugWaitsForGracePeriodBeforeRestoringBuiltin() {
        XCTAssertFalse(DisplayWorkflow.shouldRecoverBuiltin(externalPresent: false,
                                                            secondsSinceExternalSeen: 0.4,
                                                            builtinEnabled: false,
                                                            workflowClearedBuiltin: true))
        XCTAssertTrue(DisplayWorkflow.shouldRecoverBuiltin(externalPresent: false,
                                                           secondsSinceExternalSeen: 2,
                                                           builtinEnabled: false,
                                                           workflowClearedBuiltin: false))
    }

    func testRestoringBuiltinAfterWorkflowClearedIt() {
        XCTAssertTrue(DisplayWorkflow.shouldRecoverBuiltin(externalPresent: false,
                                                           secondsSinceExternalSeen: 5,
                                                           builtinEnabled: true,
                                                           workflowClearedBuiltin: true))
    }

    func testSteadySingleScreenStateNeedsNoRecovery() {
        XCTAssertFalse(DisplayWorkflow.shouldRecoverBuiltin(externalPresent: false,
                                                            secondsSinceExternalSeen: 60,
                                                            builtinEnabled: true,
                                                            workflowClearedBuiltin: false))
    }

    func testWorkflowReassertsWhenSystemTurnsBuiltinBackOn() {
        XCTAssertTrue(DisplayWorkflow.shouldKeepBuiltinOff(autoWorkflow: true,
                                                           workflowHoldsBuiltinOff: true,
                                                           userRestoredBuiltin: false,
                                                           externalOnline: true,
                                                           builtinEnabled: true))
    }

    func testReassertRespectsUserOverrideAndDisabledWorkflow() {
        XCTAssertFalse(DisplayWorkflow.shouldKeepBuiltinOff(autoWorkflow: true,
                                                            workflowHoldsBuiltinOff: true,
                                                            userRestoredBuiltin: true,
                                                            externalOnline: true,
                                                            builtinEnabled: true))
        XCTAssertFalse(DisplayWorkflow.shouldKeepBuiltinOff(autoWorkflow: false,
                                                            workflowHoldsBuiltinOff: true,
                                                            userRestoredBuiltin: false,
                                                            externalOnline: true,
                                                            builtinEnabled: true))
        XCTAssertFalse(DisplayWorkflow.shouldKeepBuiltinOff(autoWorkflow: true,
                                                            workflowHoldsBuiltinOff: true,
                                                            userRestoredBuiltin: false,
                                                            externalOnline: false,
                                                            builtinEnabled: true))
    }
}
