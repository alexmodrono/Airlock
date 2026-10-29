import AppKit

/// A native onboarding screen. Controllers are created lazily by the window.
@MainActor
public struct AirlockStep: Identifiable {
    public let id: String
    public let title: String
    public let makeViewController: @MainActor () -> NSViewController
    public var allowsGoingBack = true
    public var validation: (@MainActor () async -> Bool)?

    public init(id: String, title: String, content: @escaping @MainActor () -> NSViewController) {
        self.id = id
        self.title = title
        self.makeViewController = content
    }

    public func allowsGoingBack(_ allowed: Bool) -> Self {
        var copy = self
        copy.allowsGoingBack = allowed
        return copy
    }

    public func validation(_ validate: @escaping @MainActor () async -> Bool) -> Self {
        var copy = self
        copy.validation = validate
        return copy
    }
}

@resultBuilder
public struct AirlockStepBuilder {
    public static func buildBlock(_ components: [AirlockStep]...) -> [AirlockStep] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: AirlockStep) -> [AirlockStep] { [expression] }
    public static func buildOptional(_ component: [AirlockStep]?) -> [AirlockStep] { component ?? [] }
    public static func buildEither(first component: [AirlockStep]) -> [AirlockStep] { component }
    public static func buildEither(second component: [AirlockStep]) -> [AirlockStep] { component }
    public static func buildArray(_ components: [[AirlockStep]]) -> [AirlockStep] { components.flatMap { $0 } }
}
