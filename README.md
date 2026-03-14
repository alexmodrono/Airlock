# Airlock

![Airlock Demo](./demo.gif)

Airlock is a standalone Swift package for building first-class onboarding flows for macOS apps.

It gives you:

- A polished two-column onboarding container for SwiftUI
- A declarative step API for custom onboarding content
- A `FlightCheck` API for reusable preflight checks
- Reusable permission, feature, and status UI components
- Configurable built-in checks for permissions, setup, welcome screens, and license activation

Airlock is designed to be used outside this workspace. The package itself is product-agnostic; app-specific branding belongs in the host app's configuration.

## Requirements

- macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/alexmodrono/Airlock.git", from: "1.0.0")
]
```

Then add the product you need:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "Airlock"
    ]
)
```

### Available Products

- `Airlock`: umbrella import for most apps
- `AirlockCore`: state, models, step APIs
- `AirlockUI`: container views and reusable UI components
- `AirlockChecks`: configurable built-in checks

## Package Structure

```text
Airlock/
├── Sources/
│   ├── AirlockCore
│   ├── AirlockUI
│   ├── AirlockChecks
│   └── Airlock
├── Tests/
└── AirlockDemo/
```

## Quick Start

### Declarative API

Use the declarative API when your app already has custom onboarding views.

```swift
import SwiftUI
import Airlock

@main
struct MyApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @StateObject private var navigator = AirlockNavigator(
        appName: "MyApp",
        appIconName: "AppIcon"
    ) {
        AirlockStep(
            id: "welcome",
            title: "Welcome",
            icon: "hand.wave.fill",
            subtitle: "Get started with MyApp"
        ) {
            WelcomeStep()
        }

        AirlockStep(
            id: "permissions",
            title: "Permissions",
            icon: "lock.shield.fill",
            subtitle: "Grant the required access"
        ) {
            PermissionsStep()
        }

        AirlockStep(
            id: "ready",
            title: "Ready",
            icon: "checkmark.circle.fill",
            subtitle: "Finish onboarding"
        ) {
            ReadyStep()
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding && !navigator.isActive {
                ContentView()
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
                .onChange(of: navigator.isActive) { _, isActive in
                    if !isActive {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct WelcomeStep: View {
    var body: some View {
        VStack {
            Text("Welcome to MyApp")
        }
        .airlockEnableContinueAfter(seconds: 2)
    }
}

struct PermissionsStep: View {
    @Environment(\.airlockNavigator) private var navigator
    @StateObject private var checker = PermissionChecker(
        permissions: [.accessibility, .screenRecording]
    )

    var body: some View {
        PermissionsGroupView(
            permissions: [.accessibility, .screenRecording],
            permissionStates: checker.permissionStates
        )
        .onAppear {
            checker.startMonitoring(interval: 1.0)
            navigator?.setContinueEnabled(checker.allGranted)
        }
        .onDisappear {
            checker.stopMonitoring()
        }
        .onChange(of: checker.permissionStates) { _, _ in
            navigator?.setContinueEnabled(checker.allGranted)
        }
    }
}

struct ReadyStep: View {
    @Environment(\.airlockNavigator) private var navigator

    var body: some View {
        Text("You're all set.")
            .onAppear {
                navigator?.setContinueEnabled(true)
            }
    }
}
```

### FlightCheck API

Use the `FlightCheck` API when you want Airlock to drive validation and state for a reusable list of checks.

