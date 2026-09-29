import AppKit
import KeyboardShortcuts
import SwiftUI

struct PadOnboardingView: View {
    let onboarding: PadOnboarding
    let shortcut: KeyboardShortcuts.Shortcut?
    let draftExplanation: String
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDetails = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case close, start, practice, details, back, skip, continueWriting
    }

    private let lavender = Color(red: 0.40, green: 0.33, blue: 0.68)

    private var hasPracticed: Bool { onboarding.practiceCount > 0 }
    private var canContinue: Bool { hasPracticed || shortcut == nil }

    // A bare Return assigned as the global shortcut belongs exclusively to practice.
    // Modified Return shortcuts are ignored by the local, unmodified Return handler.
    private var returnCanContinue: Bool {
        !(shortcut?.key == .return && shortcut?.modifiers.isEmpty == true)
    }

    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                let compact = geometry.size.height < 360
                VStack(spacing: 0) {
                    ZStack {
                        switch onboarding.stage {
                        case .intro:
                            introduction(compact: compact)
                                .transition(stageTransition)
                        case .practice:
                            practice(compact: compact)
                                .transition(stageTransition)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    footer
                }
                .padding(.horizontal, compact ? 18 : 24)
                .padding(.top, compact ? 4 : 12)
                .padding(.bottom, compact ? 8 : 14)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: onboarding.stage)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding([.horizontal, .bottom], 7)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .defaultFocus($focusedControl, .start)
        .onChange(of: onboarding.stage) {
            focusedControl = onboarding.stage == .intro ? .start : .practice
        }
        .onChange(of: onboarding.practiceCount) { oldCount, newCount in
            if oldCount == 0, newCount > 0 { focusedControl = .continueWriting }
        }
        .onKeyPress(.return, phases: [.down, .repeat], action: handleReturn)
        .onExitCommand(perform: onClose)
        .accessibilityIdentifier("onboarding")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .frame(width: 22, height: 26)
            }
            .buttonStyle(.plain)
            .focused($focusedControl, equals: .close)
            .accessibilityLabel("Close PadPad")
            .accessibilityIdentifier("onboardingClose")
            .help("Close PadPad")
            Spacer()
            Text("PadPad")
                .font(.system(size: 12, weight: .medium))
                .accessibilityHidden(true)
            Spacer()
            DevelopmentBadge()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(WindowDragGesture())
        }
    }

    private func introduction(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 44 : 82, height: compact ? 44 : 82)
                .accessibilityHidden(true)

            Text("A little room\nfor a thought.")
                .font(.system(size: compact ? 26 : 30, weight: .semibold))
                .tracking(-0.8)
                .lineSpacing(-1)
                .accessibilityAddTraits(.isHeader)

            Text("Temporary drafts. Individual files.\nSave what you want to keep.")
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            primaryButton("Try your shortcut", control: .start, identifier: "onboardingStartPractice") {
                onboarding.startPractice()
            }
            .padding(.top, compact ? 0 : 5)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 400)
        .accessibilityIdentifier("onboardingIntro")
    }

    private func practice(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 18) {
            shortcutKey(compact: compact)
                .padding(.bottom, compact ? 0 : 5)

            Text(hasPracticed ? "Done" : "One gesture away.")
                .font(.system(size: compact ? 26 : 29, weight: .semibold))
                .tracking(-0.7)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(hasPracticed ? "onboardingDone" : "onboardingPracticeTitle")

            Text(practiceExplanation)
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .frame(maxWidth: 330)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboardingPracticeExplanation")

            primaryButton("Continue", control: .continueWriting, identifier: "onboardingContinue",
                          returnHint: returnCanContinue, available: canContinue, action: onContinue)
                .opacity(canContinue ? 1 : 0)
                .accessibilityHidden(!canContinue)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 400)
        .accessibilityIdentifier("onboardingPractice")
    }

    private var practiceExplanation: String {
        if hasPracticed {
            return returnCanContinue
                ? "Try it again, or press Return to start writing."
                : "Try it again, or choose Continue to start writing."
        }
        if shortcut == nil {
            return "No shortcut is set. You can add one in Settings whenever you like."
        }
        return "Use your configured shortcut\nto bring PadPad back."
    }

    private func shortcutKey(compact: Bool) -> some View {
        Text(shortcut?.description ?? "Your shortcut")
            .font(.system(size: shortcut == nil ? 15 : 25, weight: .medium))
            .tracking(shortcut == nil ? 0 : 1.5)
            .foregroundStyle(.secondary)
            .frame(minWidth: 146, minHeight: compact ? 48 : 74)
            .padding(.horizontal, 22)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
            .phaseAnimator([0.0, 2.0, 0.0], trigger: onboarding.practiceCount) { content, offset in
                content.offset(y: reduceMotion ? 0 : offset)
            } animation: { _ in
                .easeOut(duration: reduceMotion ? 0 : 0.10)
            }
            .focusable(interactions: .edit)
            .focused($focusedControl, equals: .practice)
            .accessibilityLabel(shortcut.map { "Global shortcut: \($0.description)" } ?? "No global shortcut configured")
            .accessibilityValue(hasPracticed ? "Practiced \(onboarding.practiceCount) times" : "Not yet practiced")
            .accessibilityIdentifier("onboardingShortcut")
    }

    private var footer: some View {
        HStack {
            if onboarding.stage == .intro {
                Button("What stays, what goes") { showingDetails = true }
                    .focused($focusedControl, equals: .details)
                    .accessibilityIdentifier("onboardingDetails")
                    .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Room to think. A choice to keep.")
                                .font(.headline)
                            Text("Work on individual Markdown and plain-text files, or use a temporary draft.")
                            Text(draftExplanation)
                        }
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .padding(20)
                        .frame(width: 340)
                    }
            } else {
                Button("Back") { onboarding.begin() }
                    .focused($focusedControl, equals: .back)
                    .accessibilityIdentifier("onboardingBack")
            }
            Spacer()
            Button("Skip", action: onSkip)
                .focused($focusedControl, equals: .skip)
                .accessibilityIdentifier("onboardingSkip")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(height: 28)
        .overlay {
            HStack(spacing: 5) {
                Circle().fill(onboarding.stage == .intro ? lavender : Color.secondary.opacity(0.3))
                Circle().fill(onboarding.stage == .practice ? lavender : Color.secondary.opacity(0.3))
            }
            .frame(width: 13, height: 4)
            .accessibilityLabel(onboarding.stage == .intro ? "Step 1 of 2" : "Step 2 of 2")
            .allowsHitTesting(false)
        }
    }

    private func primaryButton(_ title: String, control: Control, identifier: String,
                               returnHint: Bool = false, available: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Text(title)
                if returnHint {
                    Text("↵")
                        .font(.system(size: 15))
                        .opacity(0.8)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(OnboardingPrimaryButtonStyle(color: lavender, isFocused: focusedControl == control))
        .disabled(!available)
        .focusable(available, interactions: .edit)
        .focused($focusedControl, equals: control)
        .accessibilityLabel(title)
        .accessibilityHint(returnHint ? "Press Return to continue" : "")
        .accessibilityIdentifier(identifier)
    }

    private func handleReturn(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty, returnCanContinue else { return .ignored }
        // Releasing a shortcut modifier while holding Return must not advance on key repeat.
        guard press.phase == .down else { return .handled }
        guard !showingDetails else { return .ignored }
        switch focusedControl {
        case .close: onClose()
        case .details: showingDetails = true
        case .back: onboarding.begin()
        case .skip: onSkip()
        case .start: onboarding.startPractice()
        default:
            guard onboarding.stage == .practice, canContinue else { return .ignored }
            onContinue()
        }
        return .handled
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    let color: Color
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 34)
            .background(color.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(color.opacity(0.5), lineWidth: 2)
                        .padding(-3)
                }
            }
    }
}
