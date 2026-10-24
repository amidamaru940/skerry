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
import Lottie

/// A Lottie animation that plays only while `isPlaying` and otherwise holds
/// its frame, so it draws nothing in between. LottieUI's view, used for
/// these before, could only be told to loop, and a looping animation keeps
/// WindowServer redrawing at the display's refresh rate.
///
/// `Lottie.` is spelled out: the app has a SwiftUI view of its own named
/// `LottieAnimationView` (the music visualizer).
struct PausableLottieView: NSViewRepresentable {
    let source: AnimationSource
    var speed: CGFloat = 1
    var loopMode: LottieLoopMode = .loop
    let isPlaying: Bool

    final class Coordinator {
        weak var view: Lottie.LottieAnimationView?
        var wantsPlaying = false

        func applyPlayback() {
            guard let view else { return }
            if wantsPlaying {
                guard !view.isAnimationPlaying else { return }
                // A "Play Once" that has finished starts over.
                if view.currentProgress >= 1 { view.currentProgress = 0 }
                view.play()
            } else if view.isAnimationPlaying {
                // Holds the current frame: nothing is drawn until the next play.
                view.pause()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> Lottie.LottieAnimationView {
        let coordinator = context.coordinator
        let view: Lottie.LottieAnimationView
        switch source {
        case .lottieFile(let url):
            view = Lottie.LottieAnimationView(animation: LottieAnimation.filepath(url.path))
        case .lottieURL(let url):
            // Loaded in the background; plays on arrival if it is meant to.
            view = Lottie.LottieAnimationView(url: url, closure: { [weak coordinator] _ in
                coordinator?.applyPlayback()
            })
        }
        view.contentMode = .scaleAspectFit
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        coordinator.view = view
        return view
    }

    func updateNSView(_ view: Lottie.LottieAnimationView, context: Context) {
        if view.animationSpeed != speed { view.animationSpeed = speed }
        if view.loopMode != loopMode { view.loopMode = loopMode }
        context.coordinator.wantsPlaying = isPlaying
        context.coordinator.applyPlayback()
    }

    static func dismantleNSView(_ view: Lottie.LottieAnimationView, coordinator: Coordinator) {
        view.stop()
    }
}