```swift
import SwiftUI
import Airlock

@main
struct MyApp: App {
    @StateObject private var manager = AirlockManager(
        appName: "MyApp",
        erasedChecks: [
            AnyFlightCheck(WelcomeCheck(
                appName: "MyApp",
                subtitle: "Let's get you ready."
            )),
            AnyFlightCheck(PermissionsCheck(
                permissions: [.accessibility, .screenRecording],
                title: "Permissions",
                description: "Grant the required system permissions."
            )),
            AnyFlightCheck(SetupCheck(
                taskNames: [
                    "Preparing workspace...",
                    "Loading configuration...",
                    "Finishing setup..."
                ]
            ))
        ]
    )

    var body: some Scene {
        WindowGroup {
            AirlockView(manager: manager)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

## Built-in Checks

### WelcomeCheck

`WelcomeCheck` is already configurable through its initializer.

```swift
let check = WelcomeCheck(
    appName: "MyApp",
    subtitle: "A fast setup with clear guidance.",
    features: [
        .init(icon: "sparkles", title: "Feature One", description: "Short explanation", color: .blue),
        .init(icon: "lock.shield", title: "Private", description: "Runs locally", color: .green)
    ],
    autoAdvanceAfter: 3.0
)
```

### AccessibilityCheck

`AccessibilityCheck` is generic by default and can be branded by the host app.

```swift
let check = AccessibilityCheck(
    configuration: .default(
        appName: "Flow",
        purpose: "track Finder windows and show contextual overlays",
        privacyNote: "Flow only observes the UI state it needs for overlays."
    )
)
```

### FullDiskAccessCheck

`FullDiskAccessCheck` supports branded copy and optional folder highlights.

```swift
let check = FullDiskAccessCheck(
    configuration: .default(
        appName: "Orbit",
        purpose: "watch folders and organize files in protected locations",
        folderHighlights: [
            .init(icon: "arrow.down.doc", name: "Downloads"),
            .init(icon: "doc.text", name: "Documents"),
            .init(icon: "display", name: "Desktop")
        ],
        foldersTitle: "Orbit will work with:"
    )
)
```

### PermissionsCheck

`PermissionsCheck` can validate standard permissions automatically and lets you override both detection and requesting when macOS cannot expose a reliable generic flow.

```swift
let check = PermissionsCheck(
    permissions: [.automation, .files],
    title: "Permissions",
    description: "Review the permissions used by MyApp."
) { permission in
    switch permission {
    case .automation:
        return hasAutomationAccessToFinder ? .granted : .notGranted
    case .files:
        return hasDownloadsFolderAccess ? .granted : .notGranted
    default:
        return permission.authorizationState
    }
} requestHandler: { permission in
    switch permission {
    case .automation:
        return await requestAutomationAccessToFinder()
    case .files:
        return await requestDownloadsFolderAccess()
    default:
        return await permission.requestAccess()
    }
}
```

### LicenseActivationCheck

`LicenseActivationCheck` is fully generic. Provide your own validation closure or build one on top of an HTTP endpoint.

```swift
let check = LicenseActivationCheck(
    storageKey: "com.example.myapp.license",
    configuration: .init(
        detailTitle: "Activate MyApp",
        detailDescription: "Enter your license key to unlock the full version.",
        purchasePrompt: "Need a license?",
        purchaseURL: URL(string: "https://example.com/purchase")
    )
) { licenseKey, machineID in
    let requestBody = try JSONEncoder().encode([
        "license_key": licenseKey,
        "machine_id": machineID
    ])

    let validator = LicenseActivationCheck.jsonEndpointValidator(
        endpoint: URL(string: "https://example.com/v1/licenses/validate")!,
        requestBody: { _, _ in requestBody }
    ) { data, response in
        if response.statusCode == 200 {
            return .init(isValid: true)
        }
        return .init(isValid: false, failureMessage: "License validation failed.")
    }

    return try await validator(licenseKey, machineID)
}
```

### SetupCheck

`SetupCheck` is a reusable progress-oriented check for async setup work.

```swift
let check = SetupCheck(
    tasks: [
        .init(name: "Preparing cache") {
            try await Task.sleep(for: .seconds(0.5))
        },
        .init(name: "Syncing defaults") {
            try await Task.sleep(for: .seconds(0.5))
        }
    ],
    title: "Setup",
    description: "Prepare the app for first launch."
)
```

## Permission Semantics

Airlock distinguishes between permissions it can verify and request generically and permissions that require app-specific behavior.

- `accessibility`, `fullDiskAccess`, `screenRecording`, `camera`, `microphone`, `contacts`, `calendars`, `reminders`, `photos`, and `locationServices` use best-effort automatic checks.
- `accessibility`, `screenRecording`, `camera`, `microphone`, `contacts`, `calendars`, `reminders`, `photos`, and `locationServices` can also show the system prompt directly from Airlock when macOS allows it.
- `fullDiskAccess` always requires a trip to System Settings.
- `automation` and `files` return `.requiresManualVerification(...)` by default because those permissions are target-specific or folder-specific on macOS.
- For app-specific permissions, pass both a custom `stateProvider` and a custom `requestHandler` to `PermissionChecker` or `PermissionsCheck`.

```swift
let checker = PermissionChecker(
    permissions: [.automation, .files]
) { permission in
    switch permission {
    case .automation:
        return hasAutomationAccessToFinder ? .granted : .notGranted
    case .files:
        return hasDownloadsFolderAccess ? .granted : .notGranted
    default:
        return permission.authorizationState
    }
} requestHandler: { permission in
    switch permission {
    case .automation:
        return await requestAutomationAccessToFinder()
    case .files:
        return await requestDownloadsFolderAccess()
    default:
        return await permission.requestAccess()
    }
}
```

## Reusable UI Components

Airlock UI components are public and can be used outside the main onboarding containers.

- `FeatureCard`, `FeatureGrid`, `FeatureRow`
- `PermissionsGroupView`, `PermissionRowView`, `PermissionChecker`
- `AirlockStepHeader`, `AirlockInfoCard`, `AirlockInlineContinueButton`
- `InfoBanner`, `ProgressBarView`, `InstructionStep`

## Demo App

`AirlockDemo/` contains a standalone sample app that demonstrates:

- A declarative onboarding flow
- Permission monitoring
- App-specific setup content
- A completion screen outside the onboarding container

Open `AirlockDemo/AirlockDemo.xcodeproj` to run it.

## Development

Run the package checks from the repository root:

```bash
swift build
swift test
```

## Release

Airlock uses semantic version tags for Swift Package Manager releases.

1. Merge the release-ready changes into `main`.
2. Update version references in the README if needed.
3. Create and push a release tag:

```bash
git tag 1.0.0
git push origin main
git push origin 1.0.0
```

See [RELEASING.md](RELEASING.md) for the full GitHub publishing checklist.

## Notes

- The license-validation URLs in the examples are placeholders. Replace them with your own API endpoints.
- `AirlockDemo/` is included as a local sample app and is not part of the Swift package products.

## License

Airlock is released under the MIT License. See [LICENSE](LICENSE).
