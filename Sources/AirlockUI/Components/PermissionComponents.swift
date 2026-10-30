// PermissionComponents.swift
// AirlockUI
//
// Reusable permission UI components with native system icons
// and easy navigation to System Settings.

import Combine
import AppKit
import ApplicationServices
import AVFoundation
import Contacts
import EventKit
import Photos
import CoreLocation

/// A single shared location manager for reading authorization status.
///
/// Creating a `CLLocationManager` per read (as the old code did inside computed
/// properties hit during rendering) is wasteful; one shared instance is enough
/// to query `authorizationStatus`.
@MainActor private let airlockLocationManager = CLLocationManager()

// MARK: - Permission Grant State

/// The current authorization state for a macOS permission.
public enum PermissionGrantState: Equatable {
    /// Airlock could verify that the permission is granted.
    case granted

    /// Airlock could verify that the permission is not granted.
    case notGranted

    /// macOS does not expose a reliable generic API for this permission.
    /// The associated message explains what the host app should do instead.
    case requiresManualVerification(String)

    /// Whether the permission is currently granted.
    public var isGranted: Bool {
        if case .granted = self {
            return true
        }
        return false
    }
}

/// Describes how Airlock can ask for a permission.
public enum PermissionRequestAvailability: Equatable {
    /// Airlock can trigger the system prompt directly from the app.
    case inAppPrompt

    /// macOS requires the user to review or enable the permission in System Settings.
    case openSystemSettings

    /// Airlock cannot request this permission generically.
    /// The associated message explains what the host app should do.
    case requiresCustomHandling(String)
}

// MARK: - Permission Type

/// Represents different macOS permission types with their settings URLs and check methods.
@MainActor
public enum PermissionType: String, CaseIterable, Identifiable {
    case accessibility
    case fullDiskAccess
    case automation
    case screenRecording
    case camera
    case microphone
    case contacts
    case calendars
    case reminders
    case photos
    case files
    case locationServices

    public nonisolated var id: String { rawValue }

