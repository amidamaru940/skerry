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
import CoreBluetooth
import Foundation

/// Sees Bluetooth headphones arrive and leave through CoreAudio, which asks
/// for no permission: a connected pair is an output device whose transport
/// is Bluetooth. BluetoothAudioManager uses it only while Bluetooth is not
/// allowed (§5.8), so it knows the name and nothing else -- no battery.
///
/// It listens to the system object's device list and default output; both
/// change when headphones connect, and the second one also catches a device
/// whose streams were not ready yet when the list first changed. No timer.
///
/// Each look also reads the Bluetooth authorization, here on its own queue:
/// that read is a TCC preflight (an XPC call to tccd) and has no business on
/// the main thread either. It is how the manager learns, with no click, that
/// Bluetooth was allowed in System Settings.
final class BluetoothAudioRouteObserver {
    /// A connected pair of headphones, as CoreAudio names it.
    struct Device: Equatable {
        let name: String
        /// The Bluetooth address when the device UID carries one (it does for
        /// Bluetooth devices: "F4-34-F0-A6-4C-1B:output"), in IOBluetooth's
        /// spelling, so the battery lookups match once Bluetooth is allowed.
        let address: String
    }

    /// What CoreAudio reports for one device, before deciding whether it is
    /// a pair of headphones.
    struct Candidate: Equatable {
        let uid: String
        let name: String
        let transportType: UInt32
        let hasOutput: Bool
    }

    /// One look at the system.
    struct Report: Equatable {
        /// The headphones connected now.
        let devices: [Device]
        /// What macOS has recorded for Bluetooth at that moment.
        let authorization: CBManagerAuthorization
    }

    /// The state after every change, on the main queue. The first call after
    /// `start()` is the state at that moment. A look that finds what the last
    /// call carried is not delivered: one connection sets off a burst of
    /// CoreAudio changes, and aggregate devices (per-app volume, audio taps)
    /// come and go with no headphones involved.
    var onChange: ((Report) -> Void)?

    /// CoreAudio calls the listener here, and the device reads happen here
    /// too: they are calls into coreaudiod and have no business on the main
    /// thread.
    private let queue = DispatchQueue(label: "io.github.amidamaru940.skerry.bluetooth-audio-route", qos: .utility)
    private var listener: AudioObjectPropertyListenerBlock?
    /// The last report delivered; touched only on `queue`.
    private var lastReport: Report?

    private static let watchedSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultOutputDevice
    ]

    deinit {
        if let listener {
            Self.removeListener(listener, queue: queue)
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.report()
            }
            for selector in Self.watchedSelectors {
                var address = Self.systemAddress(selector)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, self.queue, listener)
            }
            self.listener = listener
            self.lastReport = nil
            self.report()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, let listener = self.listener else { return }
            Self.removeListener(listener, queue: self.queue)
            self.listener = nil
        }
    }

    private func report() {
        guard listener != nil else { return }
        let report = Report(
            devices: Self.headphones(in: Self.readCandidates()),
            authorization: CBManager.authorization
        )
        guard report != lastReport else { return }
        lastReport = report
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(report)
        }
    }

    // MARK: - Decisions

    static func isBluetooth(transportType: UInt32) -> Bool {
        transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    /// "F4-34-F0-A6-4C-1B:output" -> "f4-34-f0-a6-4c-1b", IOBluetooth's
    /// `addressString`. A UID without the suffix is kept whole, lowercased.
    static func bluetoothAddress(fromDeviceUID uid: String) -> String {
        var address = uid.lowercased()
        for suffix in [":output", ":input"] where address.hasSuffix(suffix) {
            address.removeLast(suffix.count)
        }
        return address
    }

    /// The Bluetooth output devices, once each: a headset's microphone is a
    /// device of its own (":input", no output) and is not a second pair.
    static func headphones(in candidates: [Candidate]) -> [Device] {
        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            guard candidate.hasOutput, isBluetooth(transportType: candidate.transportType) else { return nil }
            let address = bluetoothAddress(fromDeviceUID: candidate.uid)
            let key = address.isEmpty ? candidate.name : address
            guard seen.insert(key).inserted else { return nil }
            return Device(name: candidate.name, address: key)
        }
    }

    // MARK: - CoreAudio

    private static func systemAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func removeListener(_ listener: @escaping AudioObjectPropertyListenerBlock, queue: DispatchQueue) {
        for selector in watchedSelectors {
            var address = systemAddress(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        }
    }

    private static func readCandidates() -> [Candidate] {
        deviceIDs().map { device in
            Candidate(
                uid: string(kAudioDevicePropertyDeviceUID, of: device) ?? "",
                name: string(kAudioObjectPropertyName, of: device) ?? "",
                transportType: transportType(of: device),
                hasOutput: hasOutputStreams(device)
            )
        }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = systemAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = systemAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var address = systemAddress(kAudioDevicePropertyTransportType)
        var type: UInt32 = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type) == noErr else {
            return kAudioDeviceTransportTypeUnknown
        }
        return type
    }

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }
}
