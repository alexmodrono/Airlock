// DemoSteps.swift
// AirlockDemo
//
// Demo steps using the declarative Airlock API.

import SwiftUI
import Airlock

// MARK: - Welcome Step Content

struct WelcomeStepContent: View {
    private let features = [
        (icon: "checkmark.shield.fill", title: "Gatekeeper Pattern", description: "Ensure onboarding requirements are met before app access.", color: Color.green),
        (icon: "rectangle.split.2x1.fill", title: "Contextual Help", description: "Keep progress and detailed guidance side by side.", color: Color.blue),
        (icon: "paintbrush.fill", title: "Native Design", description: "Use SwiftUI, materials, and polished motion on macOS.", color: Color.orange),
        (icon: "gearshape.2.fill", title: "Configurable", description: "Mix reusable checks with custom onboarding content.", color: Color.purple)
    ]

    private let highlightFeatures: [AnimatedFeatureHighlight.Feature] = [
        .init(icon: "checkmark.shield.fill", title: "Structured Onboarding", color: .green),
        .init(icon: "rectangle.split.2x1.fill", title: "Contextual Detail", color: .blue),
        .init(icon: "paintbrush.fill", title: "Native macOS UI", color: .orange),
        .init(icon: "gearshape.2.fill", title: "Customizable Flows", color: .purple)
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 24)

            AnimatedFeatureHighlight(features: highlightFeatures)

            VStack(spacing: 8) {
                Text("Welcome to Airlock")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This demo shows how Airlock can drive a polished onboarding flow for any macOS app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 10) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                    FeatureCard(
                        icon: feature.icon,
                        title: feature.title,
                        description: feature.description,
                        accentColor: feature.color
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)
        }
        .airlockEnableContinueAfter(seconds: 2)
    }
}

// MARK: - Permissions Step Content

struct PermissionsStepContent: View {
    @Environment(\.airlockNavigator) private var navigator
    @StateObject private var checker = PermissionChecker(
        permissions: [.accessibility, .screenRecording]
    )
    @State private var skipped = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)

            AirlockStepHeader(
                icon: checker.allGranted ? "checkmark.shield.fill" : "lock.shield.fill",
                title: checker.allGranted ? "Permissions Granted" : "Permissions",
                subtitle: checker.allGranted
                    ? "All permissions are configured. You can continue."
                    : "Grant the sample permissions used in this demo.",
                iconColor: checker.allGranted ? .green : .blue
            )

            AirlockInfoCard(
                icon: "lock.shield.fill",
                title: "Demo Note",
                description: "This step uses Airlock's **PermissionChecker** to monitor and request system permissions. Each row calls `PermissionType.requestAccess()` which triggers the real macOS system prompt.",
                color: .blue
            )
            .padding(.horizontal, 24)

            PermissionsGroupView(
                title: "Sample Permissions",
                permissions: [.accessibility, .screenRecording],
                permissionStates: checker.permissionStates
            ) { permission in
                Task {
                    await checker.requestAccess(for: permission)
                }
            }
            .padding(.horizontal, 24)

            if !checker.allGranted && !skipped {
                Button {
                    skipped = true
                    navigator?.setContinueEnabled(true)
                } label: {
                    Text("Skip permissions for this demo")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }

            Spacer()
        }
        .onAppear {
            checker.startMonitoring(interval: 1.0)
            navigator?.setContinueEnabled(checker.allGranted || skipped)
        }
        .onDisappear {
            checker.stopMonitoring()
        }
        .onChange(of: checker.permissionStates) { _, _ in
            navigator?.setContinueEnabled(checker.allGranted || skipped)
        }
    }
}

// MARK: - License Step Content

struct LicenseStepContent: View {
    @Environment(\.airlockNavigator) private var navigator

    @State private var licenseKey: String = ""
    @State private var validationState: ValidationState = .idle
    @State private var errorMessage: String?

    enum ValidationState {
        case idle
        case validating
        case valid
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)

