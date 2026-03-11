// AirlockDemoApp.swift
// AirlockDemo
//
// A demonstration app showcasing the Airlock onboarding library.
// This uses the new declarative API with AirlockFlowView and AirlockNavigator.

import SwiftUI
import Airlock

@main
struct AirlockDemoApp: App {
    // Using the new declarative navigator
    @StateObject private var navigator = AirlockNavigator(
        appName: "Cosmos",
        appIconName: nil,
        steps: createDemoSteps()
    )

    var body: some Scene {
        WindowGroup {
            Group {
                if !navigator.isActive {
                    // Show the main app after onboarding is complete
                    MainAppView {
                        // Reset onboarding to show it again
                        navigator.reset()
                    }
                } else {
                    // Show onboarding flow
                    AirlockFlowView(
                        navigator: navigator,
                        configuration: AirlockConfiguration(
                            showIntro: true,
                            introDuration: 2.5,
                            playIntroSound: true,
                            allowSkipIntro: true
                        )
                    )
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - Main App View (shown after onboarding)

struct MainAppView: View {
    let onResetOnboarding: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.08, green: 0.08, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 24) {
                // Success header with animated icon
                VStack(spacing: 16) {
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

                    Text("Welcome to Cosmos")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text("All systems operational. You're ready to explore.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer().frame(height: 8)

                // Success banner using InfoBanner
                InfoBanner(
                    message: "Pre-flight checks completed successfully. All systems are go.",
                    style: .success
                )
                .padding(.horizontal, 40)
                .opacity(appeared ? 1.0 : 0)

                Spacer().frame(height: 8)

                // Stats using FeatureGrid
                FeatureGrid(
                    features: [
                        .init(
                            icon: "checkmark.circle.fill",
                            title: "4 Checks Passed",
                            description: "All flight checks validated",
                            color: .green
                        ),
                        .init(
                            icon: "bolt.fill",
                            title: "100% Ready",
                            description: "System fully operational",
                            color: .orange
                        ),
                        .init(
                            icon: "shield.fill",
                            title: "Secure",
                            description: "Permissions configured",
                            color: .blue
                        ),
                        .init(
                            icon: "cpu.fill",
                            title: "Connected",
                            description: "Backend services active",
                            color: .purple
                        )
                    ],
                    columns: 2
                )
                .padding(.horizontal, 40)
                .opacity(appeared ? 1.0 : 0)

                Spacer().frame(height: 16)

                // Progress bar showing completion
                ProgressBarView(
                    progress: 1.0,
                    label: "System Readiness",
                    showPercentage: true,
                    gradientColors: [.green, .cyan]
                )
                .padding(.horizontal, 40)
                .opacity(appeared ? 1.0 : 0)

                Spacer().frame(height: 24)

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        onResetOnboarding()
                    } label: {
                        Label("Show Onboarding Again", systemImage: "arrow.counterclockwise")
                            .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit Demo", systemImage: "xmark.circle")
                            .frame(width: 120)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .opacity(appeared ? 1.0 : 0)
            }
            .padding(40)
        }
        .frame(width: 600, height: 580)
        .background(WindowAccessorMain())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appeared = true
            }
            NSSound(named: "Glass")?.play()
        }
    }
}

// Window configuration for main view
struct WindowAccessorMain: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.center()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
