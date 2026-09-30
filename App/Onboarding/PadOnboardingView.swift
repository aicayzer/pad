import AppKit
import KeyboardShortcuts
import SwiftUI

struct PadOnboardingView: View {
    let onboarding: PadOnboarding
    let shortcut: KeyboardShortcuts.Shortcut?
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case close, next, back, skip, done
    }

    private var accentForeground: Color {
        guard let color = NSColor(settings.accentColor).usingColorSpace(.sRGB) else { return .black }
        let components = [color.redComponent, color.greenComponent, color.blueComponent].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
        return luminance > 0.179 ? .black : .white
    }
    private var hasPracticed: Bool { onboarding.practiceCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                let compact = geometry.size.height < 360
                VStack(spacing: 0) {
                    Group {
                        switch onboarding.stage {
                        case .intro: introduction(compact: compact)
                        case .practice: practice(compact: compact)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    footer
                }
                .padding(.horizontal, compact ? 18 : 24)
                .padding(.top, compact ? 4 : 12)
                .padding(.bottom, compact ? 8 : 14)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding([.horizontal, .bottom], 7)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .defaultFocus($focusedControl, .next)
        .onAppear { focusedControl = .next }
        .onChange(of: onboarding.stage) {
            focusedControl = onboarding.stage == .intro ? .next : (hasPracticed ? .done : .skip)
        }
        .onChange(of: onboarding.practiceCount) { oldCount, newCount in
            if oldCount == 0, newCount > 0 { focusedControl = .done }
        }
        .onChange(of: shortcut) {
            onboarding.resetPractice()
            if onboarding.stage == .practice { focusedControl = .skip }
        }
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
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
            .focusEffectDisabled()
            .focused($focusedControl, equals: .close)
            .background(.primary.opacity(focusedControl == .close ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel("Close PadPad")
            .accessibilityIdentifier("onboardingClose")
            .help("Close PadPad")
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

            Text("Your Pad for Thought")
                .font(.system(size: compact ? 26 : 30, weight: .semibold))
                .tracking(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboardingHeadline")

            Text("A space to write. Save what you want to keep.")
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboardingIntro")
    }

    private func practice(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 18) {
            shortcutKey(compact: compact)
                .padding(.bottom, compact ? 0 : 5)

            HStack(spacing: 8) {
                if hasPracticed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: compact ? 19 : 22))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(hasPracticed ? "You're ready." : "One gesture away.")
                    .font(.system(size: compact ? 26 : 29, weight: .semibold))
                    .tracking(-0.7)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(hasPracticed ? "onboardingDone" : "onboardingPracticeTitle")
            }

            Text(practiceExplanation)
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .frame(maxWidth: 350)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboardingPracticeExplanation")
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboardingPractice")
    }

    private var practiceExplanation: String {
        if hasPracticed { return "Try it again, or choose Done to start writing." }
        if shortcut == nil { return "No shortcut is set. Skip for now and add one in Settings." }
        return "Use your shortcut to bring PadPad back."
    }

    private func shortcutKey(compact: Bool) -> some View {
        Text(shortcut?.description ?? "No shortcut set")
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
            .accessibilityLabel(shortcut.map { "Global shortcut: \($0.description)" } ?? "No global shortcut configured")
            .accessibilityValue(hasPracticed ? "Practiced \(onboarding.practiceCount) times" : "Not yet practiced")
            .accessibilityIdentifier("onboardingShortcut")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if onboarding.stage == .practice {
                secondaryButton("Back", control: .back, identifier: "onboardingBack") {
                    onboarding.showIntroduction()
                }
            }
            Spacer()
            secondaryButton("Skip", control: .skip, identifier: "onboardingSkip", action: onSkip)
            if onboarding.stage == .intro {
                primaryButton("Next", control: .next, identifier: "onboardingStartPractice") {
                    onboarding.startPractice()
                }
            } else {
                primaryButton("Done", control: .done, identifier: "onboardingContinue",
                              available: hasPracticed, action: onContinue)
            }
        }
        .frame(height: 30)
        .overlay {
            HStack(spacing: 5) {
                Circle().fill(onboarding.stage == .intro ? settings.accentColor : Color.secondary.opacity(0.3))
                Circle().fill(onboarding.stage == .practice ? settings.accentColor : Color.secondary.opacity(0.3))
            }
            .frame(width: 13, height: 4)
            .accessibilityLabel(onboarding.stage == .intro ? "Step 1 of 2" : "Step 2 of 2")
            .allowsHitTesting(false)
        }
    }

    private func secondaryButton(_ title: String, control: Control, identifier: String,
                                 action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(OnboardingSecondaryButtonStyle(isFocused: focusedControl == control))
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused($focusedControl, equals: control)
            .accessibilityIdentifier(identifier)
    }

    private func primaryButton(_ title: String, control: Control, identifier: String,
                               available: Bool = true, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(OnboardingPrimaryButtonStyle(color: settings.accentColor, foreground: accentForeground,
                                                      isFocused: focusedControl == control))
            .disabled(!available)
            .focusable(available, interactions: .edit)
            .focusEffectDisabled()
            .focused($focusedControl, equals: control)
            .accessibilityHint(available ? "Continue to the next step" : "Try your global shortcut first")
            .accessibilityIdentifier(identifier)
    }


}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    let color: Color
    let foreground: Color
    let isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? foreground : Color.secondary)
            .frame(minWidth: 42)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(isEnabled ? color : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .brightness(isEnabled && (configuration.isPressed || isFocused) ? -0.08 : 0)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.primary.opacity(isFocused || configuration.isPressed ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
    }
}
