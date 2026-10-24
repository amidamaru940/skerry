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
import Lottie
import Defaults

/// When the idle animation plays. It is shown exactly while the closed
/// island has nothing else to show, so a loop that never stops kept
/// WindowServer redrawing the island at the display's refresh rate for as
/// long as the Mac sat idle (a 1920-point vector composition, recomposited
/// with the island's shadow every frame). It now plays for a while when
/// something happens -- the island goes idle, the person comes back to the
/// Mac, the pointer rests on the island -- and holds its frame in between.
enum IdleAnimationPlayback {
    /// How long one performance lasts: one pass of the bundled animations.
    static let performance: TimeInterval = 8

    /// Whether a change of `present` / `hovering` starts a performance.
    /// `firstLook` is true until the view has played once since it appeared
    /// or since the person was last away.
    static func plays(present: Bool, hovering: Bool, firstLook: Bool) -> Bool {
        present && (hovering || firstLook)
    }
}

struct IdleAnimationView: View {
    /// The pointer is over the island: the animation plays again.
    var isHovering: Bool = false

    @Default(.selectedIdleAnimation) var selectedAnimation
    @Default(.animationTransformOverrides) var overrides
    @ObservedObject private var gate = ActivityGate.shared

    var body: some View {
        Group {
            if let animation = selectedAnimation {
                AnimationContentView(animation: animation, isHovering: isHovering, isPresent: gate.state.userPresent)
                    .id("\(animation.id)-\(overrides[animation.id.uuidString]?.hashValue ?? 0)")  // Force recreation when override changes
            } else {
                // No animation selected
                EmptyView()
            }
        }
    }
}

/// Internal view that renders the actual animation content
private struct AnimationContentView: View {
    let animation: CustomIdleAnimation
    let isHovering: Bool
    let isPresent: Bool

    @State private var isPlaying = false
    @State private var hasPlayedSinceAppear = false

    private struct Trigger: Equatable {
        let present: Bool
        let hovering: Bool
    }

    var body: some View {
        let config = animation.getTransformConfig()

        PausableLottieView(
            source: animation.source,
            speed: animation.speed,
            loopMode: config.loopMode.lottieLoopMode,
            isPlaying: isPlaying
        )
        .id(animation.id)  // Force reload when animation changes
        .frame(
            width: config.cropWidth * config.scale,
            height: config.cropHeight * config.scale
        )
        .offset(x: config.offsetX, y: config.offsetY)
        .rotationEffect(.degrees(config.rotation))
        .opacity(config.opacity)
        .padding(.bottom, config.paddingBottom)
        .clipped()
        .task(id: Trigger(present: isPresent, hovering: isHovering)) {
            guard IdleAnimationPlayback.plays(present: isPresent, hovering: isHovering, firstLook: !hasPlayedSinceAppear) else {
                // Away: the next return plays it again.
                if !isPresent { hasPlayedSinceAppear = false }
                isPlaying = false
                return
            }
            hasPlayedSinceAppear = true
            isPlaying = true
            try? await Task.sleep(for: .seconds(IdleAnimationPlayback.performance))
            isPlaying = false
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black
        IdleAnimationView()
    }
    .frame(width: 100, height: 50)
}
