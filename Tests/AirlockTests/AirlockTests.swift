import XCTest
import SwiftUI
@testable import Airlock

private final class CallBox {
    var count = 0
}

final class AirlockTests: XCTestCase {
    func testCheckStatusEquality() {
        XCTAssertEqual(CheckStatus.pending, CheckStatus.pending)
        XCTAssertEqual(CheckStatus.success, CheckStatus.success)
        XCTAssertNotEqual(CheckStatus.pending, CheckStatus.success)
    }

    func testCheckError() {
        let error = CheckError(message: "Test error", recoveryAction: "Try again")
        XCTAssertEqual(error.message, "Test error")
        XCTAssertEqual(error.recoveryAction, "Try again")
        XCTAssertEqual(error.errorDescription, "Test error")
    }

    func testPermissionGrantStateBooleanView() {
        XCTAssertTrue(PermissionGrantState.granted.isGranted)
        XCTAssertFalse(PermissionGrantState.notGranted.isGranted)
        XCTAssertFalse(PermissionGrantState.requiresManualVerification("Manual").isGranted)
    }

    func testCustomPermissionsExposeCustomSetupActions() {
        XCTAssertEqual(PermissionType.automation.requestButtonLabel, "Custom Setup")
        XCTAssertEqual(PermissionType.files.requestButtonLabel, "Custom Setup")

        guard case .requiresCustomHandling = PermissionType.automation.requestAvailability else {
            return XCTFail("Automation should require app-specific request handling.")
        }

        guard case .requiresCustomHandling = PermissionType.files.requestAvailability else {
            return XCTFail("Files should require app-specific request handling.")
        }
    }

    func testAccessibilityDefaultConfigurationInjectsAppName() {
        let configuration = AccessibilityCheck.Configuration.default(
            appName: "Flow",
            purpose: "track Finder windows"
        )

        XCTAssertTrue(configuration.description.contains("Flow"))
        XCTAssertTrue(configuration.detailDescription.contains("Flow"))
        XCTAssertTrue(configuration.instructions.joined(separator: " ").contains("Flow"))
    }

    @MainActor
    func testAirlockManagerInitialization() async {
        let checks: [AccessibilityCheck] = [AccessibilityCheck()]
        let manager = AirlockManager(appName: "Test", checks: checks)

        XCTAssertEqual(manager.appName, "Test")
        XCTAssertEqual(manager.checks.count, 1)
        XCTAssertFalse(manager.isComplete)
        XCTAssertTrue(manager.isActive)
    }

    @MainActor
    func testPermissionCheckerUsesCustomStateProvider() {
        let checker = PermissionChecker(permissions: [.automation, .files]) { permission in
            switch permission {
            case .automation:
                return .granted
            case .files:
                return .requiresManualVerification("Need a folder-specific probe.")
            default:
                return permission.authorizationState
            }
        }

        XCTAssertEqual(checker.state(for: .automation), .granted)
        XCTAssertEqual(
            checker.state(for: .files),
            .requiresManualVerification("Need a folder-specific probe.")
        )
        XCTAssertFalse(checker.allGranted)
        XCTAssertTrue(checker.isGranted(.automation))
        XCTAssertFalse(checker.isGranted(.files))
    }

    @MainActor
    func testPermissionCheckerRequestHandlerUpdatesState() async {
        let checker = PermissionChecker(
            permissions: [.automation],
            stateProvider: { _ in .notGranted },
            requestHandler: { permission in
                XCTAssertEqual(permission, .automation)
                return .granted
            }
        )

        let updatedState = await checker.requestAccess(for: .automation)

        XCTAssertEqual(updatedState, .granted)
        XCTAssertEqual(checker.state(for: .automation), .granted)
        XCTAssertTrue(checker.isGranted(.automation))
    }

    @MainActor
    func testPermissionsCheckUsesCustomStateProvider() async {
        let check = PermissionsCheck(
            permissions: [.automation, .files],
            stateProvider: { permission in
                switch permission {
                case .automation:
                    return .granted
                case .files:
                    return .notGranted
                default:
                    return permission.authorizationState
                }
            }
        )

        let passed = await check.validate()

        XCTAssertFalse(passed)
        XCTAssertEqual(check.state(for: .automation), .granted)
        XCTAssertEqual(check.state(for: .files), .notGranted)
        XCTAssertEqual(check.currentlyGranted, [.automation])
    }

