// Exports.swift
// AirlockCore
//
// Re-exports all public types from this module.

// All types in this module are automatically available.
// This file serves as documentation of the public API.

/*
 Public Types:

 == Declarative API (New) ==
 - AirlockStep: Generic step definition for onboarding flows
 - AnyAirlockStep: Type-erased step wrapper
 - AirlockStepBuilder: Result builder for declarative step arrays
 - AirlockNavigator: State management for step navigation
 - AirlockStepStatus: Enum for step status (pending, current, completed)

 == Environment Values ==
 - airlockNavigator: The navigator managing the flow
 - airlockStepStatus: Current step's status
 - airlockCanContinue: Whether continue button is enabled
 - airlockStepIndex: Current step index
 - airlockStepCount: Total number of steps
 - airlockIsLastStep: Whether this is the last step
 - airlockCanGoBack: Whether back navigation is available

 == View Modifiers ==
 - airlockEnableContinue(): Enables the continue button
 - airlockContinueEnabled(_:): Controls continue button state
 - airlockEnableContinueAfter(seconds:): Enables continue after delay

 == Legacy API (Backward Compatible) ==
 - CheckStatus: Enum representing the status of a flight check
 - CheckError: Error type for check failures
 - FlightCheck: Protocol for defining flight checks
 - AnyFlightCheck: Type-erased wrapper for FlightCheck
 - AirlockManager: State manager for the onboarding sequence
*/