    /// Display name for the permission.
    public var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "Full Disk Access"
        case .automation: return "Automation"
        case .screenRecording: return "Screen Recording"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .contacts: return "Contacts"
        case .calendars: return "Calendars"
        case .reminders: return "Reminders"
        case .photos: return "Photos"
        case .files: return "Files and Folders"
        case .locationServices: return "Location Services"
        }
    }

    /// Description of why the permission is needed.
    public var defaultDescription: String {
        switch self {
        case .accessibility:
            return "Required to observe and interact with other applications."
        case .fullDiskAccess:
            return "Required to read or organize files in protected locations."
        case .automation:
            return "Required to control another app via Apple Events."
        case .screenRecording:
            return "Required to inspect on-screen window content."
        case .camera:
            return "Required to access your camera."
        case .microphone:
            return "Required to access your microphone."
        case .contacts:
            return "Required to access your contacts."
        case .calendars:
            return "Required to access your calendars."
        case .reminders:
            return "Required to access your reminders."
        case .photos:
            return "Required to access your photo library."
        case .files:
            return "Required to access specific folders that macOS protects per app."
        case .locationServices:
            return "Required to access your location."
        }
    }

    /// SF Symbol matching the System Settings Privacy & Security icons.
    public var systemImage: String {
        switch self {
        case .accessibility: return "accessibility"
        case .fullDiskAccess: return "opticaldiscdrive.fill"
        case .automation: return "applescript.fill"
        case .screenRecording: return "rectangle.inset.filled.and.person.filled"
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .contacts: return "person.crop.rectangle.stack.fill"
        case .calendars: return "calendar"
        case .reminders: return "list.bullet.rectangle.fill"
        case .photos: return "photo.stack.fill"
        case .files: return "folder.fill"
        case .locationServices: return "location.fill"
        }
    }

    /// The accent color associated with this permission type.
    public var accentColor: NSColor {
        switch self {
        case .accessibility: return .blue
        case .fullDiskAccess: return .gray
        case .automation: return .purple
        case .screenRecording: return .orange
        case .camera: return .green
        case .microphone: return .systemPink
        case .contacts: return .brown
        case .calendars: return .red
        case .reminders: return .orange
        case .photos: return NSColor(red: 0.98, green: 0.36, blue: 0.45, alpha: 1)
        case .files: return .blue
        case .locationServices: return .blue
        }
    }

    /// The URL to open System Settings for this permission.
    public var settingsURL: URL? {
        let urlString: String
        switch self {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .fullDiskAccess:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .automation:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .camera:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .contacts:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        case .calendars:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .reminders:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        case .photos:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
        case .files:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case .locationServices:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        }
        return URL(string: urlString)
    }

    /// Opens System Settings to this permission's panel.
    public func openSettings() {
        guard let url = settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// How Airlock can request this permission from the user.
    public var requestAvailability: PermissionRequestAvailability {
        switch self {
        case .accessibility:
            return .inAppPrompt

        case .fullDiskAccess:
            return .openSystemSettings

        case .automation:
            return .requiresCustomHandling(
                "Automation permission must be requested against a specific target app."
            )

        case .screenRecording:
            return .inAppPrompt

        case .camera:
            return avRequestAvailability(for: .video)

        case .microphone:
            return avRequestAvailability(for: .audio)

        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .notDetermined:
                return .inAppPrompt
            case .authorized:
                return .inAppPrompt
            case .denied, .restricted:
                return .openSystemSettings
            @unknown default:
                return .openSystemSettings
            }

        case .calendars:
            return eventKitRequestAvailability(for: .event)

        case .reminders:
            return eventKitRequestAvailability(for: .reminder)

        case .photos:
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .notDetermined:
                return .inAppPrompt
            case .authorized, .limited:
                return .inAppPrompt
            case .denied, .restricted:
                return .openSystemSettings
            @unknown default:
                return .openSystemSettings
            }

        case .files:
            return .requiresCustomHandling(
                "Files and Folders access depends on which folders your app touches. Use a custom request flow or folder picker."
            )

        case .locationServices:
            let status = airlockLocationManager.authorizationStatus
            switch status {
            case .notDetermined:
                return .inAppPrompt
            case .authorizedAlways, .authorizedWhenInUse, .authorized:
                return .inAppPrompt
            case .denied, .restricted:
                return .openSystemSettings
            @unknown default:
                return .openSystemSettings
            }
        }
    }

    /// Default button label for requesting this permission.
    public var requestButtonLabel: String {
        switch requestAvailability {
        case .inAppPrompt:
            return "Request"
        case .openSystemSettings:
            return "Open Settings"
        case .requiresCustomHandling:
            return "Custom Setup"
        }
    }

    /// Requests the permission where macOS allows it, or opens System Settings otherwise.
    @MainActor
    public func requestAccess() async -> PermissionGrantState {
        switch self {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return authorizationState

        case .fullDiskAccess:
            openSettings()
            return authorizationState

        case .automation:
            return .requiresManualVerification(
                "Automation access must be requested against a specific target app. Supply a custom request handler that sends the Apple Event your app needs."
            )

        case .screenRecording:
            if CGPreflightScreenCaptureAccess() {
                return .granted
            }
            return CGRequestScreenCaptureAccess() ? .granted : authorizationState

        case .camera:
            return await requestAVAccess(for: .video)

        case .microphone:
            return await requestAVAccess(for: .audio)

        case .contacts:
            return await requestContactsAccess()

        case .calendars:
            return await requestCalendarsAccess()

        case .reminders:
            return await requestRemindersAccess()

        case .photos:
            return await requestPhotosAccess()

        case .files:
            return .requiresManualVerification(
                "Files and Folders access depends on the folder your app touches. Supply a custom request handler or folder picker for the folders your app uses."
            )

        case .locationServices:
            return await requestLocationAccess()
        }
    }

    /// A best-effort authorization state for this permission.
    ///
    /// Some permissions are app-specific and cannot be verified generically.
    /// In those cases, Airlock returns `.requiresManualVerification(...)`
    /// instead of incorrectly reporting `false`.
    public var authorizationState: PermissionGrantState {
        switch self {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted

        case .fullDiskAccess:
            return PermissionDetector.fullDiskAccessState()

        case .automation:
            return .requiresManualVerification(
                "Automation access is granted per target app. Provide a custom state provider for the app you control."
            )

        case .screenRecording:
            return PermissionDetector.screenRecordingState()

        case .camera:
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            return status == .authorized ? .granted : .notGranted

        case .microphone:
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            return status == .authorized ? .granted : .notGranted

        case .contacts:
            let status = CNContactStore.authorizationStatus(for: .contacts)
            return status == .authorized ? .granted : .notGranted

        case .calendars:
            if #available(macOS 14.0, *) {
                let status = EKEventStore.authorizationStatus(for: .event)
                return (status == .fullAccess || status == .writeOnly) ? .granted : .notGranted
            } else {
                let status = EKEventStore.authorizationStatus(for: .event)
                return status == .authorized ? .granted : .notGranted
            }

        case .reminders:
            if #available(macOS 14.0, *) {
                let status = EKEventStore.authorizationStatus(for: .reminder)
                return (status == .fullAccess || status == .writeOnly) ? .granted : .notGranted
            } else {
                let status = EKEventStore.authorizationStatus(for: .reminder)
                return status == .authorized ? .granted : .notGranted
            }

        case .photos:
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            return (status == .authorized || status == .limited) ? .granted : .notGranted

        case .files:
            return .requiresManualVerification(
                "Files and Folders access is granted per folder. Supply a custom state provider that probes the folders your app actually uses."
            )

        case .locationServices:
            let status = airlockLocationManager.authorizationStatus
            switch status {
            case .authorized, .authorizedAlways, .authorizedWhenInUse:
                return .granted
            case .notDetermined, .denied, .restricted:
                return .notGranted
            @unknown default:
                return .notGranted
            }
        }
    }

    /// Backward-compatible boolean view of `authorizationState`.
    public var isGranted: Bool {
        authorizationState.isGranted
    }

    private func avRequestAvailability(for mediaType: AVMediaType) -> PermissionRequestAvailability {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .notDetermined, .authorized:
            return .inAppPrompt
        case .denied, .restricted:
            return .openSystemSettings
        @unknown default:
            return .openSystemSettings
        }
    }

    private func eventKitRequestAvailability(for entityType: EKEntityType) -> PermissionRequestAvailability {
        let status = EKEventStore.authorizationStatus(for: entityType)
        switch status {
        case .notDetermined:
            return .inAppPrompt
        case .authorized, .fullAccess, .writeOnly:
            return .inAppPrompt
        case .denied, .restricted:
            return .openSystemSettings
        @unknown default:
            return .openSystemSettings
        }
    }

    @MainActor
    private func requestAVAccess(for mediaType: AVMediaType) async -> PermissionGrantState {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return .granted
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
            return granted ? .granted : .notGranted
        case .denied, .restricted:
            openSettings()
            return authorizationState
        @unknown default:
            return .notGranted
        }
    }

    @MainActor
    private func requestContactsAccess() async -> PermissionGrantState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return .granted
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                CNContactStore().requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            return granted ? .granted : .notGranted
        case .denied, .restricted:
            openSettings()
            return authorizationState
        @unknown default:
            return .notGranted
        }
    }

    @MainActor
    private func requestCalendarsAccess() async -> PermissionGrantState {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            return .granted
        case .notDetermined:
            if #available(macOS 14.0, *) {
                let granted = (try? await store.requestFullAccessToEvents()) ?? false
                return granted ? .granted : .notGranted
            } else {
                let granted = await withCheckedContinuation { continuation in
                    store.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
                return granted ? .granted : .notGranted
            }
        case .denied, .restricted:
            openSettings()
            return authorizationState
        @unknown default:
            return .notGranted
        }
    }

    @MainActor
    private func requestRemindersAccess() async -> PermissionGrantState {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            return .granted
        case .notDetermined:
            if #available(macOS 14.0, *) {
                let granted = (try? await store.requestFullAccessToReminders()) ?? false
                return granted ? .granted : .notGranted
            } else {
                let granted = await withCheckedContinuation { continuation in
                    store.requestAccess(to: .reminder) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
                return granted ? .granted : .notGranted
            }
        case .denied, .restricted:
            openSettings()
            return authorizationState
        @unknown default:
            return .notGranted
        }
    }

    @MainActor
    private func requestPhotosAccess() async -> PermissionGrantState {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return .granted
        case .notDetermined:
            let updatedStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
            return (updatedStatus == .authorized || updatedStatus == .limited) ? .granted : .notGranted
        case .denied, .restricted:
            openSettings()
            return authorizationState
        @unknown default:
            return .notGranted
        }
    }

    @MainActor
    private func requestLocationAccess() async -> PermissionGrantState {
        let requester = LocationPermissionRequester()
        return await requester.request()
    }
}

