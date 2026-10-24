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
import Defaults

struct LottieAnimationView: View {
    /// Plays while the music does; holds its frame on pause.
    var isPlaying: Bool = true
    @Default(.selectedVisualizer) var selectedVisualizer

    private static let defaultSource = AnimationSource.lottieURL(URL(string: "https://assets9.lottiefiles.com/packages/lf20_mniampqn.json")!)

    var body: some View {
        if let visualizer = selectedVisualizer {
            PausableLottieView(source: .lottieURL(visualizer.url), speed: visualizer.speed, isPlaying: isPlaying)
                .id(visualizer.url)
        } else {
            PausableLottieView(source: Self.defaultSource, isPlaying: isPlaying)
        }
    }
}

#Preview {
    LottieAnimationView()
}
