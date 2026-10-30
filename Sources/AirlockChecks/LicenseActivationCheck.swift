// LicenseActivationCheck.swift
// AirlockChecks

import AppKit
import Combine
import IOKit
import AirlockCore
import AirlockUI

/// A configurable license activation check.
@MainActor
public final class LicenseActivationCheck: FlightCheck, ObservableObject {
    public struct ValidationResult: Equatable, Sendable {
        public let isValid: Bool
        public let failureMessage: String?

        public init(isValid: Bool, failureMessage: String? = nil) {
            self.isValid = isValid
            self.failureMessage = failureMessage
        }
    }

    public typealias Validator = @Sendable (_ licenseKey: String, _ machineID: String) async throws -> ValidationResult

    public struct Configuration {
        public let title: String
        public let description: String
        public let icon: String
        public let actionLabel: String
        public let action: (() -> Void)?
        public let detailTitle: String
        public let detailDescription: String
        public let fieldTitle: String
        public let placeholder: String
        public let submitButtonTitle: String
        public let purchasePrompt: String?
        public let purchaseButtonTitle: String
        public let purchaseURL: URL?

        public init(
            title: String = "License Activation",
            description: String = "Validate your license key.",
            icon: String = "key.fill",
            actionLabel: String = "",
            action: (() -> Void)? = nil,
            detailTitle: String = "License Activation",
            detailDescription: String = "Enter your license key to unlock the full experience.",
            fieldTitle: String = "License Key",
            placeholder: String = "XXXX-XXXX-XXXX-XXXX",
            submitButtonTitle: String = "Activate",
            purchasePrompt: String? = nil,
            purchaseButtonTitle: String = "Purchase",
            purchaseURL: URL? = nil
        ) {
            self.title = title
            self.description = description
            self.icon = icon
            self.actionLabel = actionLabel
            self.action = action
            self.detailTitle = detailTitle
            self.detailDescription = detailDescription
            self.fieldTitle = fieldTitle
            self.placeholder = placeholder
            self.submitButtonTitle = submitButtonTitle
            self.purchasePrompt = purchasePrompt
            self.purchaseButtonTitle = purchaseButtonTitle
            self.purchaseURL = purchaseURL
        }
    }

    public let id = UUID()
    public let title: String
    public let description: String
    public let icon: String
    public let actionLabel: String

    @Published public var status: CheckStatus = .pending
    @Published public var licenseKey: String = ""
    @Published public var validationError: String?

    let configuration: Configuration
    private let storageKey: String?
    private let validator: Validator
    private let machineIDProvider: () -> String
    private var validationGeneration = UUID()

    public init(
        storageKey: String? = nil,
        configuration: Configuration = Configuration(),
        validator: @escaping Validator,
        machineIDProvider: (() -> String)? = nil
    ) {
        self.storageKey = storageKey
        self.configuration = configuration
        self.validator = validator
        self.machineIDProvider = machineIDProvider ?? Self.defaultMachineID
        self.title = configuration.title
        self.description = configuration.description
        self.icon = configuration.icon
        self.actionLabel = configuration.actionLabel

        if let storageKey,
           let savedKey = UserDefaults.standard.string(forKey: storageKey) {
            self.licenseKey = savedKey
        }
    }

    public var detailView: NSViewController {
        NativeCheckViewController(check: self)
    }

    public func performAction() {
        configuration.action?()
    }

    @MainActor
    public func validate() async -> Bool {
        // Pure predicate. The actual network validation runs only on explicit
        // submission (see submitLicenseKey / validateStoredKeyIfNeeded) so the
        // background validation loop never re-POSTs a stale key on every tick.
        status == .success
    }

    /// Submit only on an explicit action. A late reply cannot validate or persist
    /// a different key after cancellation or a newer submission.
    @MainActor
    public func submitLicenseKey(_ key: String) async {
        licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedKey = licenseKey
        validationGeneration = UUID()
        let attempt = validationGeneration
        validationError = nil
        guard !submittedKey.isEmpty else { status = .active; return }
        status = .checking
        do {
            try Task.checkCancellation()
            let result = try await validator(submittedKey, machineIDProvider())
            guard validationGeneration == attempt else { return }
            try Task.checkCancellation()
            guard licenseKey == submittedKey else { status = .active; return }
            validationError = result.failureMessage
            if result.isValid, let storageKey {
                UserDefaults.standard.set(submittedKey, forKey: storageKey)
            }
            status = result.isValid ? .success : .active
        } catch {
            guard validationGeneration == attempt else { return }
            if !Task.isCancelled, !(error is CancellationError) { validationError = error.localizedDescription }
            status = .active
        }
    }

    /// Invalidates a pending reply when its screen is left or the flow closes.
    public func cancelPendingValidation() {
        validationGeneration = UUID()
        if status == .checking { status = .active }
    }

    /// Validates a previously stored key once without replaying it on polling ticks.
    @MainActor
    public func validateStoredKeyIfNeeded() async {
        guard status != .success, status != .checking, !licenseKey.isEmpty else { return }
        await submitLicenseKey(licenseKey)
    }

    /// Returns a validator that posts JSON to an HTTP endpoint.
    public static func jsonEndpointValidator(
        endpoint: URL,
        headers: [String: String] = [:],
        requestBody: @escaping @Sendable (_ licenseKey: String, _ machineID: String) throws -> Data,
        responseParser: @escaping @Sendable (_ data: Data, _ response: HTTPURLResponse) throws -> ValidationResult
    ) -> Validator {
        { licenseKey, machineID in
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            for (header, value) in headers {
                request.setValue(value, forHTTPHeaderField: header)
            }

            request.httpBody = try requestBody(licenseKey, machineID)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ValidationResult(isValid: false, failureMessage: "Unexpected server response.")
            }
            return try responseParser(data, httpResponse)
        }
    }

    private static func defaultMachineID() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        defer { IOObjectRelease(platformExpert) }

        if let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return uuid
        }

        return UUID().uuidString
    }
}