// MARK: - Permission Detection Helpers

@MainActor
private enum PermissionDetector {
    private static let fullDiskAccessProbePaths: [String] = [
        "Library/Mail",
        "Library/Safari",
        "Library/Messages",
        "Library/Application Support/com.apple.TCC"
    ]

    static func fullDiskAccessState() -> PermissionGrantState {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        var foundCandidate = false

        for relativePath in fullDiskAccessProbePaths {
            let path = homeDirectory.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false

            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
                continue
            }

            foundCandidate = true

            do {
                _ = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
                return .granted
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain &&
                    error.code == NSFileReadNoPermissionError {
                    return .notGranted
                }
            } catch {
                continue
            }
        }

        if foundCandidate {
            return .requiresManualVerification(
                "Airlock could not confirm Full Disk Access automatically on this Mac. Review the setting manually."
            )
        }

        return .requiresManualVerification(
            "This Mac does not expose a standard protected folder to probe. Review Full Disk Access manually."
        )
    }

    static func screenRecordingState() -> PermissionGrantState {
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return .notGranted
        }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != myPID else {
                continue
            }

            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                return .granted
            }
        }

        let hasOtherAppWindows = windowList.contains {
            guard let pid = $0[kCGWindowOwnerPID as String] as? Int32 else { return false }
            return pid != myPID
        }

        return hasOtherAppWindows ? .notGranted : .requiresManualVerification(
            "No other app windows were visible, so screen recording access could not be confirmed automatically."
        )
    }
}

