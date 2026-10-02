import Foundation
import Observation

@MainActor
@Observable
final class PadOnboarding {
    enum Stage: Equatable {
        case intro, practice
    }

    enum Control: Hashable {
        case close, next, back, skip, done
    }

    @ObservationIgnored var focusedControl: Control?

    private let defaults: UserDefaults
    private static let completionKey = "pad.onboardingCompleted"

    private(set) var stage = Stage.intro
    private(set) var isPresented = false
    private(set) var practiceCount = 0
    private(set) var shortcutPressed = false
    @ObservationIgnored private var shortcutRelease: Task<Void, Never>?
    private(set) var hasCompleted: Bool

    init(defaults: UserDefaults) {
        self.defaults = defaults
        hasCompleted = defaults.bool(forKey: Self.completionKey)
    }

    /// Replay never changes the document or clears completion unless explicitly requested.
    func begin(resetCompletion: Bool = false) {
        if resetCompletion {
            hasCompleted = false
            defaults.set(false, forKey: Self.completionKey)
        }
        stage = .intro
        resetPractice()
        isPresented = true
    }

    @discardableResult
    func beginIfNeeded() -> Bool {
        guard !hasCompleted else { return false }
        // A second presentation request must not interrupt shortcut practice.
        if !isPresented { begin() }
        return true
    }

    func startPractice() {
        guard isPresented else { return }
        stage = .practice
    }

    func showIntroduction() {
        guard isPresented else { return }
        stage = .intro
        clearShortcutPress()
    }

    /// A changed global shortcut must be practiced again before completing.
    func resetPractice() {
        clearShortcutPress()
        practiceCount = 0
    }

    /// Called by the application's actual global shortcut handler, not local key matching.
    func recordShortcut() {
        guard isPresented, stage == .practice else { return }
        shortcutRelease?.cancel()
        shortcutPressed = true
        practiceCount += 1
    }

    func releaseShortcut() {
        guard shortcutPressed else { return }
        shortcutRelease?.cancel()
        // Keep a quick tap visible; a held shortcut remains pressed until key-up.
        shortcutRelease = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            self?.shortcutPressed = false
        }
    }

    private func clearShortcutPress() {
        shortcutRelease?.cancel()
        shortcutRelease = nil
        shortcutPressed = false
    }

    func resetCompletion() {
        dismiss()
        hasCompleted = false
        defaults.set(false, forKey: Self.completionKey)
        resetPractice()
    }

    func complete() {
        clearShortcutPress()
        hasCompleted = true
        defaults.set(true, forKey: Self.completionKey)
        isPresented = false
    }

    /// Closing the introduction is not completion and does not store a draft.
    func dismiss() {
        clearShortcutPress()
        isPresented = false
    }
}
