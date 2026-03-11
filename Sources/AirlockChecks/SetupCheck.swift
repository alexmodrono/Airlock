// SetupCheck.swift
// AirlockChecks
//
// A configurable setup check with progress indication.

import SwiftUI
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
    ///   - actionLabel: Action button label (default: "Configure")
    public init(
        tasks: [SetupTask],
        stages: [String]? = nil,
        title: String = "Setup",
        description: String = "Configure your system",
        icon: String = "gearshape.fill",
        actionLabel: String = "Configure"
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
        actionLabel: String = "Configure"
    ) {
        let tasks = taskNames.map { name in
            SetupTask(name: name) {
                try? await Task.sleep(nanoseconds: UInt64(taskDuration * 1_000_000_000))
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

    public var detailView: AnyView {
        AnyView(SetupCheckDetailView(check: self))
    }

    public func performAction() {
        guard !hasStarted else { return }
        hasStarted = true

        Task { @MainActor in
            status = .checking
            await runSetup()
        }
    }

    @MainActor
    public func validate() async -> Bool {
        return progress >= 1.0
    }

    @MainActor
    private func runSetup() async {
        guard !tasks.isEmpty else {
            progress = 1.0
            currentTaskName = "Complete!"
            status = .success
            return
        }

        for (index, task) in tasks.enumerated() {
            currentTaskName = task.name

            // Run the task
            do {
                try await task.action()
            } catch {
                // Continue even if a task fails
            }

            // Update progress with smooth animation
            let targetProgress = Double(index + 1) / Double(tasks.count)
            let steps = 10
            for step in 1...steps {
                progress = Double(index) / Double(tasks.count) + (targetProgress - Double(index) / Double(tasks.count)) * Double(step) / Double(steps)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            progress = targetProgress
        }

        currentTaskName = "Complete!"
        status = .success
    }

    // Internal accessors for the detail view
    var setupStages: [String] { stages }
}

// MARK: - Detail View

struct SetupCheckDetailView: View {
    @ObservedObject var check: SetupCheck

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CheckDetailView(
            icon: check.icon,
            title: check.title,
            description: check.description,
            status: check.status
        ) {
            VStack(spacing: 20) {
                // Progress bar
                ProgressBarView(
                    progress: check.progress,
                    label: check.currentTaskName
                )
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
                )

                // Setup stages
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(check.setupStages.enumerated()), id: \.offset) { index, stage in
                        let stageProgress = Double(index + 1) / Double(check.setupStages.count)
                        SetupStage(
                            name: stage,
                            isComplete: check.progress >= stageProgress
                        )
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
        }
    }
}
