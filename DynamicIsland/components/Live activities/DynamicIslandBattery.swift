/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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
import Defaults

// The header's battery icon, its popover and the views behind them
// (`BatteryView`, `BatteryMenuView`, `DynamicIslandBatteryView`) went with
// the new header in D1; the low-battery capsule took their place.

private struct BatteryTemporaryHUDMetrics {
    let width: CGFloat
    let height: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat
}

private extension BatteryTemporaryHUDKind {
    func metrics(
        style: BatteryNotificationStyle,
        closedNotchWidth: CGFloat,
        baseHeight: CGFloat
    ) -> BatteryTemporaryHUDMetrics {
        let compactBaseRadius = max(baseHeight / 2, 16)
        let compactTopRadius = max(12, compactBaseRadius - 4)

        switch (self, style) {
        case (.charging, _), (.lowBattery, .compact), (.fullBattery, .compact):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 180,
                height: baseHeight,
                topRadius: compactTopRadius,
                bottomRadius: compactBaseRadius
            )
        case (.lowBattery, .standard):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 150,
                height: baseHeight + 75,
                topRadius: 22,
                bottomRadius: 40
            )
        case (.fullBattery, .standard):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 140,
                height: baseHeight + 70,
                topRadius: 18,
                bottomRadius: 36
            )
        }
    }
}

private struct BatteryCompactStatusRow: View {
    let title: String
    let batteryLevel: Int
    let tint: Color

