import Combine
import Foundation

public enum AirlockStepStatus: Equatable, Sendable {
    case pending, current, completed
}

@MainActor
public final class AirlockNavigator: ObservableObject {
    public let steps: [AirlockStep]
    public let appName: String
    @Published public private(set) var currentIndex = 0
    @Published public private(set) var canContinue = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var isComplete = false
    @Published public private(set) var buttonLabel: String?
    public var onComplete: (@MainActor () -> Void)?

    private var action: (@MainActor () async -> Void)?
    private var operation: Task<Void, Never>?
    private var generation = UUID()

    public init(appName: String, steps: [AirlockStep]) {
        precondition(Set(steps.map(\.id)).count == steps.count, "Onboarding step IDs must be unique")
        self.appName = appName
        self.steps = steps
    }

    public convenience init(appName: String, @AirlockStepBuilder steps: () -> [AirlockStep]) {
        self.init(appName: appName, steps: steps())
    }

    deinit { operation?.cancel() }

    public var currentStep: AirlockStep? { steps.indices.contains(currentIndex) ? steps[currentIndex] : nil }
    public var isLastStep: Bool { !steps.isEmpty && currentIndex == steps.count - 1 }
    public var canGoBack: Bool { canGoTo(index: currentIndex - 1) }
    public var progress: Double { steps.count > 1 ? Double(currentIndex) / Double(steps.count - 1) : 1 }

    public func setContinueEnabled(_ enabled: Bool) { canContinue = enabled }

    public func setButtonAction(label: String, action: @escaping @MainActor () async -> Void) {
        buttonLabel = label
        self.action = action
    }

    public func setButtonLabel(_ label: String) {
        buttonLabel = label
        action = nil
    }

    public func resetButton() {
        buttonLabel = nil
        action = nil
    }

    public func goToNext() {
        guard canContinue, !isBusy, !isComplete, let step = currentStep else { return }
        let currentGeneration = generation
        if let action {
            isBusy = true
            operation = Task { [weak self] in
                await action()
                guard let self, !Task.isCancelled, self.generation == currentGeneration else { return }
                self.isBusy = false
                self.operation = nil
            }
        } else if let validate = step.validation {
            isBusy = true
            operation = Task { [weak self] in
                let passed = await validate()
                guard let self, !Task.isCancelled, self.generation == currentGeneration else { return }
                self.isBusy = false
                self.operation = nil
                if passed { self.advance() }
            }
        } else {
            advance()
        }
    }

    public func goToPrevious() { goTo(index: currentIndex - 1) }

    /// Whether a navigation control may select this step without bypassing
    /// validation or crossing a completed setup checkpoint.
    public func canGoTo(index: Int) -> Bool {
        guard !isBusy, !isComplete, steps.indices.contains(index), index <= currentIndex else { return false }
        if index == currentIndex { return true }
        return steps[(index + 1)...currentIndex].allSatisfy(\.allowsGoingBack)
    }

    public func goTo(index: Int) {
        guard index != currentIndex, canGoTo(index: index) else { return }
        currentIndex = index
        canContinue = false
        resetButton()
    }

    public func status(at index: Int) -> AirlockStepStatus {
        if index < currentIndex || isComplete { return .completed }
        return index == currentIndex ? .current : .pending
    }

    public func cancelPendingAction() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        isBusy = false
    }

    public func reset() {
        cancelPendingAction()
        currentIndex = 0
        isComplete = false
        canContinue = false
        resetButton()
    }

    private func advance() {
        if isLastStep {
            isComplete = true
            onComplete?()
        } else {
            canContinue = false
            resetButton()
            currentIndex += 1
        }
    }
}
