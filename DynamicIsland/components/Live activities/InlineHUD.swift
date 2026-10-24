/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import AppKit
import AVFoundation
import Defaults

// MARK: - Inline HUD looping .mov icon

private final class LoopingPlayerController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        self.player = AVQueuePlayer()
        self.player.isMuted = true
        self.player.actionAtItemEnd = .none
        self.looper = AVPlayerLooper(player: self.player, templateItem: item)
        self.player.play()
    }

    deinit {
        player.pause()
        looper = nil
    }
}

private struct LoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds

        view.layer?.addSublayer(layer)

        context.coordinator.attach(layer: layer, url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op; the animation loops via AVPlayerLooper.
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var controller: LoopingPlayerController?

        func attach(layer: AVPlayerLayer, url: URL) {
            controller = LoopingPlayerController(url: url)
            layer.player = controller?.player
        }
    }
}

struct AirPodsListeningModeSymbol: View {
    let mode: AirPodsListeningMode
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: mode.sfSymbol)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect)
            .frame(width: size + 2, height: size + 2)
    }
}

struct InlineHUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    
    @Default(.useColorCodedBatteryDisplay) var useColorCodedBatteryDisplay
    @Default(.useColorCodedVolumeDisplay) var useColorCodedVolumeDisplay
    @Default(.useSmoothColorGradient) var useSmoothColorGradient
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.showProgressPercentages) var showProgressPercentages
    @Default(.useCircularBluetoothBatteryIndicator) var useCircularBluetoothBatteryIndicator
    @Default(.showBluetoothBatteryPercentageText) var showBluetoothBatteryPercentageText
    @Default(.showBluetoothDeviceNameMarquee) var showBluetoothDeviceNameMarquee
    @Default(.useBluetoothHUD3DIcon) var useBluetoothHUD3DIcon
    @Default(.showCapsLockLabel) var showCapsLockLabel
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @ObservedObject var bluetoothManager = BluetoothAudioManager.shared
    
    @State private var displayName: String = ""

    /// The AirPods listening-mode HUD at its widest (the outer frame's
    /// bound): equal wings for the longest label the HUD shows.
    static func airPodsListeningModeWidth(
        closedNotchWidth: CGFloat,
        gestureProgress: CGFloat
    ) -> CGFloat {
        let wing = max(44, listeningModeTextCap + 8) + gestureProgress / 2
        return 2 * wing + closedNotchWidth
    }

    /// The glyph's 20 pt box and the 5 pt after it in the leading wing.
    static let glyphAndSpacing: CGFloat = 25
    /// The listening-mode label never takes more than this; longer labels
    /// scale down.
    static let listeningModeTextCap: CGFloat = 124
    /// `.caption.weight(.medium)`, the listening-mode label.
    static let listeningModeFont = NSFont.systemFont(
        ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
        weight: .medium
    )

    /// The two wings a HUD with text (Caps Lock, AirPods, the mic and timer
    /// events) asks for, before they are made equal: the leading glyph and
    /// name, and the trailing value. A listening-mode label is measured, so
    /// equal wings stay no wider than it needs.
    static func textWings(
        type: SneakContentType,
        listeningModeLabel: String?,
        hasBatteryLevel: Bool,
        showsDeviceName: Bool,
        circularBattery: Bool,
        showsBatteryPercentage: Bool,
        showsCapsLockLabel: Bool,
        gestureProgress: CGFloat
    ) -> (info: CGFloat, trailing: CGFloat) {
        let isListeningModeEvent = type == .bluetoothAudio && listeningModeLabel != nil

        let baseInfoWidth: CGFloat = {
            if type == .bluetoothAudio {
                if isListeningModeEvent { return 44 }
                return showsDeviceName ? 132 : 64
            }
            if type == .capsLock && !showsCapsLockLabel { return 56 }
            return 92
        }()
        let minimumInfo: CGFloat = {
            if type == .bluetoothAudio {
                if isListeningModeEvent { return 38 }
                return showsDeviceName ? 112 : 60
            }
            if type == .capsLock && !showsCapsLockLabel { return 44 }
            return 88
        }()

        let baseTrailingWidth: CGFloat = {
            if type == .bluetoothAudio {
                if let listeningModeLabel {
                    let label = min(ClosedWingE.measure(listeningModeLabel, font: listeningModeFont), listeningModeTextCap)
                    return max(64, label + 8)
                }
                if !hasBatteryLevel { return showsDeviceName ? 110 : 80 }
                if circularBattery { return showsBatteryPercentage ? 112 : 76 }
                return showsBatteryPercentage ? 128 : 100
            }
            if type == .capsLock { return showsCapsLockLabel ? 88 : 0 }
            return 92
        }()
        let minimumTrailing: CGFloat = {
            if type == .bluetoothAudio {
                if isListeningModeEvent { return 64 }
                if !hasBatteryLevel { return showsDeviceName ? 102 : 80 }
                if circularBattery { return showsBatteryPercentage ? 102 : 64 }
                return showsBatteryPercentage ? 112 : 82
            }
            if type == .capsLock { return showsCapsLockLabel ? 72 : 0 }
            return 90
        }()

        return (
            info: max(baseInfoWidth + gestureProgress / 2, minimumInfo),
            trailing: max(baseTrailingWidth + gestureProgress / 2, minimumTrailing)
        )
    }

    @Environment(\.colorSchemeContrast) private var contrast

    /// Volume, brightness and the keyboard backlight are E's line of light
    /// (docs/design/VISUAL-E.md §2.10, sheet 1.3 S11–S12).
    static func showsLevelLine(_ type: SneakContentType) -> Bool {
        type == .volume || type == .brightness || type == .backlight
    }

    /// The level wing inside the island's padding: W 62 from the camera.
    static let levelWingWidth: CGFloat = 62 - cornerRadiusInsets.closed.bottom

    var body: some View {
        if Self.showsLevelLine(type) {
            levelBody
        } else {
            otherBody
        }
    }

    /// The HUD glyph in the leading wing, the 48 pt level line in the trailing
    /// one; no number, no plate. Muted: the slashed speaker in grey over the
    /// bare track.
    private var levelBody: some View {
        let muted = type == .volume && value.isZero
        let wing = max(Self.levelWingWidth + gestureProgress / 2, DSE.Size.levelClosed)
        return HStack(spacing: 0) {
            levelGlyph(muted: muted)
                .frame(width: wing, height: ClosedWingE.content, alignment: .leading)
                .offset(x: -ClosedWingE.outset)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            LevelLine(level: Double(value), length: DSE.Size.levelClosed, isMuted: muted)
                .frame(width: wing, height: ClosedWingE.content, alignment: .trailing)
                .offset(x: ClosedWingE.outset)
        }
        .frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Type2Name(type)))
    }

    private func levelGlyph(muted: Bool) -> some View {
        Group {
            switch type {
            case .volume:
                if icon.isEmpty {
                    // Headphones while Bluetooth audio is connected, otherwise the speaker.
                    Image(systemName: bluetoothManager.isBluetoothAudioConnected ? "headphones" : SpeakerSymbol(value))
                        .symbolVariant(value > 0 ? .none : .slash)
                } else {
                    Image(systemName: icon)
                }
            case .brightness:
                Image(systemName: !icon.isEmpty ? icon : BrightnessSymbol(value))
            default:
                Image(systemName: BacklightSymbol(value))
            }
        }
        .symbolVariant(.fill)
        .contentTransition(.interpolate)
        .font(DSE.Typeface.glyphClosed)
        .foregroundStyle(muted ? DSE.Palette.secondary(contrast) : DSE.Palette.text)
    }

    private var otherBody: some View {
        let useCircularIndicator = useCircularBluetoothBatteryIndicator
        let listeningModeEvent = bluetoothManager.activeListeningModeEvent
        let listeningMode = listeningModeEvent?.mode ?? (type == .bluetoothAudio && value < 0 ? AirPodsListeningMode.fromHUDSymbol(icon) : nil)
        let isListeningModeEvent = type == .bluetoothAudio && listeningMode != nil
        let hasBatteryLevel = value > 0 && !isListeningModeEvent
        let capsLockAccentColor = capsLockTintMode.color

        // Widths stay constant whether hovered or not so HUD text/icons do
        // not slide toward the notch edges when the user moves over it.
        let wings = Self.textWings(
            type: type,
            listeningModeLabel: listeningMode?.displayName,
            hasBatteryLevel: hasBatteryLevel,
            showsDeviceName: showBluetoothDeviceNameMarquee,
            circularBattery: useCircularIndicator,
            showsBatteryPercentage: showBluetoothBatteryPercentageText,
            showsCapsLockLabel: showCapsLockLabel,
            gestureProgress: gestureProgress
        )
        // Equal wings (E §2.1): the island is centred on the camera, so a
        // trailing wing wider than the leading one slid the black middle off
        // the camera and the text after it in under the camera.
        let geometry = ClosedWingGeometry.equalWings(
            closedNotchWidth: vm.closedNotchSize.width,
            leading: wings.info,
            trailing: wings.trailing
        )
        let infoWidth = geometry.leadingWing
        let trailingWidth = geometry.trailingWing

        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Group {
                    switch (type) {
                        case .volume:
                            if icon.isEmpty {
                                // Show headphone icon if Bluetooth audio is connected, otherwise speaker
                                let baseIcon = bluetoothManager.isBluetoothAudioConnected ? "headphones" : SpeakerSymbol(value)
                                Image(systemName: baseIcon)
                                    .contentTransition(.interpolate)
                                    .symbolVariant(value > 0 ? .none : .slash)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            } else {
                                Image(systemName: icon)
                                    .contentTransition(.interpolate)
                                    .opacity(value.isZero ? 0.6 : 1)
                                    .scaleEffect(value.isZero ? 0.85 : 1)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            }
                        case .brightness:
                            Image(systemName: !icon.isEmpty ? icon : BrightnessSymbol(value))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .backlight:
                            Image(systemName: BacklightSymbol(value))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .mic:
                            Image(systemName: "mic")
                                .symbolRenderingMode(.hierarchical)
                                .symbolVariant(value > 0 ? .none : .slash)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .timer:
                            Image(systemName: "timer")
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .bluetoothAudio:
                            if let listeningMode {
                                AirPodsListeningModeSymbol(mode: listeningMode)
                                    .contentTransition(.interpolate)
                                    .frame(width: 20, height: 15, alignment: .center)
                            } else if useBluetoothHUD3DIcon,
                               let deviceType = bluetoothManager.lastConnectedDevice?.deviceType,
                               let url = deviceType.inlineHUDAnimationURL {
                                LoopingVideoIcon(url: url, size: CGSize(width: 20, height: 20))
                                    .frame(width: 20, height: 20, alignment: .center)
                            } else {
                                Image(systemName: icon.isEmpty ? "dot.radiowaves.left.and.right" : icon)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.interpolate)
                                    .frame(width: 20, height: 15, alignment: .center)
                            }
                        case .capsLock:
                            Image(systemName: "capslock.fill")
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                                .foregroundStyle(capsLockAccentColor)
                        default:
                            EmptyView()
                    }
                }
                .foregroundStyle(.white)
                .symbolVariant(.fill)
                
                // Use marquee text for device names to handle long names
                if type == .bluetoothAudio {
                    if isListeningModeEvent {
                        EmptyView()
                    } else if showBluetoothDeviceNameMarquee {
                        MarqueeText(
                            $displayName,
                            font: .system(size: 13, weight: .medium),
                            nsFont: .body,
                            textColor: .white,
                            minDuration: 0.2,
                            // The glyph and its spacing share the wing.
                            frameWidth: max(0, infoWidth - Self.glyphAndSpacing)
                        )
                    }
                } else if type != .capsLock {
                    Text(Type2Name(type))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: infoWidth, height: vm.notchSize.height - (hoverAnimation ? 0 : 12), alignment: .leading)
            
            Rectangle()
                .fill(.black)
                .frame(width: geometry.middle)
            
            HStack {
                if (type == .mic) {
                    Text(value.isZero ? "muted" : "unmuted")
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentTransition(.interpolate)
                } else if (type == .timer) {
                    Text(TimerManager.shared.formattedRemainingTime())
                        .foregroundStyle(TimerManager.shared.timerColor)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentTransition(.interpolate)
                } else if (type == .capsLock) {
                    if showCapsLockLabel {
                        Text("Caps Lock")
                            .foregroundStyle(capsLockAccentColor)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .contentTransition(.interpolate)
                    }
                } else if (type == .bluetoothAudio) {
                    if let listeningMode {
                        let listeningModeTextWidth = Self.listeningModeTextCap

                        // Render every mode label with a trailing-aligned Text.
                        // The previous MarqueeText path is `.leading`-aligned
                        // internally, so the longer modes (Noise Cancellation /
                        // Adaptive Audio / Conversation Awareness) hugged the notch
                        // edge and were clipped behind it — only the short,
                        // trailing-aligned modes (Transparency / Off) stayed
                        // visible. A scaling Text keeps every mode on screen.
                        Text(listeningMode.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .truncationMode(.tail)
                            .allowsTightening(true)
                            .frame(
                                width: max(0, min(trailingWidth - 8, listeningModeTextWidth)),
                                alignment: .trailing
                            )
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else if hasBatteryLevel {
                        let indicatorSpacing: CGFloat = {
                            if useCircularIndicator {
                                return showBluetoothBatteryPercentageText ? 8 : 2
                            }
                            return showBluetoothBatteryPercentageText ? 6 : 4
                        }()

                        HStack(spacing: indicatorSpacing) {
                            if useCircularIndicator {
                                CircularBatteryIndicator(
                                    value: value,
                                    useColorCoding: useColorCodedBatteryDisplay && progressBarStyle != .segmented,
                                    smoothGradient: useSmoothColorGradient
                                )
                                .allowsHitTesting(false)
                            } else {
                                LinearBatteryIndicator(
                                    value: value,
                                    useColorCoding: useColorCodedBatteryDisplay && progressBarStyle != .segmented,
                                    smoothGradient: useSmoothColorGradient
                                )
                                .allowsHitTesting(false)
                            }

                            if showBluetoothBatteryPercentageText {
                                Text("\(Int(value * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    // Volume and brightness displays
                    Group {
                        if type == .volume {
                            Group {
                                if value.isZero {
                                    Text("muted")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.gray)
                                        .lineLimit(1)
                                        .allowsTightening(true)
                                        .multilineTextAlignment(.trailing)
                                        .contentTransition(.numericText())
                                } else {
                                    HStack(spacing: 6) {
                                        DraggableProgressBar(value: $value, colorMode: .volume)
                                        PercentageLabel(value: value, isVisible: showProgressPercentages)
                                    }
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .animation(.smooth(duration: 0.2), value: value.isZero)
                        } else {
                            HStack(spacing: 6) {
                                DraggableProgressBar(value: $value)
                                PercentageLabel(value: value, isVisible: showProgressPercentages)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.trailing, trailingWidth > 0 ? 4 : 0)
            .frame(width: trailingWidth, height: vm.closedNotchSize.height - (hoverAnimation ? 0 : 12), alignment: .center)
        }
        .frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
        .onAppear {
            displayName = Type2Name(type)
        }
        .onChange(of: type) { _, _ in
            displayName = Type2Name(type)
        }
        .onChange(of: bluetoothManager.lastConnectedDevice?.name) { _, _ in
            displayName = Type2Name(type)
        }
    }
    
    private struct CircularBatteryIndicator: View {
        let value: CGFloat
        let useColorCoding: Bool
        let smoothGradient: Bool

        private var clampedValue: CGFloat {
            min(max(value, 0), 1)
        }

        private var indicatorColor: Color {
            if useColorCoding {
                return ColorCodedProgressBar.paletteColor(for: clampedValue, mode: .battery, smoothGradient: smoothGradient)
            }
            return .white
        }

        var body: some View {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: max(clampedValue, 0.015))
                    .rotation(.degrees(-90))
                    .stroke(indicatorColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            .frame(width: 16, height: 16)
            .animation(.smooth(duration: 0.18), value: clampedValue)
        }
    }

    private struct LinearBatteryIndicator: View {
        let value: CGFloat
        let useColorCoding: Bool
        let smoothGradient: Bool

        private let trackWidth: CGFloat = 54
        private let trackHeight: CGFloat = 6

        private var clampedValue: CGFloat {
            min(max(value, 0), 1)
        }

        private var fillColor: Color {
            if useColorCoding {
                return ColorCodedProgressBar.paletteColor(for: clampedValue, mode: .battery, smoothGradient: smoothGradient)
            }
            return .white
        }

        var body: some View {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: trackWidth, height: trackHeight)

                Capsule()
                    .fill(fillColor)
                    .frame(width: trackWidth * clampedValue, height: trackHeight)
            }
            .frame(width: trackWidth, height: trackHeight)
            .animation(.smooth(duration: 0.18), value: clampedValue)
        }
    }

    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
    
    func BrightnessSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0...0.6:
                return "sun.min"
            case 0.6...1:
                return "sun.max"
            default:
                return "sun.min"
        }
    }

    func BacklightSymbol(_ value: CGFloat) -> String {
        if value >= 0.5 {
            return "light.max"
        }
        return "light.min"
    }
    
    func Type2Name(_ type: SneakContentType) -> String {
        switch(type) {
            case .volume:
                return String(localized: "Volume")
            case .brightness:
                return String(localized: "Brightness")
            case .backlight:
                return String(localized: "Backlight")
            case .mic:
                return String(localized: "Mic")
            case .bluetoothAudio:
                return BluetoothAudioManager.shared.lastConnectedDevice?.name ?? "Bluetooth"
            case .capsLock:
                return String(localized: "Caps Lock")
            default:
                return ""
        }
    }
}

#Preview {
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(DynamicIslandViewModel())
}