    @MainActor
    func testLicenseActivationCheckSuccessPersistsKey() async {
        let storageKey = "airlock.tests.license.success.\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: storageKey)

        let check = LicenseActivationCheck(
            storageKey: storageKey,
            validator: { licenseKey, machineID in
                XCTAssertEqual(licenseKey, "VALID-KEY")
                XCTAssertEqual(machineID, "machine-id")
                return .init(isValid: true)
            },
            machineIDProvider: { "machine-id" }
        )

        await check.submitLicenseKey("VALID-KEY")

        XCTAssertEqual(check.status, .success)
        XCTAssertNil(check.validationError)
        XCTAssertEqual(UserDefaults.standard.string(forKey: storageKey), "VALID-KEY")

        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    @MainActor
    func testLicenseActivationCheckFailureSetsError() async {
        let check = LicenseActivationCheck(
            validator: { _, _ in
                .init(isValid: false, failureMessage: "Invalid license key.")
            },
            machineIDProvider: { "machine-id" }
        )

        await check.submitLicenseKey("BAD-KEY")

        XCTAssertEqual(check.status, .active)
        XCTAssertEqual(check.validationError, "Invalid license key.")
    }

    @MainActor
    func testLicenseValidateIsPurePredicate() async {
        let box = CallBox()
        let check = LicenseActivationCheck(
            validator: { _, _ in
                box.count += 1
                return .init(isValid: true)
            },
            machineIDProvider: { "machine-id" }
        )
        check.licenseKey = "VALID-KEY"

        // validate() must not hit the network — it only reports current status.
        _ = await check.validate()
        _ = await check.validate()
        XCTAssertEqual(box.count, 0)

        // The stored-key path runs the validator exactly once.
        await check.validateStoredKeyIfNeeded()
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(check.status, .success)
        let passed = await check.validate()
        XCTAssertTrue(passed)
    }

    // MARK: - Navigator

    @MainActor
    private func makeNavigator(ids: [String]) -> AirlockNavigator {
        let steps = ids.map { id in
            AnyAirlockStep(AirlockStep(id: id, title: id, icon: "circle") { Text(id) })
        }
        return AirlockNavigator(appName: "Test", steps: steps)
    }

    @MainActor
    func testStepBuilderSupportsConditionalsAndLoops() {
        let includeExtra = true
        let navigator = AirlockNavigator(appName: "Test") {
            AirlockStep(id: "a", title: "A", icon: "circle") { Text("a") }
            if includeExtra {
                AirlockStep(id: "b", title: "B", icon: "circle") { Text("b") }
            }
            for index in 0..<2 {
                AirlockStep(id: "loop-\(index)", title: "L", icon: "circle") { Text("l") }
            }
        }

        XCTAssertEqual(navigator.steps.map(\.id), ["a", "b", "loop-0", "loop-1"])
    }

    @MainActor
    func testGoToNavigatesBackWithoutCrashing() {
        let navigator = makeNavigator(ids: ["a", "b", "c"])
        XCTAssertEqual(navigator.currentIndex, 0)

        // Steps without validation advance synchronously.
        navigator.goToNext()
        navigator.goToNext()
        XCTAssertEqual(navigator.currentIndex, 2)

        navigator.goTo(index: 0)
        XCTAssertEqual(navigator.currentIndex, 0)

        // Jumping to the current index must not trap on an invalid range.
        navigator.goTo(index: 0)
        XCTAssertEqual(navigator.currentIndex, 0)

        // Cannot jump forward.
        navigator.goTo(index: 2)
        XCTAssertEqual(navigator.currentIndex, 0)
    }

    @MainActor
    func testGoToNextRunsValidationOnce() async {
        let box = CallBox()
        let steps = [
            AnyAirlockStep(
                AirlockStep(id: "a", title: "A", icon: "circle") { Text("a") }
                    .validation {
                        box.count += 1
                        return true
                    }
            ),
            AnyAirlockStep(AirlockStep(id: "b", title: "B", icon: "circle") { Text("b") })
        ]
        let navigator = AirlockNavigator(appName: "Test", steps: steps)

        // Two rapid taps: the second must be rejected while validation is in flight.
        navigator.goToNext()
        navigator.goToNext()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(navigator.currentIndex, 1)
    }

    // MARK: - Checks

    @MainActor
    func testSetupCheckRunsToCompletion() async {
        let check = SetupCheck(taskNames: ["one", "two"], taskDuration: 0.01)
        let initiallyPassed = await check.validate()
        XCTAssertFalse(initiallyPassed)

        check.start()

        for _ in 0..<150 {
            if check.status == .success { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(check.status, .success)
        let passed = await check.validate()
        XCTAssertTrue(passed)
    }

    @MainActor
    func testWelcomeAutoAdvanceMarksSuccess() async {
        let check = WelcomeCheck(appName: "Test", autoAdvanceAfter: 0.05)
        let initiallyPassed = await check.validate()
        XCTAssertFalse(initiallyPassed)

        check.beginAutoAdvanceIfNeeded()
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(check.status, .success)
        let passed = await check.validate()
        XCTAssertTrue(passed)
    }

    @MainActor
    func testWelcomeWithoutAutoAdvanceRequiresAction() async {
        let check = WelcomeCheck(appName: "Test", autoAdvanceAfter: 0)
        check.beginAutoAdvanceIfNeeded() // no-op when auto-advance is disabled
        try? await Task.sleep(nanoseconds: 100_000_000)
        let passedBeforeAction = await check.validate()
        XCTAssertFalse(passedBeforeAction)

        check.performAction()
        let passedAfterAction = await check.validate()
        XCTAssertTrue(passedAfterAction)
        XCTAssertEqual(check.status, .success)
    }

    @MainActor
    func testAnyFlightCheckStatusIsSingleSourceOfTruth() {
        let underlying = AccessibilityCheck()
        let erased = AnyFlightCheck(underlying)

        XCTAssertEqual(erased.status, underlying.status)

        // Writes pass through to the wrapped check.
        erased.status = .success
        XCTAssertEqual(underlying.status, .success)

        // Reads reflect the wrapped check.
        underlying.status = .active
        XCTAssertEqual(erased.status, .active)
    }
}
