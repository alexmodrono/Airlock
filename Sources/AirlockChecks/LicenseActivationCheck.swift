// LicenseActivationCheck.swift
// AirlockChecks

import SwiftUI
import AppKit
import IOKit
import AirlockCore

/// A configurable license activation check.
public final class LicenseActivationCheck: FlightCheck, ObservableObject {
    public struct ValidationResult: Equatable {
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

    fileprivate let configuration: Configuration
    private let storageKey: String?
    private let validator: Validator
    private let machineIDProvider: () -> String

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

    public var detailView: AnyView {
        AnyView(LicenseActivationDetailView(check: self))
    }

    public func performAction() {
        configuration.action?()
    }

    @MainActor
    public func validate() async -> Bool {
        guard !licenseKey.isEmpty else {
            return false
        }

        do {
            let result = try await validator(licenseKey, machineIDProvider())
            validationError = result.failureMessage

            if result.isValid, let storageKey {
                UserDefaults.standard.set(licenseKey, forKey: storageKey)
            }

            return result.isValid
        } catch {
            validationError = error.localizedDescription
            return false
        }
    }

    /// Submits the license key for validation.
    @MainActor
    public func submitLicenseKey(_ key: String) async {
        licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .checking

        let valid = await validate()
        status = valid ? .success : .active
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

// MARK: - Detail View

struct LicenseActivationDetailView: View {
    @ObservedObject var check: LicenseActivationCheck
    @State private var inputKey: String = ""
    @State private var isValidating: Bool = false

    var body: some View {
        CheckDetailView(
            icon: check.configuration.icon,
            title: check.configuration.detailTitle,
            description: check.configuration.detailDescription,
            status: check.status
        ) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(check.configuration.fieldTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)

                    HStack(spacing: 12) {
                        TextField(check.configuration.placeholder, text: $inputKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(borderColor, lineWidth: 1)
                            )

                        Button {
                            Task {
                                isValidating = true
                                await check.submitLicenseKey(inputKey)
                                isValidating = false
                            }
                        } label: {
                            if isValidating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(check.configuration.submitButtonTitle)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputKey.isEmpty || isValidating)
                    }

                    if let error = check.validationError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }

                if let prompt = check.configuration.purchasePrompt,
                   let purchaseURL = check.configuration.purchaseURL {
                    HStack {
                        Text(prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(check.configuration.purchaseButtonTitle) {
                            NSWorkspace.shared.open(purchaseURL)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
        }
        .onAppear {
            inputKey = check.licenseKey
        }
    }

    private var borderColor: Color {
        if check.validationError != nil {
            return .red.opacity(0.5)
        }
        return Color.primary.opacity(0.1)
    }
}
