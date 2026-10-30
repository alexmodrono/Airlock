# Releasing Airlock

The AppKit API replaces the earlier SwiftUI presentation API. Publish this change
with an appropriate major-version release note; see the README migration section.
An application may also pin a reviewed commit while preparing its own release.

## Qualify the revision

Run from a clean checkout with the committed package lockfile:

```sh
swift test --configuration debug --force-resolved-versions
swift test --configuration release --force-resolved-versions
xcodebuild -project AirlockDemo/AirlockDemo.xcodeproj -scheme AirlockDemo \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/AirlockDemoQualification \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

GitHub Actions runs the same package configurations and unsigned demo using
Xcode 26.6. Record the commit, toolchain version, test results, and any unresolved
runtime warnings. A local pass on another Xcode version does not establish the
CI toolchain result.

Check the native window and step controls in a consuming app: typing, validation,
back-navigation checkpoints, closing during work, reopening, and small/offset
displays. Keep the main window solid and compact; glass belongs to the navigation
pill. Verify the intro glow ends, startup sound plays once, and accessibility
settings are respected.

When updating Lottie, keep the root `Package.resolved` and the demo workspace's
lockfile at the same reviewed revision. Consuming applications retain their own
lockfiles.

## Publish

Push the reviewed commit and wait for CI before creating a version tag or release.
Use a semantic version for tags and describe the removed SwiftUI APIs. Consumers
should pin the accepted version or immutable revision, rather than an unreviewed
working checkout.