// MARK: - Permission Status Checker

/// A utility class for checking and monitoring permission status.
@MainActor
public final class PermissionChecker: ObservableObject {
    public typealias RequestHandler = @MainActor (PermissionType) async -> PermissionGrantState

    @Published public private(set) var permissionStatus: [PermissionType: Bool] = [:]
    @Published public private(set) var permissionStates: [PermissionType: PermissionGrantState] = [:]

    private var checkTimer: Timer?
    private let permissionsToCheck: [PermissionType]
    private let stateProvider: (PermissionType) -> PermissionGrantState
    private let requestHandler: RequestHandler?

    public init(
        permissions: [PermissionType],
        stateProvider: ((PermissionType) -> PermissionGrantState)? = nil,
        requestHandler: RequestHandler? = nil
    ) {
        self.permissionsToCheck = permissions
        self.stateProvider = stateProvider ?? { $0.authorizationState }
        self.requestHandler = requestHandler
        checkAllPermissions()
    }

    isolated deinit {
        checkTimer?.invalidate()
    }

    /// Checks all permissions once.
    public func checkAllPermissions() {
        for permission in permissionsToCheck {
            let state = stateProvider(permission)
            permissionStates[permission] = state
            permissionStatus[permission] = state.isGranted
        }
    }

    /// Starts periodic checking of permissions.
    public func startMonitoring(interval: TimeInterval = 1.0) {
        stopMonitoring()
        checkAllPermissions()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkAllPermissions()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
    }

    /// Stops periodic checking.
    public func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Whether all permissions are granted.
    public var allGranted: Bool {
        permissionsToCheck.allSatisfy { permissionStates[$0]?.isGranted == true }
    }

    /// The set of granted permissions.
    public var grantedPermissions: Set<PermissionType> {
        Set(permissionStates.compactMap { $0.value.isGranted ? $0.key : nil })
    }

    /// Returns the current state for a permission.
    public func state(for permission: PermissionType) -> PermissionGrantState {
        permissionStates[permission] ?? stateProvider(permission)
    }

    /// Whether the specified permission is granted.
    public func isGranted(_ permission: PermissionType) -> Bool {
        state(for: permission).isGranted
    }

    /// Requests the specified permission and stores the resulting state.
    @discardableResult
    public func requestAccess(for permission: PermissionType) async -> PermissionGrantState {
        let state = if let requestHandler {
            await requestHandler(permission)
        } else {
            await permission.requestAccess()
        }

        permissionStates[permission] = state
        permissionStatus[permission] = state.isGranted
        return state
    }

    /// Opens settings for a specific permission.
    public func openSettings(for permission: PermissionType) {
        permission.openSettings()
    }
}

// MARK: - Location Permission Requester

@MainActor
private final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<PermissionGrantState, Never>?

    @MainActor
    override init() {
        super.init()
        manager.delegate = self
    }

    @MainActor
    func request() async -> PermissionGrantState {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            return .granted
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            PermissionType.locationServices.openSettings()
            return PermissionType.locationServices.authorizationState
        @unknown default:
            return .notGranted
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        Task { @MainActor in
            guard let continuation else { return }

            let state: PermissionGrantState
            switch authorization {
            case .authorizedAlways, .authorizedWhenInUse, .authorized:
                state = .granted
            case .notDetermined:
                return
            case .denied, .restricted:
                state = .notGranted
            @unknown default:
                state = .notGranted
            }

            self.continuation = nil
            continuation.resume(returning: state)
        }
    }
}
