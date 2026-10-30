import AppKit
import Combine
import Testing
@testable import AirlockCore
@testable import AirlockChecks
@testable import AirlockUI

@Suite @MainActor
struct AirlockLifecycleTests {
    @Test(arguments: [NSSize(width: 540, height: 520), NSSize(width: 500, height: 480)])
    func selfTitledScreensUseTheBodyAndKeepFooterActionsTogether(size: NSSize) async throws {
        _ = NSApplication.shared
        let first = LifecycleStep(), second = LifecycleStep()
        let navigator = AirlockNavigator(appName: "Layout", steps: [
            AirlockStep(id: "first", title: "First") { first }.showsHeading(false),
            AirlockStep(id: "second", title: "Second") { second }.showsHeading(false)
        ])
        let flow = AirlockFlowController(navigator: navigator, playsIntro: false, playsSound: false)
        flow.view.frame = NSRect(origin: .zero, size: size)
        flow.viewDidAppear()
        navigator.goToNext()
        await flow.refreshTask?.value
        flow.view.layoutSubtreeIfNeeded()
        let buttons = descendants(NSButton.self, in: flow.view)
        let primary = try #require(buttons.first { $0.title == "Done" })
        let back = try #require(buttons.first { $0.title == "Back" })
        let primaryFrame = primary.convert(primary.bounds, to: flow.view)
        let backFrame = back.convert(back.bounds, to: flow.view)
        let bodyFrame = second.view.convert(second.view.bounds, to: flow.view)
        #expect(primary.controlSize == .large)
        #expect(back.controlSize == .large)
        #expect(!back.isHidden)
        #expect(abs(primaryFrame.maxX - (size.width - 24)) < 1)
        #expect(abs(primaryFrame.minY - 18) < 1)
        #expect(abs(backFrame.midY - primaryFrame.midY) < 1)
        #expect(abs(primaryFrame.minX - backFrame.maxX - 8) < 1)
        #expect(abs(bodyFrame.minX - 24) < 1)
        #expect(abs(bodyFrame.maxX - (size.width - 24)) < 1)
        #expect(abs(bodyFrame.maxY - (size.height - 28)) < 1)
        #expect(abs(bodyFrame.minY - primaryFrame.maxY - 18) < 1)
        #expect(!descendants(NSTextField.self, in: flow.view).contains { $0.stringValue == "Second" })
        flow.cancelPendingWork()
    }

    @Test func defaultScreensKeepTheirSharedHeading() throws {
        let step = LifecycleStep()
        let navigator = AirlockNavigator(appName: "Layout", steps: [
            AirlockStep(id: "first", title: "Shared heading") { step }
        ])
        let flow = AirlockFlowController(navigator: navigator, playsIntro: false, playsSound: false)
        flow.view.frame = NSRect(x: 0, y: 0, width: 540, height: 520)
        flow.viewDidAppear()
        flow.view.layoutSubtreeIfNeeded()
        let heading = try #require(descendants(NSTextField.self, in: flow.view).first { $0.stringValue == "Shared heading" })
        let titleFrame = heading.convert(heading.bounds, to: flow.view)
        let bodyFrame = step.view.convert(step.view.bounds, to: flow.view)
        #expect(titleFrame.minY >= bodyFrame.maxY + 20)
        flow.cancelPendingWork()
    }