            AirlockStepHeader(
                icon: validationState == .valid ? "checkmark.circle.fill" : "key.fill",
                title: validationState == .valid ? "License Activated" : "Activate License",
                subtitle: validationState == .valid
                    ? "Your license has been verified."
                    : "Enter a license key to unlock the full experience.",
                iconColor: validationState == .valid ? .green : .orange
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("License Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)

                HStack(spacing: 12) {
                    TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    errorMessage != nil ? Color.red.opacity(0.5) : Color.primary.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                        .disabled(validationState == .valid)
                }

                if let error = errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 40)

            AirlockInfoCard(
                icon: "info.circle.fill",
                title: "Demo Tip",
                description: "Type **demo** to simulate a successful activation, or anything else to see the error state. This step uses the **button API** to run validation on tap.",
                color: .purple
            )
            .padding(.horizontal, 24)

            Spacer()
        }
        .onAppear {
            configureButton()
        }
        .onChange(of: licenseKey) { _, _ in
            if validationState == .valid { return }
            errorMessage = nil
            configureButton()
        }
    }

    private func configureButton() {
        guard validationState != .valid else { return }

        if licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            navigator?.setButtonLabel("Activate", icon: "key.fill")
            navigator?.setContinueEnabled(false)
        } else {
            navigator?.setButtonAction(label: "Activate", icon: "key.fill") {
                await validateLicense()
            }
            navigator?.setContinueEnabled(true)
        }
    }

    @MainActor
    private func validateLicense() async {
        validationState = .validating
        errorMessage = nil

        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "demo" {
            validationState = .valid
            navigator?.resetButton()
            navigator?.setContinueEnabled(true)
        } else {
            validationState = .idle
            errorMessage = "Invalid license key. Try \"demo\" for this example."
            configureButton()
        }
    }
}

// MARK: - Service Step Content

struct ServiceStepContent: View {
    @Environment(\.airlockNavigator) private var navigator

    @State private var serviceState: ServiceState = .checking

    enum ServiceState {
        case checking
        case unavailable
        case starting
        case ready
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)

            AirlockStepHeader(
                icon: headerIcon,
                title: headerTitle,
                subtitle: headerSubtitle,
                iconColor: headerColor
            )

            statusBanner
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                FeatureRow(icon: "server.rack", text: "Connect to a local helper process", iconColor: .blue)
                FeatureRow(icon: "arrow.clockwise.circle", text: "Retry service initialization if needed", iconColor: .orange)
                FeatureRow(icon: "bolt.shield", text: "Keep setup local to the Mac", iconColor: .green)
            }
            .padding(.horizontal, 24)

            if serviceState == .unavailable {
                AirlockCapabilityChips([
                    (icon: "server.rack", label: "Local Service", color: .blue),
                    (icon: "network", label: "No Network Required", color: .green),
                    (icon: "lock.fill", label: "Sandboxed", color: .purple),
                    (icon: "bolt.fill", label: "Fast Startup", color: .orange)
                ])
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .onAppear {
            navigator?.setContinueEnabled(serviceState == .ready)
            configureButtonForState()
            if serviceState == .checking {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if serviceState == .checking {
                        serviceState = .unavailable
                    }
                }
            }
        }
        .onChange(of: serviceState) { _, newValue in
            navigator?.setContinueEnabled(newValue == .ready)
            configureButtonForState()
        }
    }

    private func configureButtonForState() {
        switch serviceState {
        case .checking:
            navigator?.setButtonLabel("Checking...", icon: "arrow.triangle.2.circlepath")
            navigator?.setContinueEnabled(false)
        case .unavailable:
            navigator?.setButtonAction(label: "Start Service", icon: "play.fill") {
                await startService()
            }
            navigator?.setContinueEnabled(true)
        case .starting:
            navigator?.setButtonLabel("Starting...", icon: "arrow.triangle.2.circlepath")
            navigator?.setContinueEnabled(false)
        case .ready:
            navigator?.resetButton()
            navigator?.setContinueEnabled(true)
        }
    }

    @MainActor
    private func startService() async {
        serviceState = .starting
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        serviceState = .ready
    }

    private var headerIcon: String {
        switch serviceState {
        case .checking: return "server.rack"
        case .unavailable: return "exclamationmark.triangle.fill"
        case .starting: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle.fill"
        }
    }

    private var headerTitle: String {
        switch serviceState {
        case .checking: return "Checking Local Service"
        case .unavailable: return "Local Service Required"
        case .starting: return "Starting Local Service"
        case .ready: return "Service Ready"
        }
    }

    private var headerSubtitle: String {
        switch serviceState {
        case .checking:
            return "Simulating a dependency check."
        case .unavailable:
            return "This demo step represents any app-specific setup task."
        case .starting:
            return "Launching the local helper process."
        case .ready:
            return "The local helper is ready."
        }
    }

    private var headerColor: Color {
        switch serviceState {
        case .checking: return .blue
        case .unavailable: return .orange
        case .starting: return .purple
        case .ready: return .green
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch serviceState {
        case .checking:
            InfoBanner(message: "Checking for a local dependency...", style: .info)
        case .unavailable:
            InfoBanner(message: "The local helper is not running yet. Use the sidebar button to start it.", style: .warning)
        case .starting:
            ProgressBarView(progress: 0.55, label: "Starting local service...", showPercentage: false)
        case .ready:
            InfoBanner(message: "Local service is connected and ready.", style: .success)
        }
    }
}

