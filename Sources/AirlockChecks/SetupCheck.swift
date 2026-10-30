// SetupCheck.swift
// AirlockChecks
//
// A configurable setup check with progress indication.

import AppKit
import Combine
import AirlockCore
import AirlockUI

/// A flight check that displays a multi-step setup process with progress indication.
///
/// This check runs through a series of tasks, updating progress as each completes.
/// Use this for initialization, configuration, or any multi-step setup process.
///
/// Example:
/// ```swift
/// SetupCheck(
///     tasks: [
///         .init(name: "Initializing", action: { /* async work */ }),
///         .init(name: "Configuring", action: { /* async work */ }),
///         .init(name: "Finalizing", action: { /* async work */ })
///     ]
/// )
/// ```
@MainActor
public final class SetupCheck: FlightCheck, ObservableObject {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon: String
    public let actionLabel: String

    @Published public var status: CheckStatus = .pending
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var currentTaskName: String = "Waiting..."

    private let tasks: [SetupTask]
    private let stages: [String]
    private var hasStarted = false
    private(set) var setupTask: Task<Void, Never>?
    private var generation = UUID()

    /// A task to execute during setup.
    public struct SetupTask {
        public let name: String
        public let action: () async throws -> Void

        /// Creates a setup task.
        /// - Parameters:
        ///   - name: Display name for the task (shown during execution)
        ///   - action: Async action to perform
        public init(name: String, action: @escaping () async throws -> Void = {}) {
            self.name = name
            self.action = action
        }
    }

    /// Creates a setup check.
    /// - Parameters:
    ///   - tasks: Array of tasks to execute in order
    ///   - stages: Optional custom stage names for the progress display (defaults to task names)
    ///   - title: Check title in the sidebar (default: "Setup")
    ///   - description: Check description (default: "Configure your system")
    ///   - icon: SF Symbol for the check (default: "gearshape.fill")
    ///   - actionLabel: Action button label. Empty by default because setup
    ///     runs automatically when the check appears.
    public init(
        tasks: [SetupTask],
        stages: [String]? = nil,
        title: String = "Setup",
        description: String = "Configure your system",
        icon: String = "gearshape.fill",
        actionLabel: String = ""
    ) {
        self.tasks = tasks
        self.stages = stages ?? tasks.map { $0.name }
        self.title = title
        self.description = description
        self.icon = icon
        self.actionLabel = actionLabel
    }

    /// Creates a setup check with simulated tasks (for demos or simple delays).
    /// - Parameters:
    ///   - taskNames: Array of task names to display
    ///   - taskDuration: Duration for each task in seconds (default: 0.5)
    ///   - title: Check title in the sidebar
    ///   - description: Check description
    ///   - icon: SF Symbol for the check
    ///   - actionLabel: Action button label
    public convenience init(
        taskNames: [String],
        taskDuration: Double = 0.5,
        title: String = "Setup",
        description: String = "Configure your system",
        icon: String = "gearshape.fill",
        actionLabel: String = ""
    ) {
        let tasks = taskNames.map { name in
            SetupTask(name: name) {
                try await Task.sleep(for: .seconds(max(0, taskDuration)))
            }
        }
        self.init(
            tasks: tasks,
            title: title,
            description: description,
            icon: icon,
            actionLabel: actionLabel
        )
    }

    public var detailView: NSViewController {
        NativeCheckViewController(check: self)
    }

    /// Starts the setup work. Idempotent — safe to call more than once.
    ///
    /// The setup runs automatically when the check's detail view appears, so
    /// it progresses without the user having to find an action button. Calling
    /// ``performAction()`` is equivalent.
    @MainActor
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        generation = UUID()
        let attempt = generation
        progress = 0
        status = .checking
        setupTask = Task { [weak self] in await self?.runSetup(generation: attempt) }
    }

    public func performAction() {
        start()
    }

    @MainActor
    public func validate() async -> Bool {
        return progress >= 1.0
    }

    public func cancel() {
        generation = UUID()
        setupTask?.cancel()
        setupTask = nil
        if status != .success { hasStarted = false }
    }

    @MainActor
    private func runSetup(generation attempt: UUID) async {
        for (index, task) in tasks.enumerated() {
            guard !Task.isCancelled, generation == attempt else { return }
            currentTaskName = task.name
            do {
                try await task.action()
                try Task.checkCancellation()
                guard generation == attempt else { return }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, generation == attempt else { return }
                currentTaskName = error.localizedDescription
                status = .failed(CheckError(message: error.localizedDescription))
                hasStarted = false
                return
            }
            progress = Double(index + 1) / Double(tasks.count)
        }
        guard !Task.isCancelled, generation == attempt else { return }
        progress = 1
        currentTaskName = "Complete"
        status = .success
    }

    // Internal accessors for the detail view
    var setupStages: [String] { stages }
}
