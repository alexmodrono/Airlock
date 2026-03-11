// Exports.swift
// AirlockUI
//
// Re-exports all public types from this module.

@_exported import AirlockCore

/*
 Public Types:

 == Main Views ==
 - AirlockFlowView: Declarative onboarding flow container (new)
 - AirlockConfiguration: Configuration for flow appearance/behavior (new)
 - AirlockView: Legacy two-column onboarding view (backward compatible)

 == Step Content Components (new) ==
 - AirlockStepContent: Standardized container for step content
 - AirlockInlineContinueButton: Continue button for inline use in steps
 - AirlockStepHeader: Header with icon, title, subtitle
 - AirlockStatusBadge: Badge showing step status
 - AirlockInfoCard: Card for displaying information
 - AirlockCapabilityChips: Row of capability/feature chips
 - AirlockCapabilityChip: Single capability chip
 - AirlockProgressSteps: List of progress steps with indicators
 - AirlockContinueButton: The main continue button (used in sidebar)

 == Feature Components ==
 - FeatureCard: Card displaying a feature with icon, title, description
 - FeatureRow: Simple row for displaying a feature
 - FeatureGrid: Grid layout for multiple features
 - AnimatedFeatureHighlight: Animated carousel of feature highlights

 == Permission Components ==
 - PermissionType: Enum representing macOS permission types
 - PermissionRowView: Row displaying a permission with status and action
 - PermissionsGroupView: Group of permissions with header and progress
 - PermissionChecker: Observable class for monitoring permission status

 == Animation Components ==
 - HelloAnimationView: Lottie-based "hello" animation
 - HelloAnimationController: Controller for the intro animation
 - StartupAnimationView: Reusable startup animation with sound and glow
 - AnimatedGlowEffect: Rotating gradient glow effect
 - StartupCardView: Card with startup animation, sound, and glow
 - FullscreenStartupView: Complete fullscreen startup experience

 == Utility Components ==
 - CheckDetailView: Reusable detail view template
 - InstructionStep: Numbered instruction component
 - SetupStage: Row indicating setup stage completion
 - ProgressBarView: Customizable progress bar with gradient
 - InfoBanner: Informational banner with icon and message
*/