    @Test func interruptedEntrancesKeepOnlyTheActiveControllerAndStopOnClose() async throws {
        _ = NSApplication.shared
        let first = LifecycleStep(), second = LifecycleStep()
        let navigator = AirlockNavigator(appName: "Motion", steps: [
            AirlockStep(id: "first", title: "First") { first },
            AirlockStep(id: "second", title: "Second") { second }
        ])
        let flow = AirlockFlowController(navigator: navigator, playsIntro: false, playsSound: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = flow
        window.orderFront(nil)
        defer { window.close() }
        flow.viewDidAppear()
        navigator.goToNext()
        await flow.refreshTask?.value
        #expect(first.view.superview == nil)
        #expect(first.navigator == nil)
        #expect(first.cancellations == 1)
        #expect(flow.children.count == 1)
        navigator.goToPrevious()
        await flow.refreshTask?.value
        #expect(second.view.superview == nil)
        #expect(second.navigator == nil)
        #expect(second.cancellations == 1)
        #expect(first.preparations == 2)
        #expect(flow.children.count == 1)
        let host = try #require(first.view.superview)
        #expect(host.layer?.animation(forKey: "Airlock.stepTransition") != nil)
        flow.cancelPendingWork()
        #expect(host.layer?.animation(forKey: "Airlock.stepTransition") == nil)
        #expect(first.navigator == nil)
    }

    @Test func queuedNavigationCannotStartAScreenAfterClosing() async throws {
        _ = NSApplication.shared
        let first = LifecycleStep(), second = LifecycleStep()
        let navigator = AirlockNavigator(appName: "Lifecycle", steps: [
            AirlockStep(id: "first", title: "First") { first },
            AirlockStep(id: "second", title: "Second") { second }
        ])
        let flow = AirlockFlowController(navigator: navigator, playsIntro: false, playsSound: false)
        _ = flow.view
        flow.viewDidAppear()
        #expect(first.preparations == 1)
        navigator.goToNext()
        let pendingRefresh = try #require(flow.refreshTask)
        flow.cancelPendingWork()
        await pendingRefresh.value
        #expect(second.preparations == 0)
        #expect(first.navigator == nil)
        flow.resume()
        #expect(second.preparations == 1)
        #expect(second.navigator === navigator)
        flow.cancelPendingWork()
    }

    @Test func offscreenControllersCannotReconfigureTheCurrentStep() async throws {
        let first = LifecycleStep(), second = LifecycleStep()
        let navigator = AirlockNavigator(appName: "Lifecycle", steps: [
            AirlockStep(id: "first", title: "First") { first },
            AirlockStep(id: "second", title: "Second") { second }
        ])
        let flow = AirlockFlowController(navigator: navigator, playsIntro: false, playsSound: false)
        _ = flow.view
        flow.viewDidAppear()
        navigator.goToNext()
        await flow.refreshTask?.value
        #expect(first.navigator == nil)
        first.navigator?.setContinueEnabled(false)
        #expect(navigator.canContinue)
        navigator.goToPrevious()
        await flow.refreshTask?.value
        #expect(first.navigator === navigator)
        #expect(second.navigator == nil)
        #expect(first.preparations == 2)
        flow.cancelPendingWork()
    }

    @Test func cancelledSetupFailureCannotOverwriteARetry() async throws {
        let gate = LifecycleGate<Void>()
        let check = SetupCheck(tasks: [.init(name: "Prepare") { try await gate.call() }])
        check.start()
        let old = try #require(check.setupTask)
        await gate.waitForCall(1)
        check.cancel()
        check.start()
        let current = try #require(check.setupTask)
        await gate.waitForCall(2)
        await gate.finish(1, result: .failure(CheckError(message: "retired attempt")))
        await old.value
        #expect(check.status == .checking)
        #expect(check.currentTaskName == "Prepare")
        #expect(check.progress == 0)
        await gate.finish(2, result: .success(()))
        await current.value
        #expect(check.status == .success)
        #expect(check.progress == 1)
    }

    @Test func staleLicenseReplyCannotApproveOrPersistANewerKey() async throws {
        let gate = LifecycleGate<LicenseActivationCheck.ValidationResult>()
        let storageKey = "AirlockLifecycleTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: storageKey) }
        let check = LicenseActivationCheck(storageKey: storageKey, validator: { _, _ in try await gate.call() },
                                           machineIDProvider: { "test-machine" })
        let old = Task { await check.submitLicenseKey("old-key") }
        await gate.waitForCall(1)
        let current = Task { await check.submitLicenseKey("new-key") }
        await gate.waitForCall(2)
        await gate.finish(2, result: .success(.init(isValid: false, failureMessage: "Rejected")))
        await current.value
        await gate.finish(1, result: .success(.init(isValid: true)))
        await old.value
        #expect(check.licenseKey == "new-key")
        #expect(check.status == .active)
        #expect(check.validationError == "Rejected")
        #expect(UserDefaults.standard.string(forKey: storageKey) == nil)
    }

    @Test func cancelledLicenseReplyCannotPersistAKey() async throws {
        let gate = LifecycleGate<LicenseActivationCheck.ValidationResult>()
        let storageKey = "AirlockLifecycleTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: storageKey) }
        let check = LicenseActivationCheck(storageKey: storageKey, validator: { _, _ in try await gate.call() },
                                           machineIDProvider: { "test-machine" })
        let task = Task { await check.submitLicenseKey("cancelled-key") }
        await gate.waitForCall(1)
        task.cancel()
        check.cancelPendingValidation()
        await gate.finish(1, result: .success(.init(isValid: true)))
        await task.value
        #expect(check.status == .active)
        #expect(check.validationError == nil)
        #expect(UserDefaults.standard.string(forKey: storageKey) == nil)
    }

    @Test func closingWelcomeCancelsItsCountdownAndAllowsAnotherVisit() async throws {
        let check = WelcomeCheck(appName: "Test", autoAdvanceAfter: 60)
        check.beginAutoAdvanceIfNeeded()
        let first = try #require(check.autoAdvanceTask)
        check.cancel()
        await first.value
        #expect(check.status != .success)
        #expect(check.autoAdvanceTask == nil)
        check.beginAutoAdvanceIfNeeded()
        let second = try #require(check.autoAdvanceTask)
        #expect(second != first)
        check.cancel()
        await second.value
    }

    @Test func managerCannotPublishValidationAfterStopping() async throws {
        let gate = LifecycleGate<Bool>()
        let check = LifecycleFlightCheck(gate: gate)
        let manager = AirlockManager(appName: "Test", checks: [check])
        manager.startValidation()
        let task = try #require(manager.validationTask)
        await gate.waitForCall(1)
        manager.stopValidation()
        await gate.finish(1, result: .success(true))
        await task.value
        #expect(check.status != .success)
        #expect(!manager.isComplete)
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants(type, in: $0) }
    }
}