    var body: some View {
        HStack {
            Text(verbatim: title)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            HStack(spacing: 6) {
                Text("\(batteryLevel)%")
                    .font(.system(size: 14))
                    .foregroundColor(tint)

                HStack(spacing: 1.5) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.3))

                        GeometryReader { geo in
                            let clamped = max(0, min(batteryLevel, 100))
                            let width = CGFloat(clamped) / 100 * geo.size.width
                            Rectangle()
                                .fill(tint.gradient)
                                .frame(width: max(0, width))
                        }
                    }
                    .frame(width: 28, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(batteryLevel == 100 ? tint.gradient : tint.opacity(0.3).gradient)
                        .frame(width: 2, height: 6)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct BatteryTemporaryActivityView: View {
    let kind: BatteryTemporaryHUDKind
    let batteryLevel: Int
    let isLowPowerMode: Bool
    let closedNotchWidth: CGFloat
    let baseHeight: CGFloat
    let isDynamicIslandMode: Bool
    let topCornerRadius: CGFloat
    @Default(.lowBatteryHUDStyle) var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) var fullBatteryHUDStyle
    var styleOverride: BatteryNotificationStyle? = nil

    @State private var pulse = false
    @State private var showBatteryIndicator = false
    @State private var changeBatteryIndicator = true

    private var style: BatteryNotificationStyle {
        if kind == .charging {
            return .compact
        }
        if let styleOverride {
            return styleOverride
        }
        switch kind {
        case .charging:
            return .compact
        case .lowBattery:
            return lowBatteryHUDStyle
        case .fullBattery:
            return fullBatteryHUDStyle
        }
    }

    private var metrics: BatteryTemporaryHUDMetrics {
        kind.metrics(
            style: style,
            closedNotchWidth: closedNotchWidth,
            baseHeight: baseHeight
        )
    }

    private var batteryTint: Color {
        switch kind {
        case .charging:
            if isLowPowerMode {
                return .yellow
            } else if batteryLevel <= 20 {
                return .red
            }
            return .green
        case .lowBattery:
            return isLowPowerMode ? .yellow : .red
        case .fullBattery:
            return isLowPowerMode ? .yellow : .green
        }
    }


    private var surfaceShape: AnyShape {
        if isDynamicIslandMode {
            return AnyShape(DynamicIslandPillShape(cornerRadius: dynamicIslandPillCornerRadiusInsets.opened))
        } else {
            return AnyShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: metrics.bottomRadius))
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .bottom)
        .clipShape(surfaceShape)
        .onAppear(perform: prepareAnimations)
    }

    @ViewBuilder
    private var content: some View {
        if style == .compact {
            BatteryCompactStatusRow(
                title: compactTitle,
                batteryLevel: batteryLevel,
                tint: batteryTint
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack {
                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: kind == .lowBattery ? 2 : 3) {
                        standardTitle
                        standardDescription
                    }

                    Spacer()

                    standardIndicator
                }
                .padding(.leading, kind == .lowBattery ? 40 : 35)
                .padding(.trailing, kind == .lowBattery ? 45 : 40)
                .padding(.bottom, 20)
            }
        }
    }

    private var compactTitle: String {
        Self.compactTitle(for: kind, batteryLevel: batteryLevel)
    }

    static func compactTitle(for kind: BatteryTemporaryHUDKind, batteryLevel: Int) -> String {
        switch kind {
        case .charging:
            // Plugged in when already full: nothing is charging.
            return batteryLevel >= 100 ? String(localized: "Fully charged") : String(localized: "Charging")
        case .lowBattery:
            return String(localized: "Low Battery")
        case .fullBattery:
            return String(localized: "Full Battery")
        }
    }

    @ViewBuilder
    private var standardTitle: some View {
        HStack(spacing: 5) {
            Text(verbatim: kind == .lowBattery ? String(localized: "Battery Low") : String(localized: "Full Battery"))
                .font(.system(size: kind == .lowBattery ? 13 : 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            Text("\(batteryLevel)%")
                .font(.system(size: kind == .lowBattery ? 12 : 13, weight: .semibold))
                .foregroundStyle(batteryTint)
        }
    }

    @ViewBuilder
    private var standardDescription: some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            if isLowPowerMode {
                (
                    Text(verbatim: String(localized: "Low Power Mode enabled"))
                        .foregroundColor(.yellow)
                        .font(.system(size: 10, weight: .medium))
                    +
                    Text(verbatim: String(localized: ", it is recommended to charge it."))
                        .foregroundColor(.gray.opacity(0.6))
                        .font(.system(size: 10, weight: .medium))
                )
            } else {
                Text(verbatim: String(localized: "Turn on Low Power Mode or it\nis recommended to charge it."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineLimit(2)
            }
        case .fullBattery:
            Text(verbatim: String(localized: "Your Mac is fully charged."))
                .font(.system(size: 10))
                .foregroundStyle(.gray.opacity(0.6))
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var standardIndicator: some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            if isLowPowerMode {
                yellowLowIndicator
            } else {
                redLowIndicator
            }
        case .fullBattery:
            if showBatteryIndicator {
                if isLowPowerMode {
                    yellowFullIndicator
                        .transition(.opacity.combined(with: .scale))
                } else {
                    greenFullIndicator
                        .transition(.opacity.combined(with: .scale))
                }
            } else {
                magSafeIndicator
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private var redLowIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.red.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.opacity(0.4))
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.gradient)
                .frame(width: 8, height: 14)
                .opacity(pulse ? 1 : 0.3)
                .offset(x: -15)

            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.red.opacity(0.9), lineWidth: 1.5)
                .frame(width: pulse ? 8 : 30, height: pulse ? 14 : 32)
                .offset(x: -15)
                .opacity(pulse ? 0.3 : 1)
        }
    }

    private var yellowLowIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.yellow.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(.yellow.gradient)
                .frame(width: 8, height: 14)
                .offset(x: -15)
        }
    }

    private var greenFullIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.green.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    )

                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private var yellowFullIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.yellow.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.yellow.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    )

                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private var magSafeIndicator: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.gray.opacity(0.15))
                .frame(width: 30, height: 5)

            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.2).gradient)
                    .frame(width: 30, height: 40)

                Circle()
                    .fill(changeBatteryIndicator ? .orange : .green)
                    .shadow(color: changeBatteryIndicator ? .orange : .green, radius: 5)
                    .frame(width: 5, height: 5)
            }

            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(width: 3, height: 32)
        }
    }

    private func prepareAnimations() {
        pulse = false
        showBatteryIndicator = kind == .fullBattery && style == .standard
        changeBatteryIndicator = true

        guard style == .standard else { return }

        switch kind {
        case .charging:
            break
        case .lowBattery:
            if !isLowPowerMode {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        case .fullBattery:
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring(duration: 0.4)) {
                    showBatteryIndicator = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.spring(duration: 0.2)) {
                    changeBatteryIndicator = false
                }
            }
        }
    }
}