// MARK: - Ready Step Content

struct ReadyStepContent: View {
    @Environment(\.airlockNavigator) private var navigator
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
            }
            .scaleEffect(appeared ? 1.0 : 0.8)
            .opacity(appeared ? 1.0 : 0)

            VStack(spacing: 8) {
                Text("Ready to Launch")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Everything is configured and ready.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            AirlockProgressSteps([
                (text: "Welcome tour completed", isDone: true),
                (text: "System permissions granted", isDone: true),
                (text: "License activated", isDone: true),
                (text: "Local service started", isDone: true)
            ])
            .padding(.horizontal, 40)
            .opacity(appeared ? 1.0 : 0)

            FeatureGrid(
                features: [
                    .init(icon: "checkmark.circle.fill", title: "Guided Steps", description: "Move through onboarding in order", color: .green),
                    .init(icon: "sidebar.left", title: "Persistent Context", description: "Keep progress visible in the sidebar", color: .blue),
                    .init(icon: "slider.horizontal.3", title: "Configurable", description: "Mix built-in and app-specific content", color: .purple),
                    .init(icon: "sparkles", title: "Polished", description: "Use intro animation, sound, and motion", color: .orange)
                ],
                columns: 2
            )
            .padding(.horizontal, 24)
            .opacity(appeared ? 1.0 : 0)

            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appeared = true
            }
            navigator?.setContinueEnabled(true)
            navigator?.setButtonLabel("Get Started", icon: "arrow.right.circle.fill")
        }
    }
}

// MARK: - Demo Step Factory

func createDemoSteps() -> [AnyAirlockStep] {
    [
        AnyAirlockStep(AirlockStep(
            id: "welcome",
            title: "Welcome",
            icon: "hand.wave.fill",
            subtitle: "Explore the Airlock flow"
        ) {
            WelcomeStepContent()
        }),

        AnyAirlockStep(AirlockStep(
            id: "permissions",
            title: "Permissions",
            icon: "lock.shield.fill",
            subtitle: "Grant sample system permissions"
        ) {
            PermissionsStepContent()
        }),

        AnyAirlockStep(AirlockStep(
            id: "license",
            title: "License",
            icon: "key.fill",
            subtitle: "Activate a demo license"
        ) {
            LicenseStepContent()
        }),

        AnyAirlockStep(AirlockStep(
            id: "service",
            title: "Service",
            icon: "server.rack",
            subtitle: "Connect a local dependency"
        ) {
            ServiceStepContent()
        }),

        AnyAirlockStep(AirlockStep(
            id: "ready",
            title: "Ready",
            icon: "checkmark.circle.fill",
            subtitle: "Finish the demo flow"
        ) {
            ReadyStepContent()
        })
    ]
}
