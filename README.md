# Airlock

Native AppKit onboarding for macOS. A compact, borderless setup window with glass step navigation,
asynchronous validation, and the original hello animation and startup sound.

This branch, `feat/appkit-onboarding`, replaces the SwiftUI presentation API.
It requires Xcode 26 or later (Swift 6.2 and the macOS 26 SDK) to build and supports macOS 14 or later at runtime.

## Presentation

`AirlockWindowController.present()` brings the onboarding app forward. It does
not hide, close, or terminate other applications, dim the desktop, or change
system presentation options. The content window is solid and defaults to 540 × 520 points, with no title bar or traffic-light
buttons. Drag its background to move it, resize its edges, and use Command-W to
close it. Command-Option-1 through 9 selects an available setup step.

The main content opens at the exact geometric center of its screen. A soft
rainbow rim restores the original SwiftUI palette, blur, and opacity without
making the content translucent. It rotates during the intro and fades out when
the intro finishes or is skipped. Reduce Motion keeps it static and removes it
immediately at completion. Its separate background window ignores mouse events,
so transparent margins do not block other apps. The startup sound plays once,
continuing to its end after the visual intro. Closing setup stops the sound.

A separate glass pill above the content contains native segmented step controls.
It moves with the main window, stays on screen when resized, and closes with it.
Steps that would skip validation or cross a completed checkpoint remain disabled.
The intro can be skipped; Reduce Motion displays its final frame.

The layout follows Crono's compact onboarding: generous content above a footer
with large Back and Continue buttons together on the right. Pages enter with a
24-point directional fade; Reduce Motion uses a short opacity transition. The
previous screen is removed immediately, so its fields cannot remain active or
be captured in a transition snapshot.

The navigation pill uses AppKit's NSGlassEffectView on macOS 26 and later, with a visual
effect fallback on macOS 14–15 and an opaque surface when Reduce Transparency is
enabled. See [Apple's glass view documentation](https://developer.apple.com/documentation/appkit/nsglasseffectview).

## Usage

Add the `Airlock` product to your macOS app. Create steps from AppKit view
controllers and retain the window controller for the duration of setup:

```swift
import AppKit
import Airlock

@MainActor
final class WelcomeController: AirlockStepViewController {
    override func loadView() {
        view = NSTextField(wrappingLabelWithString: "Choose your preferences to get started.")
    }

    override func prepareForPresentation() {
        navigator?.setContinueEnabled(true)
    }
}

@MainActor
func makeOnboarding() -> AirlockWindowController {
    let navigator = AirlockNavigator(appName: "My App") {
        AirlockStep(id: "welcome", title: "Welcome") { WelcomeController() }
    }
    let window = AirlockWindowController(navigator: navigator)
    navigator.onComplete = { [weak window] in window?.close() }
    return window
}
```

Call `present()` from your app delegate after retaining the result. Step view controllers are created lazily and retained while navigating between steps.
`prepareForPresentation()` runs on each visit; `cancelPendingWork()` runs when
leaving the screen or closing the window. The shared `navigator` is available
only while the controller is presented, so a hidden screen cannot change another
screen's navigation controls. Asynchronous screen work must still cooperate with
cancellation before publishing its own results.

Use `.showsHeading(false)` for a screen with its own centered welcome title or
form header. Its body then fills the space between the 28-point top inset and
the shared footer, with 24-point horizontal insets. The navigation pill still
uses the step's title. Shared headings remain enabled by default for existing
controllers and checks.

## Validation

Use `navigator.setButtonAction(label:action:)` for sign-in or other asynchronous
work that should keep the user on the current screen. On success, reset the
button and enable Continue. Use `.validation { ... }` on a step for a predicate
that must succeed before navigation. Disabled steps cannot advance, concurrent
button actions are rejected, and resetting or closing cancels pending work.

`allowsGoingBack(false)` prevents navigation back across a completed checkpoint.
All UI and navigation state is isolated to the main actor.

## Checks

The `AirlockChecks` product retains configurable Accessibility, Full Disk Access,
permission, license, welcome, and setup checks. Their `detailView` is now an
`NSViewController`; their validation and status models remain available.
`NativeCheckViewController` adapts them to the shared navigation controls.
Custom screens can also use `PermissionType` and `PermissionChecker` directly.

The package does not grant capabilities to the host app. Supply the appropriate
usage descriptions and entitlements, and request permission only when the user
chooses the corresponding feature. Accessibility-based cross-app observation
requires an unsandboxed host.

## Build and test

```sh
swift test --configuration debug --force-resolved-versions
swift test --configuration release --force-resolved-versions
swift run AirlockDemo
```

CI selects Xcode 26.6 on `macos-26`, tests both configurations, and builds the
unsigned Xcode demo. The package and demo lockfiles retain the reviewed Lottie
revision; update and validate both together.

The demo uses an AppKit application delegate and native controls. The existing
`AirlockDemo/AirlockDemo.xcodeproj` also uses the local package.

## Migration

Replace `AirlockFlowView`, SwiftUI step builders, and environment modifiers with
`AirlockWindowController`, `AirlockStep`, and `AirlockStepViewController`.
SwiftUI visual components, full-screen overlays, and decorative feature cards
have been removed. The rainbow rim is rendered with AppKit/Core Animation.
The original `hello.lottie` and
`startup.wav` assets are preserved.

## License

MIT. See [LICENSE](LICENSE).
