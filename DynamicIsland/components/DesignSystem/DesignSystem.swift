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

import SwiftUI

/// Skerry's one design system (docs/PLAN-DESIGN.md §2): colours, type,
/// radii, spacing, motion and the small components every screen is built
/// from. Screens take their look from here only, so the whole app reads as
/// one piece.
enum DS {
    enum Palette {
        static let island = Color.black
        static let surface = Color(rgb: 0x161618)
        static let card = Color(rgb: 0x1F1F22)
        static let raised = Color(rgb: 0x2A2A2E)
        static let control = Color(rgb: 0x3A3A3F)
        static let hoverFill = Color.white.opacity(0.08)
        static let selectedFill = Color.white.opacity(0.14)
        static let separator = Color.white.opacity(0.08)

        static let text = Color(rgb: 0xF5F5F7)
        static let textSecondary = Color(rgb: 0xA1A1A6)
        /// The dimmest grey that still reads as small text on black (4.5:1).
        static let textTertiary = Color(rgb: 0x8E8E93)

        /// Apple blue: the single accent, for the main action and selection.
        static let accent = Color(rgb: 0x0A84FF)
        static let on = Color(rgb: 0x30D158)
        static let attention = Color(rgb: 0xFFD60A)
        static let paused = Color(rgb: 0xFF9F0A)
        static let danger = Color(rgb: 0xFF453A)
    }

    enum Radius {
        static let chip: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 10
        static let panel: CGFloat = 14
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Typeface {
        static let caption = Font.system(size: 11)
        static let body = Font.system(size: 13)
        static let bodyEmphasis = Font.system(size: 13, weight: .semibold)
        static let title = Font.system(size: 15, weight: .semibold)
        static let large = Font.system(size: 20, weight: .semibold)
    }

    /// Every popover of the island is this wide.
    static let panelWidth: CGFloat = 280

    /// SF Symbols in the island: 15 pt glyphs in 28 pt targets.
    static let iconSize: CGFloat = 15
    static let hitTarget: CGFloat = 28

    /// Moves without overshoot; hover changes are quicker still.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 1)
    static let hover = Animation.easeOut(duration: 0.15)
    /// Controls that are there but cannot act just now, such as the player's
    /// while a video holds the system's playback controls.
    static let heldControlsOpacity: Double = 0.35
}

extension Color {
    /// `Color(rgb: 0x0A84FF)`.
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Buttons

/// The three kinds of text button: one main action per screen (filled with
/// the accent), ordinary ones and quiet ones.
struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive }
    var kind: Kind = .secondary
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .primary ? DS.Typeface.bodyEmphasis : .system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 8 : 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(background))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(DS.hover, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return DS.Palette.text
        case .quiet: return DS.Palette.textSecondary
        case .destructive: return DS.Palette.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return DS.Palette.accent
        case .secondary: return DS.Palette.raised
        case .quiet, .destructive: return .clear
        }
    }
}

/// A glyph-only button: 28 pt target, hover and selected fills, a tooltip
/// and an accessibility label (an icon alone says nothing to VoiceOver).
struct DSIconButton: View {
    let symbol: String
    let label: String
    var isSelected = false
    var width: CGFloat = DS.hitTarget
    var tint: Color? = nil
    var dot: Color? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: DS.iconSize, weight: .medium))
                .foregroundStyle(tint ?? (isSelected || isHovering ? DS.Palette.text : DS.Palette.textSecondary))
                .frame(width: width, height: DS.hitTarget)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.control + 1, style: .continuous)
                        .fill(isSelected ? DS.Palette.selectedFill : (isHovering ? DS.Palette.hoverFill : .clear))
                )
                .overlay(alignment: .topTrailing) {
                    if let dot {
                        DSDot(color: dot).padding(.top, 5).padding(.trailing, 6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.hover) { isHovering = hovering } }
        .help(label)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "There is something new here": a 6 pt dot that always fits inside its
/// button, instead of a count that gets cut off.
struct DSDot: View {
    var color: Color = DS.Palette.accent

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

// MARK: - Segmented control

/// A few mutually exclusive choices in one quiet control, instead of a row
/// of separate chips.
struct DSSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isOn = option.value == selection
                Button {
                    withAnimation(DS.spring) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isOn ? DS.Palette.text : DS.Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(isOn ? DS.Palette.control : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.card))
    }
}

// MARK: - Capsules, toasts, empty states

/// A small rounded capsule for a live state (Keep Awake time, recording,
/// low battery).
struct DSStatusCapsule<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) { content() }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(DS.Palette.card))
    }
}

/// Feedback after an action ("Copied", "Pasted into Claude · 3").
struct DSToastView: View {
    enum Tone { case done, warning }
    let text: String
    var tone: Tone = .done

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tone == .done ? "checkmark" : "exclamationmark.triangle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tone == .done ? DS.Palette.on : DS.Palette.attention)
            Text(text)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.text)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 30)
        .background(Capsule().fill(DS.Palette.card))
        .accessibilityElement(children: .combine)
    }
}

/// What a screen shows when there is nothing to show: a glyph, one line,
/// an optional explanation and at most one action.
struct DSEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// One line at the top instead of a centred block that fills the space:
    /// for places that shrink to their content.
    var inline = false

    var body: some View {
        if inline {
            inlineBody
        } else {
            stackedBody
        }
    }

    private var inlineBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
            (Text(title).font(DS.Typeface.bodyEmphasis).foregroundColor(DS.Palette.text)
                + Text(message.map { "  " + $0 } ?? "").font(.system(size: 12)).foregroundColor(DS.Palette.textSecondary))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Spacer(minLength: 8)
                Button(actionTitle, action: action)
                    .buttonStyle(DSButtonStyle(kind: .secondary, height: 24))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private var stackedBody: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
            Text(title)
                .font(DS.Typeface.title)
                .foregroundStyle(DS.Palette.text)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DSButtonStyle(kind: .secondary))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
