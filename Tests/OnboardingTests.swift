import Foundation
import Testing
@testable import Pad

@MainActor
@Suite struct OnboardingTests {
    @Test func firstPresentationIsOptInAndDoesNotPersistCompletion() {
        let fixture = OnboardingFixture()
        defer { fixture.cleanUp() }
        let onboarding = fixture.onboarding

        #expect(!onboarding.isPresented)
        #expect(!onboarding.hasCompleted)
        #expect(onboarding.beginIfNeeded())
        #expect(onboarding.isPresented)
        #expect(onboarding.stage == .intro)
        #expect(fixture.defaults.object(forKey: "pad.onboardingCompleted") == nil)
    }

    @Test func onlyPresentedPracticeRecordsShortcutEvents() {
        let fixture = OnboardingFixture()
        defer { fixture.cleanUp() }
        let onboarding = fixture.onboarding

        onboarding.startPractice()
        onboarding.recordShortcut()
        #expect(onboarding.stage == .intro)
        #expect(onboarding.practiceCount == 0)

        onboarding.begin()
        onboarding.recordShortcut()
        #expect(onboarding.practiceCount == 0)

        onboarding.startPractice()
        onboarding.recordShortcut()
        onboarding.recordShortcut()
        #expect(onboarding.practiceCount == 2)
        #expect(onboarding.stage == .practice)
        #expect(onboarding.isPresented)
        #expect(!onboarding.hasCompleted)

        onboarding.dismiss()
        onboarding.recordShortcut()
        #expect(onboarding.practiceCount == 2)
        #expect(!onboarding.isPresented)
    }

    @Test func repeatedPresentationRequestsDoNotRestartPractice() {
        let fixture = OnboardingFixture()
        defer { fixture.cleanUp() }
        let onboarding = fixture.onboarding
        onboarding.begin()
        onboarding.startPractice()
        onboarding.recordShortcut()

        #expect(onboarding.beginIfNeeded())
        #expect(onboarding.stage == .practice)
        #expect(onboarding.practiceCount == 1)
    }

    @Test func closingWithoutCompletionOffersTheIntroductionAgain() {
        let fixture = OnboardingFixture()
        defer { fixture.cleanUp() }
        let onboarding = fixture.onboarding
        onboarding.begin()
        onboarding.startPractice()
        onboarding.recordShortcut()
        onboarding.dismiss()

        #expect(!onboarding.hasCompleted)
        #expect(onboarding.beginIfNeeded())
        #expect(onboarding.stage == .intro)
        #expect(onboarding.practiceCount == 0)
        #expect(!PadOnboarding(defaults: fixture.defaults).hasCompleted)
    }

    @Test func completionPersistsAndSuppressesAutomaticPresentation() {
        let fixture = OnboardingFixture()
        defer { fixture.cleanUp() }
        let onboarding = fixture.onboarding
        onboarding.begin()
        onboarding.startPractice()
        onboarding.recordShortcut()
        onboarding.complete()

        #expect(onboarding.hasCompleted)
        #expect(!onboarding.isPresented)
        #expect(!onboarding.beginIfNeeded())
        #expect(!onboarding.isPresented)

        let restored = PadOnboarding(defaults: fixture.defaults)
        #expect(restored.hasCompleted)
        #expect(!restored.beginIfNeeded())
        #expect(!restored.isPresented)
    }

    @Test func skippingCanCompleteWithoutClaimingShortcutPractice() {
        let fixture = OnboardingFixture()
        defer { fixture.cleanUp() }
        let onboarding = fixture.onboarding
        onboarding.begin()
        onboarding.complete()

        #expect(onboarding.hasCompleted)
        #expect(onboarding.practiceCount == 0)
        #expect(!onboarding.isPresented)
    }

    @Test func replayRetainsCompletionUntilExplicitReset() {
        let fixture = OnboardingFixture()
        defer { fixture.cleanUp() }
        let onboarding = fixture.onboarding
        onboarding.begin()
        onboarding.startPractice()
        onboarding.recordShortcut()
        onboarding.complete()
        onboarding.begin()

        #expect(onboarding.isPresented)
        #expect(onboarding.stage == .intro)
        #expect(onboarding.practiceCount == 0)
        #expect(onboarding.hasCompleted)
        #expect(PadOnboarding(defaults: fixture.defaults).hasCompleted)

        onboarding.dismiss()
        #expect(!onboarding.beginIfNeeded())
        onboarding.begin(resetCompletion: true)
        #expect(onboarding.isPresented)
        #expect(!onboarding.hasCompleted)
        #expect(!PadOnboarding(defaults: fixture.defaults).hasCompleted)
    }

    @Test func completionIsIsolatedToTheSuppliedDefaults() {
        let first = OnboardingFixture()
        let second = OnboardingFixture()
        defer {
            first.cleanUp()
            second.cleanUp()
        }
        first.onboarding.begin()
        first.onboarding.complete()

        #expect(!second.onboarding.hasCompleted)
        #expect(second.onboarding.beginIfNeeded())
        #expect(second.defaults.object(forKey: "pad.onboardingCompleted") == nil)
    }
}

@MainActor
private struct OnboardingFixture {
    let suite: String
    let defaults: UserDefaults
    let onboarding: PadOnboarding

    init() {
        suite = "pad-onboarding-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        onboarding = PadOnboarding(defaults: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
    }
}
