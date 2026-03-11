import XCTest
@testable import Airlock

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
}
