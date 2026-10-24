//
//  MenuBarLayout.swift
//  DynamicIsland
//
//  Where the frontmost app's menus end, so a live activity can stay out of
//  their way.
//

import AppKit
import ApplicationServices
import Combine

/// Tracks the right edge of the frontmost application's menu bar items.
///
/// A live activity draws into the strip of menu bar to the left of the notch,
/// which is the same strip the app's own menus occupy. macOS lays those menus
/// out inside `NSScreen.auxiliaryTopLeftArea` and offers no way to tell it that
/// something else is using part of that space -- both auxiliary areas are
/// read-only and derived from the display hardware. So rather than reserving
/// room, Atoll measures what is already there and moves aside.
///
/// The measurement is the accessibility API's view of the menu bar, which is
/// how the geometry is available at all: every menu reports its own position
/// and size.
@MainActor
final class MenuBarLayout: ObservableObject {
    static let shared = MenuBarLayout()

    /// What the strip actually holds. `menuItemFrames` are the frontmost
    /// app's menu titles (accessibility's view, global coordinates; only x
    /// matters). `statusItemFrames` are the other apps' menu bar status
    /// items, from the window list. macOS lays menus out around the physical
    /// notch, so with a crowded menu bar some titles sit to the notch's
    /// right -- which is why one "right edge of the menus" is not enough to
    /// place anything.
    struct Measurement: Equatable {
        var menuItemFrames: [CGRect]
        var statusItemFrames: [CGRect]
    }

    /// `nil` when nothing can be known -- no accessibility permission, an app
    /// that exposes no menu bar, or a process that did not answer in time.
    /// Callers treat that as "no constraint" rather than guessing.
    @Published private(set) var measurement: Measurement?

    /// Menus change with the frontmost app, so each activation is measured,
    /// and again a little later for menus an app adds after it comes forward.
    /// Upstream also scanned every 3 s for as long as the island was closed,
    /// waking Skerry and the frontmost app with it all day; a menu that
    /// changes while its app stays in front waits for the next activation.
    static let followUpDelays: [TimeInterval] = [0.6, 2]

    private var observer: NSObjectProtocol?
    private var followUps: [DispatchWorkItem] = []
    private var trackers = 0
    private var inFlight = false

    private init() {}

    /// How far right content of `contentWidth`, centred in `screenFrame`, has
    /// to move so it clears the menu titles it covers.
    ///
    /// Zero when nothing is covered. The move is clamped to the room on the
    /// right -- up to the next menu title, status item, the island's own
    /// window edge (`maxRightEdge`: content past it is clipped to a hard
    /// black edge) or the screen edge -- so it changes smoothly with the width
    /// instead of flipping, which made the island jump under the pointer.
    ///
    /// On a screen with a notch macOS lays out titles that do not fit left of
    /// it to its right. One of those under the surface means both sides are
    /// taken, and the island stays on the notch: before, the right edge of
    /// all titles was taken for "where the menus end" and the island jumped
    /// past the notch onto the status items (21.10).
    ///
    /// `menuBarBand` is this screen's menu bar in top-left global
    /// coordinates, so a display stacked above or below does not count.
    nonisolated static func clearanceOffset(
        contentWidth: CGFloat,
        screenFrame: CGRect,
        measurement: Measurement,
        menuBarBand: ClosedRange<CGFloat>,
        hasNotch: Bool,
        maxRightEdge: CGFloat,
        gap: CGFloat
    ) -> CGFloat {
        guard contentWidth > 0 else { return 0 }
        let left = screenFrame.midX - contentWidth / 2
        let right = left + contentWidth
        let onThisMenuBar = { (frame: CGRect) in
            menuBarBand.contains(frame.midY) && frame.midX >= screenFrame.minX && frame.midX <= screenFrame.maxX
        }
        let menus = measurement.menuItemFrames.filter(onThisMenuBar)
        // Titles the surface covers, or sits flush against, ask for a move.
        let covered = menus.filter { $0.maxX > left - gap && $0.minX < right }
        guard let coveredEdge = covered.map(\.maxX).max() else { return 0 }
        if hasNotch, covered.contains(where: { $0.minX >= screenFrame.midX }) { return 0 }
        let wanted = coveredEdge + gap - left
        guard wanted > 0 else { return 0 }

        let obstacles = menus.filter { $0.minX >= right }.map(\.minX)
            + measurement.statusItemFrames.filter(onThisMenuBar).map(\.minX)
        let bound = min(maxRightEdge, screenFrame.maxX, (obstacles.min() ?? .greatestFiniteMagnitude) - gap)
        return max(0, min(wanted, bound - right))
    }

