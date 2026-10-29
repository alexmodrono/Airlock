import AppKit
import Combine
import Testing
@testable import Airlock

@Suite @MainActor
struct AirlockTests {
    private func navigator(_ count: Int = 3) -> AirlockNavigator {
        AirlockNavigator(appName: "Test", steps: (0..<count).map { index in
            AirlockStep(id: String(index), title: "Step \(index)") { NSViewController() }
        })
    }

    @Test func disabledStepsCannotAdvance() {
        let nav = navigator()
        nav.goToNext()
        #expect(nav.currentIndex == 0)
        nav.setContinueEnabled(true)
        nav.goToNext()
        #expect(nav.currentIndex == 1)
        #expect(!nav.canContinue)
    }

    @Test func completionRunsOnce() {
        let nav = navigator(1)
        var count = 0
        nav.onComplete = { count += 1 }
        nav.setContinueEnabled(true)
        nav.goToNext()
        nav.goToNext()
        #expect(count == 1)
        #expect(nav.isComplete)
    }

    @Test func backNavigationRespectsStepPolicy() {
        let nav = AirlockNavigator(appName: "Test", steps: [
            AirlockStep(id: "a", title: "A") { NSViewController() },
            AirlockStep(id: "b", title: "B") { NSViewController() }.allowsGoingBack(false)
        ])
        nav.setContinueEnabled(true)
        nav.goToNext()
        nav.goToPrevious()
        #expect(nav.currentIndex == 1)
        #expect(!nav.canGoBack)
    }

    @Test func emptyFlowDoesNotAdvance() {
        let nav = navigator(0)
        nav.setContinueEnabled(true)
        nav.goToNext()
        #expect(nav.currentStep == nil)
        #expect(!nav.isComplete)
    }

    @Test func builderSupportsConditionalSteps() {
        let nav = AirlockNavigator(appName: "Test") {
            AirlockStep(id: "start", title: "Start") { NSViewController() }
            for index in 0..<2 {
                AirlockStep(id: "loop-\(index)", title: "Loop") { NSViewController() }
            }
        }
        #expect(nav.steps.map(\.id) == ["start", "loop-0", "loop-1"])
    }

    @Test func validationCannotAdvanceAfterReset() async {
        let events = AsyncStream<Void>.makeStream()
        var continuation: CheckedContinuation<Bool, Never>?
        let step = AirlockStep(id: "a", title: "A") { NSViewController() }.validation {
            events.continuation.yield(())
            return await withCheckedContinuation { continuation = $0 }
        }
        let nav = AirlockNavigator(appName: "Test", steps: [step,
            AirlockStep(id: "b", title: "B") { NSViewController() }])
        nav.setContinueEnabled(true)
        nav.goToNext()
        var iterator = events.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(nav.isBusy)
        nav.reset()
        continuation?.resume(returning: true)
        await Task.yield()
        #expect(nav.currentIndex == 0)
        #expect(!nav.isBusy)
        #expect(!nav.isComplete)
    }

    @Test func nativeWindowUsesRegularWindowLevel() {
        _ = NSApplication.shared
        let controller = AirlockWindowController(navigator: navigator(), playsIntro: false, playsSound: false)
        #expect(controller.window?.level == .normal)
        #expect(controller.window?.styleMask.contains(.titled) == false)
        #expect(controller.window?.canBecomeKey == true)
        #expect(controller.window?.isOpaque == false)
        #expect(controller.window?.collectionBehavior.contains(.fullScreenPrimary) == false)
    }

    @Test func permissionChecksUseInjectedState() async {
        let check = PermissionsCheck(permissions: [.automation, .files], stateProvider: {
            $0 == .automation ? .granted : .notGranted
        })
        #expect(!(await check.validate()))
        #expect(check.currentlyGranted == [.automation])
    }

    @Test func erasedCheckSharesStatus() {
        let check = AccessibilityCheck()
        let erased = AnyFlightCheck(check)
        erased.status = .success
        #expect(check.status == .success)
        check.status = .active
        #expect(erased.status == .active)
    }

    @Test func licenseValidationRequiresExplicitSubmission() async {
        let check = LicenseActivationCheck(validator: { key, _ in .init(isValid: key == "valid") }, machineIDProvider: { "test" })
        check.licenseKey = "valid"
        #expect(!(await check.validate()))
        await check.submitLicenseKey("valid")
        #expect(await check.validate())
    }

    @Test func failedSetupDoesNotReportSuccess() async {
        let failures = AsyncStream<Bool>.makeStream()
        let check = SetupCheck(tasks: [.init(name: "Prepare") { throw CheckError(message: "Cannot prepare files") }])
        let token = check.$status.sink { status in
            if case .failed = status { failures.continuation.yield(true); failures.continuation.finish() }
        }
        defer { token.cancel() }
        check.start()
        var iterator = failures.stream.makeAsyncIterator()
        #expect(await iterator.next() == true)
        #expect(!(await check.validate()))
        #expect(check.progress == 0)
        check.cancel()
    }
}
