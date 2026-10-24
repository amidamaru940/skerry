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

import CoreAudio
import Foundation

/// Tells when another app starts sending audio to an output device, from
/// CoreAudio's own property notices: nothing is polled.
///
/// The Now Playing adapter runs only while a player is active, and a player
/// that starts (from its own window, a media key, the island's ⏯) starts
/// making sound first. CoreAudio reports that per process
/// (`kAudioProcessPropertyIsRunningOutput`), so every process gets a
/// listener, and the process list gets one for apps that appear. Main
/// thread only; no permission is needed to read these.
final class AudioOutputActivity {
    /// Another process began output (or is outputting when watching starts).
    var onOutputStarted: (() -> Void)?
    /// `anyOtherOutput` changed.
    var onActivityChanged: ((Bool) -> Void)?

    /// Whether any process but this one is sending audio right now.
    private(set) var anyOtherOutput = false
    private(set) var isWatching = false

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var listListener: AudioObjectPropertyListenerBlock?
    private var outputting: Set<AudioObjectID> = []

    private static var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    /// The per-process notices listened to. macOS 26 never posts a change of
    /// `IsRunningOutput` (measured: not when a player starts, pauses or
    /// resumes), but posts `IsRunning` each time I/O starts or stops, and by
    /// then `IsRunningOutput` already reads right. Both are listened to; the
    /// answer is always read from `IsRunningOutput`.
    static let listenedProcessProperties: [AudioObjectPropertySelector] = [
        kAudioProcessPropertyIsRunningOutput,
        kAudioProcessPropertyIsRunning,
    ]

    private static func processAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    deinit {
        stop()
    }

    func start() {
        guard !isWatching else { return }
        isWatching = true
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.syncProcesses()
        }
        var address = Self.processListAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            listListener = block
        }
        syncProcesses()
    }

    func stop() {
        guard isWatching else { return }
        isWatching = false
        if let listListener {
            var address = Self.processListAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listListener)
            self.listListener = nil
        }
        let present = Set(AudioProcessQuery.processObjectIDs())
        // Only processes still there have listeners to remove (see syncProcesses).
        for (object, block) in processListeners where present.contains(object) {
            removeProcessListener(object, block)
        }
        processListeners.removeAll()
        outputting.removeAll()
        anyOtherOutput = false
    }

    /// Listens to processes that appeared and forgets those that left.
    private func syncProcesses() {
        guard isWatching else { return }
        let current = Set(AudioProcessQuery.processObjectIDs())
        // A process that left took its object with it: removing its
        // listeners failed anyway and only logged «no object with given ID»
        // each time an app stopped playing (24.10). They are just forgotten.
        for object in processListeners.keys where !current.contains(object) {
            processListeners[object] = nil
        }
        for object in current where processListeners[object] == nil {
            guard AudioProcessQuery.pid(for: object) != ownPID else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.evaluate()
            }
            var added = false
            for selector in Self.listenedProcessProperties {
                var address = Self.processAddress(selector)
                if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
                    added = true
                }
            }
            if added {
                processListeners[object] = block
            }
        }
        evaluate()
    }

    private func removeProcessListener(_ object: AudioObjectID, _ block: @escaping AudioObjectPropertyListenerBlock) {
        for selector in Self.listenedProcessProperties {
            var address = Self.processAddress(selector)
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
    }

    private func evaluate() {
        let now = Set(processListeners.keys.filter(AudioProcessQuery.isRunningOutput))
        let began = Self.outputBegan(previous: outputting, current: now)
        let wasOutputting = anyOtherOutput
        outputting = now
        anyOtherOutput = !now.isEmpty
        if began { onOutputStarted?() }
        if anyOtherOutput != wasOutputting { onActivityChanged?(anyOtherOutput) }
    }

    /// True when a process is outputting now that was not before.
    static func outputBegan(previous: Set<AudioObjectID>, current: Set<AudioObjectID>) -> Bool {
        !current.subtracting(previous).isEmpty
    }
}