    /// How much the closed island grows while hovered: 8 pt in the middle and
    /// up to 12 pt on each music wing. Clearance is worked out for the hovered
    /// size, so hovering never changes the position.
    nonisolated static let hoverGrowthAllowance: CGFloat = 32

    /// The closed island's black surface: the content plus the closed padding
    /// on each side. Clearance is measured on this, so the surface itself
    /// stays off the menus, not just the content inside it.
    nonisolated static func surfaceWidth(contentWidth: CGFloat, padding: CGFloat) -> CGFloat {
        contentWidth > 0 ? contentWidth + 2 * max(0, padding) : 0
    }

    /// Breathing room between the last menu and the notch content, so they do
    /// not end up flush against each other.
    nonisolated static let clearanceGap: CGFloat = 8

    /// Begin measuring. Balanced by `stopTracking()`; nested calls are counted,
    /// so several live activities can ask at once without one's disappearance
    /// stopping the others.
    func startTracking() {
        trackers += 1
        guard trackers == 1 else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWithFollowUps() }
        }

        refreshWithFollowUps()
    }

    private func refreshWithFollowUps() {
        refresh()
        followUps.forEach { $0.cancel() }
        followUps = Self.followUpDelays.map { delay -> DispatchWorkItem in
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    func stopTracking() {
        guard trackers > 0 else { return }
        trackers -= 1
        guard trackers == 0 else { return }

        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        followUps.forEach { $0.cancel() }
        followUps.removeAll()
        measurement = nil
    }

    func refresh() {
        guard !inFlight, trackers > 0 else { return }
        guard AXIsProcessTrusted() else {
            measurement = nil
            return
        }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            measurement = nil
            return
        }

        // Off the main actor: these are cross-process calls, and an app that has
        // stopped answering would otherwise take the notch's UI down with it.
        inFlight = true
        Task.detached(priority: .utility) {
            let measured = Self.menuItemFrames(pid: pid).map {
                Measurement(menuItemFrames: $0, statusItemFrames: Self.statusItemFrames())
            }
            await MainActor.run {
                self.inFlight = false
                guard self.trackers > 0 else { return }
                if self.measurement != measured { self.measurement = measured }
            }
        }
    }

    /// Longest the whole scan may take. A menu bar with many items could
    /// otherwise reach minutes at the per-element timeout, and until it returns
    /// no further measurement is taken.
    nonisolated private static let scanDeadline: TimeInterval = 1

    /// Per-element messaging timeout. `AXUIElementSetMessagingTimeout` applies
    /// only to the element it is called on -- it does not carry to the children
    /// that element hands back -- so every element messaged here is given its
    /// own, or a hung app would still block on the ones that inherited nothing.
    nonisolated private static let elementTimeout: Float = 0.25

    /// The menu bar's status items, Skerry's own icon included: windows at the
    /// status level, one per item, no taller than the menu bar. The island
    /// (level 27) and the OSD (26) are left out by the level. Reading bounds
    /// and layer needs no permission; only window names are gated.
    nonisolated static func statusItemFrames() -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return windows.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == statusLevel,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 0, height > 0, height <= 40
            else { return nil }
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Every menu title's frame, or `nil` if the menu bar cannot be read.
    nonisolated private static func menuItemFrames(pid: pid_t) -> [CGRect]? {
        let startedAt = Date()
        let app = AXUIElementCreateApplication(pid)
        // A hung app must not hold this up; the measurement is an optimisation,
        // never something worth waiting on.
        AXUIElementSetMessagingTimeout(app, elementTimeout)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
        else { return nil }
        let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(menuBar, elementTimeout)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let items = childrenValue as? [AXUIElement], !items.isEmpty
        else { return nil }

        var frames: [CGRect] = []
        for item in items {
            // Whatever has been measured so far is still usable; a scan that has
            // run long is one where the app is not answering, and waiting out
            // every remaining item only delays the next attempt.
            guard Date().timeIntervalSince(startedAt) < scanDeadline else { break }
            AXUIElementSetMessagingTimeout(item, elementTimeout)

            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success
            else { continue }

            var origin = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            else { continue }

            frames.append(CGRect(origin: origin, size: size))
        }
        return frames.isEmpty ? nil : frames
    }
}
