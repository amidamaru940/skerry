/*
 * Skerry — a fork of Atoll (DynamicIsland)
 * Copyright (C) 2026 amidamaru940 and Skerry contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import ApplicationServices
import Defaults
import SwiftUI

/// Onboarding in three steps, without profiles (docs/PLAN-DESIGN.md §3.9):
/// hello, what to turn on, the one permission. Back and Skip everywhere;
/// quitting half way resumes at the same step next time.
enum OnboardingFlow {
    enum Step: String, CaseIterable {
        case hello, features, permission

        var next: Step? {
            switch self {
            case .hello: return .features
            case .features: return .permission
            case .permission: return nil
            }
        }

        var previous: Step? {
            switch self {
            case .hello: return nil
            case .features: return .hello
            case .permission: return .features
            }
        }

        var number: Int { (Step.allCases.firstIndex(of: self) ?? 0) + 1 }
    }

    /// Where to start: the step the user left at, or the first one.
    static func resumeStep(saved: String?) -> Step {
        saved.flatMap(Step.init(rawValue:)) ?? .hello
    }

    /// Whether the onboarding still has to be shown: on the first launch,
    /// or to resume a step left half way. Whoever went through the old
    /// onboarding (first launch behind them, no step saved) is not asked again.
    static func isNeeded(completed: Bool, firstLaunch: Bool, savedStep: String?) -> Bool {
        !completed && (firstLaunch || savedStep != nil)
    }

    /// «Continue» on step two with Screenshots on is the person asking for
    /// screenshots: their folder is looked at then, and macOS may ask for
    /// it, not at launch (docs/design/REDESIGN-SPEC.md §5.8). Back and Skip
    /// do not count.
    static func startsScreenshots(leaving step: Step, for target: Step, screenshotsOn: Bool) -> Bool {
        screenshotsOn && step == .features && target == step.next
    }

    /// The things step two offers. Nothing that talks to the network is in
    /// the list.
    struct Feature: Identifiable, Equatable {
        let id: String
        let symbol: String
        let title: String.LocalizationValue
        let detail: String.LocalizationValue
        let permission: String.LocalizationValue
        let key: Defaults.Key<Bool>

        static func == (lhs: Feature, rhs: Feature) -> Bool { lhs.id == rhs.id }
    }

    static let features: [Feature] = [
        Feature(id: "clipboard", symbol: "doc.on.clipboard", title: "Clipboard",
                detail: "Everything you copy, to paste again later.",
                permission: "No permission needed.", key: .enableClipboardManager),
        Feature(id: "screenshots", symbol: "camera.viewfinder", title: "Screenshots",
                detail: "New screenshots, saved or taken to the clipboard, gather in batches, ready to paste into a chat.",
                permission: "macOS may ask for the folder they are saved in.", key: .enableScreenshotShelf),
        Feature(id: "music", symbol: "music.note", title: "Music",
                detail: "What is playing, with play, pause and skip.",
                permission: "macOS asks before Skerry controls Spotify or Music.", key: .showStandardMediaControls),
        Feature(id: "calendar", symbol: "calendar", title: "Calendar",
                detail: "Your next two or three events beside the player.",
                permission: "Asks for calendar access when you turn it on in the island.", key: .showCalendar),
        Feature(id: "terminal", symbol: "apple.terminal", title: "Terminal",
                detail: "A terminal that drops down from the notch.",
                permission: "No permission needed.", key: .enableTerminalFeature),
    ]

    /// A switch on step two. Screenshots are one feature: their switch also
    /// collects the ones taken to the clipboard (⌃⇧⌘4), which were left out
    /// on a fresh install (owner, 22.10).
    static func setFeature(_ feature: Feature, on: Bool) {
        if feature.key.name == Defaults.Keys.enableScreenshotShelf.name {
            ScreenshotFeature.setEnabled(on)
        } else {
            Defaults[feature.key] = on
        }
    }

    /// Settings the old profiles applied whatever was picked; kept, without
    /// the profiles.
    static func applyCommonDefaults() {
        Defaults[.menubarIcon] = true
        Defaults[.enableLyrics] = false
        Defaults[.islandLayout] = .standard
        if let screen = NSScreen.main {
            Defaults[.externalDisplayStyle] = screen.safeAreaInsets.top > 0 ? .notch : .dynamicIsland
        }
    }
}

/// The onboarding window's content.
struct OnboardingFlowView: View {
    let onFinish: () -> Void
    @State private var step: OnboardingFlow.Step = OnboardingFlow.resumeStep(saved: Defaults[.onboardingStep])
    @State private var isTrusted = AXIsProcessTrusted()
    @State private var trustPoll: Timer?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(format: String(localized: "Step %lld of %lld"), step.number, OnboardingFlow.Step.allCases.count))
                    .font(DS.Typeface.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Skip"), action: finish)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)

            Group {
                switch step {
                case .hello: hello
                case .features: features
                case .permission: permission
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .transition(.opacity)

            HStack {
                if let previous = step.previous {
                    Button(String(localized: "Back")) { go(to: previous) }
                        .controlSize(.large)
                }
                Spacer()
                if let next = step.next {
                    Button(step == .hello ? String(localized: "Get started") : String(localized: "Continue")) { go(to: next) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(String(localized: "Done"), action: finish)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(width: 440, height: 560)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .onAppear { Defaults[.onboardingStep] = step.rawValue }
        .onDisappear { trustPoll?.invalidate() }
    }

    // MARK: Steps

    private var hello: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image("logo2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
            Text("Skerry")
                .font(.system(size: 28, weight: .semibold))
            VStack(alignment: .leading, spacing: 12) {
                helloLine("doc.on.clipboard", "Your clipboard and screenshots, at the notch.")
                helloLine("music.note", "What is playing and what is next, at a glance.")
                helloLine("lock.shield", "Nothing leaves your Mac unless you turn it on.")
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    private func helloLine(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What to turn on")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 18)
            Text("You can change all of this later in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ForEach(OnboardingFlow.features) { feature in
                    FeatureToggleRow(feature: feature)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("One permission")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 18)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Lets Skerry paste from the clipboard in one click and makes the keyboard shortcuts work. It does not read your screen or your typing.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.primary.opacity(0.06)))

            if isTrusted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DS.Palette.on)
                    .font(.system(size: 14, weight: .semibold))
            } else {
                Button(String(localized: "Open System Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.large)
                Text("Turn on Skerry in the list, then come back. You can also do it later.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .onAppear(perform: startTrustPoll)
        .onDisappear { trustPoll?.invalidate() }
    }

    // MARK: Moving

    private func go(to target: OnboardingFlow.Step) {
        if OnboardingFlow.startsScreenshots(leaving: step, for: target, screenshotsOn: Defaults[.enableScreenshotShelf]) {
            ScreenshotShelfManager.shared.startOnFirstUse()
        }
        withAnimation(DS.spring) { step = target }
        Defaults[.onboardingStep] = target.rawValue
    }

    private func finish() {
        trustPoll?.invalidate()
        OnboardingFlow.applyCommonDefaults()
        Defaults[.onboardingCompleted] = true
        Defaults[.onboardingStep] = nil
        onFinish()
    }

    /// The tick appears as soon as the permission is given in System Settings.
    private func startTrustPoll() {
        trustPoll?.invalidate()
        trustPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let trusted = AXIsProcessTrusted()
            Task { @MainActor in
                if trusted != isTrusted { withAnimation(DS.spring) { isTrusted = trusted } }
            }
        }
    }
}

private struct FeatureToggleRow: View {
    let feature: OnboardingFlow.Feature
    @State private var isOn: Bool

    init(feature: OnboardingFlow.Feature) {
        self.feature = feature
        _isOn = State(initialValue: Defaults[feature.key])
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOn ? DS.Palette.accent : Color.secondary)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: feature.title))
                    .font(.system(size: 14, weight: .semibold))
                Text(String(localized: feature.detail))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: feature.permission))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: isOn) { _, value in OnboardingFlow.setFeature(feature, on: value) }
        }
    }
}
