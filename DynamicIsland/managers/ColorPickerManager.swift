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
import Cocoa
import CoreGraphics
import Defaults

// MARK: - NSColor Extensions from Solid
extension NSColor {
    var hexString: String {
        let red = Int((redComponent * 255).rounded())
        let green = Int((greenComponent * 255).rounded())
        let blue = Int((blueComponent * 255).rounded())
        let alpha = Int((alphaComponent * 255).rounded())

        if alpha == 255 {
            return String(format: "%02x%02x%02x", red, green, blue)
        } else {
            return String(format: "%02x%02x%02x%02x", red, green, blue, alpha)
        }
    }
}

// MARK: - Color Formatter from Solid
struct ColorFormatter {
    static let shared = ColorFormatter()

    func hex(
        color: NSColor,
        includeHashPrefix: Bool = true,
        lowerCaseHex: Bool = false
    ) -> String {
        let prefix = includeHashPrefix ? "#" : ""
        let hex = (prefix + color.hexString)
        
        if lowerCaseHex {
            return hex
        } else {
            return hex.uppercased()
        }
    }
}

class ColorPickerManager: ObservableObject {
    static let shared = ColorPickerManager()
    
    @Published var colorHistory: [PickedColor] = []
    @Published var isPickingColor: Bool = false
    
    // Use NSColorSampler from Solid project - much more reliable
    private let colorSampler = NSColorSampler()
    
    private init() {
        loadColorHistory()
    }
    
    // MARK: - Public Interface
    
    /// Whether the panel comes back after the pick in progress.
    private var reopensPanelAfterPick = false

    /// What follows a pick. Every pick flashes on the closed island (the
    /// colour is already copied). The panel comes back only when the pick
    /// started from its own button, which closes it for the pick -- and
    /// without taking the focus: reopening it as the key window took the
    /// focus from the app the colour was meant to be pasted into.
    struct AfterPick: Equatable {
        var flashes = true
        var reopensPanel: Bool
        var panelTakesFocus = false
    }

    static func afterPick(startedFromPanel: Bool) -> AfterPick {
        AfterPick(reopensPanel: startedFromPanel)
    }

    func startColorPicking(reopensPanel: Bool = false) {
        guard !isPickingColor else { return }
        reopensPanelAfterPick = reopensPanel
        
        print("ColorPicker: Starting color picking with NSColorSampler...")
        
        isPickingColor = true
        
        // Use NSColorSampler like Solid project - much cleaner and more reliable
        colorSampler.show { [weak self] pickedColor in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isPickingColor = false
                
                if let color = pickedColor {
                    print("ColorPicker: Successfully picked color - R:\(color.redComponent) G:\(color.greenComponent) B:\(color.blueComponent)")
                    
                    // Convert to sRGB for consistent color handling
                    if let sRGBColor = color.usingColorSpace(.sRGB) {
                        let pickedColor = PickedColor(nsColor: sRGBColor, point: NSEvent.mouseLocation)
                        self.addColor(pickedColor)
                        self.showColorPickedFeedback(for: pickedColor)
                        
                        // Provide haptic feedback if enabled
                        if Defaults[.enableHaptics] {
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                        }
                    }
                } else {
                    print("ColorPicker: Color picking cancelled by user")
                }
            }
        }
    }
    
    // MARK: - Color Feedback
    
    private func showColorPickedFeedback(for color: PickedColor) {
        print("ColorPicker: Showing color picked feedback for \(color.hexString)")
        let after = Self.afterPick(startedFromPanel: reopensPanelAfterPick)
        if after.flashes {
            MainActor.assumeIsolated { ColorPickFlash.shared.show(color) }
        }
        if after.reopensPanel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ColorPickerPanelManager.shared.showColorPickerPanel(takingFocus: after.panelTakesFocus)
            }
        }
    }
    
    // MARK: - Color History Management
    
    func addColor(_ color: PickedColor) {
        // By colour, not by the new id every pick gets, and as many as the
        // setting says (it was a fixed 50 and repeats piled up).
        colorHistory = ColorHistoryRules.adding(color, to: colorHistory, limit: Defaults[.colorHistorySize])
        
        saveColorHistory()
        
        // Always copy to clipboard for now (can be made configurable later if needed)
        copyToClipboard(color.hexString)
    }
    
    func removeColor(_ color: PickedColor) {
        colorHistory.removeAll { $0.id == color.id }
        saveColorHistory()
    }
    
    func clearHistory() {
        colorHistory.removeAll()
        saveColorHistory()
    }
    
    /// Colours have their own history here; marked as the app's own write,
    /// they stay out of the clipboard history. A screenshot paste or copy
    /// under way stops first, so it does not overwrite the colour.
    func copyToClipboard(_ text: String, to pasteboard: NSPasteboard = .general) {
        ClipboardPaster.yieldClipboardFromAnyThread()
        ClipboardOwnWrites.write(to: pasteboard) { pasteboard in
            pasteboard.setString(text, forType: .string)
        }
    }
    
    func copyColorToClipboard(_ color: PickedColor, format: ColorFormat) {
        copyToClipboard(format.copyValue)
    }
    
    // MARK: - Persistence
    
    private func saveColorHistory() {
        if let encoded = try? JSONEncoder().encode(colorHistory) {
            UserDefaults.standard.set(encoded, forKey: "ColorPickerHistory")
        }
    }
    
    private func loadColorHistory() {
        guard let data = UserDefaults.standard.data(forKey: "ColorPickerHistory"),
              let decoded = try? JSONDecoder().decode([PickedColor].self, from: data) else {
            return
        }
        
        colorHistory = decoded
    }
}

/// How the colour history grows.
enum ColorHistoryRules {
    /// The new colour on top, an earlier pick of the same colour gone, at
    /// most `limit` kept.
    static func adding(_ color: PickedColor, to history: [PickedColor], limit: Int) -> [PickedColor] {
        var result = history.filter { $0.hexString != color.hexString }
        result.insert(color, at: 0)
        return Array(result.prefix(max(1, limit)))
    }
}

/// The picked colour on the closed island for a moment (swatch and hex), so
/// a pick is confirmed without a window taking the focus.
@MainActor
final class ColorPickFlash: ObservableObject {
    static let shared = ColorPickFlash()
    static let duration: TimeInterval = 2

    @Published private(set) var color: PickedColor?
    private var clearWork: DispatchWorkItem?

    func show(_ color: PickedColor, for seconds: TimeInterval = ColorPickFlash.duration) {
        clearWork?.cancel()
        self.color = color
        let work = DispatchWorkItem { [weak self] in self?.color = nil }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func clear() {
        clearWork?.cancel()
        color = nil
    }
}
