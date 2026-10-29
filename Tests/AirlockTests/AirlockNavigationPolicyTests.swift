import AppKit
import Testing
@testable import Airlock

@Suite @MainActor
struct AirlockNavigationPolicyTests {
    private func navigator() -> AirlockNavigator {
        AirlockNavigator(appName: "Test", steps: [
            AirlockStep(id: "site", title: "Site") { NSViewController() },
            AirlockStep(id: "signin", title: "Sign In") { NSViewController() },
            AirlockStep(id: "courses", title: "Courses") { NSViewController() }.allowsGoingBack(false),
            AirlockStep(id: "finder", title: "Finder") { NSViewController() },
            AirlockStep(id: "sync", title: "Sync") { NSViewController() }
        ])
    }

    @Test func navigationStopsAtTheWholeCheckpointBoundary() {
        let nav = navigator()
        for _ in 0..<4 {
            nav.setContinueEnabled(true)
            nav.goToNext()
        }
        #expect(nav.currentIndex == 4)
        #expect(!nav.canGoTo(index: 0))
        #expect(!nav.canGoTo(index: 1))
        #expect(nav.canGoTo(index: 2))
        #expect(nav.canGoTo(index: 3))
        #expect(nav.canGoTo(index: 4))
        nav.goTo(index: 1)
        #expect(nav.currentIndex == 4)
        nav.goTo(index: 2)
        #expect(nav.currentIndex == 2)
        #expect(!nav.canGoBack)
    }

    @Test func futureAndInvalidStepsCannotSkipValidation() {
        let nav = navigator()
        #expect(!nav.canGoTo(index: -1))
        #expect(!nav.canGoTo(index: 1))
        #expect(!nav.canGoTo(index: nav.steps.count))
        nav.goTo(index: 1)
        #expect(nav.currentIndex == 0)
        #expect(!nav.canContinue)
    }

    @Test func selectingTheCurrentStepPreservesItsActionState() {
        let nav = navigator()
        nav.setContinueEnabled(true)
        nav.setButtonLabel("Connect")
        #expect(nav.canGoTo(index: 0))
        nav.goTo(index: 0)
        #expect(nav.currentIndex == 0)
        #expect(nav.canContinue)
        #expect(nav.buttonLabel == "Connect")
    }

    @Test func busyNavigationCannotSwitchSteps() async {
        let nav = navigator()
        nav.setContinueEnabled(true)
        nav.goToNext()
        let started = AsyncStream<Void>.makeStream()
        var continuation: CheckedContinuation<Void, Never>?
        nav.setButtonAction(label: "Sign In") {
            started.continuation.yield(())
            await withCheckedContinuation { continuation = $0 }
        }
        nav.setContinueEnabled(true)
        nav.goToNext()
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(nav.isBusy)
        #expect(!nav.canGoTo(index: 0))
        #expect(!nav.canGoTo(index: 1))
        #expect(!nav.canGoTo(index: 2))
        #expect(!nav.canGoBack)
        nav.goTo(index: 0)
        #expect(nav.currentIndex == 1)
        nav.cancelPendingAction()
        continuation?.resume()
        started.continuation.finish()
        #expect(nav.canGoTo(index: 0))
        #expect(nav.canGoTo(index: 1))
    }

    @Test func completedNavigationCannotReopenSteps() {
        let nav = navigator()
        for _ in nav.steps {
            nav.setContinueEnabled(true)
            nav.goToNext()
        }
        #expect(nav.isComplete)
        #expect(!nav.canGoBack)
        for index in nav.steps.indices { #expect(!nav.canGoTo(index: index)) }
        nav.goTo(index: 3)
        #expect(nav.currentIndex == 4)
    }
}
