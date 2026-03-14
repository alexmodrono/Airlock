// AirlockDemoApp.swift
// AirlockDemo
//
// A demonstration app showcasing the Airlock onboarding library.
// This uses the declarative API with AirlockFlowView and AirlockNavigator.

import SwiftUI
import Airlock

@main
struct AirlockDemoApp: App {
    @StateObject private var navigator = AirlockNavigator(
        appName: "Airlock Demo",
        appIconName: nil,
        steps: createDemoSteps()
    )

    var body: some Scene {
        WindowGroup {
            Group {
                if !navigator.isActive {
                    MainAppView {
                        navigator.reset()
                    }
                } else {
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
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 88, height: 88)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                }
                .scaleEffect(appeared ? 1.0 : 0.85)
                .opacity(appeared ? 1.0 : 0)

                VStack(spacing: 6) {
                    Text("Onboarding Complete")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("The Airlock demo has finished. Your app would start here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1.0 : 0)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onResetOnboarding()
                } label: {
                    Text("Run Onboarding Again")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
            .opacity(appeared ? 1.0 : 0)
        }
        .frame(width: 360, height: 340)
        .background(.ultraThinMaterial)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}
