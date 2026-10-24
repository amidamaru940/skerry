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

struct SpinningCircleDownloadView: View {
    /// A download that has stopped growing holds the spinner still.
    var isSpinning: Bool = true
    @State private var isRotating = false
    
    var body: some View {
        ZStack {
            // Gray track
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3.5)
            
            // Blue spinning segment
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(Angle(degrees: isRotating ? 360 : 0))
                .onAppear { setSpinning(isSpinning) }
                .onChange(of: isSpinning) { _, spinning in setSpinning(spinning) }
        }
        .frame(width: 16, height: 16)
    }

    private func setSpinning(_ spinning: Bool) {
        if spinning {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                isRotating = true
            }
        } else {
            // A plain assignment replaces the repeating animation: it stops.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isRotating = false }
        }
    }
}