@MainActor
private final class LifecycleStep: AirlockStepViewController {
    var preparations = 0
    var cancellations = 0
    override func loadView() { view = NSView() }
    override func prepareForPresentation() {
        preparations += 1
        super.prepareForPresentation()
    }
    override func cancelPendingWork() { cancellations += 1 }
}

private actor LifecycleGate<Value: Sendable> {
    private var count = 0
    private var pending: [Int: CheckedContinuation<Value, any Error>] = [:]
    private var waiting: [(Int, CheckedContinuation<Void, Never>)] = []
    func call() async throws -> Value {
        count += 1
        let index = count
        for (desired, waiter) in waiting where desired <= count { waiter.resume() }
        waiting.removeAll { $0.0 <= count }
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitForCall(_ desired: Int) async {
        if count < desired { await withCheckedContinuation { waiting.append((desired, $0)) } }
    }
    func finish(_ index: Int, result: Result<Value, any Error>) { pending.removeValue(forKey: index)?.resume(with: result) }
}

@MainActor
private final class LifecycleFlightCheck: FlightCheck {
    let id = UUID()
    let title = "Test"
    let description = "Test"
    let icon = "checkmark"
    @Published var status: CheckStatus = .pending
    let gate: LifecycleGate<Bool>
    init(gate: LifecycleGate<Bool>) { self.gate = gate }
    var detailView: NSViewController { NSViewController() }
    func performAction() {}
    func validate() async -> Bool { (try? await gate.call()) ?? false }
}
