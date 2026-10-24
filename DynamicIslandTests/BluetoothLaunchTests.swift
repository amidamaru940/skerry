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

@testable import Atoll
import CoreAudio
import CoreBluetooth
import XCTest

/// §5.8: launch only reads the Bluetooth authorization. Headphones are seen
/// through CoreAudio until Bluetooth is allowed, and Bluetooth is asked for
/// only from a click.
final class BluetoothLaunchTests: XCTestCase {
    private typealias Candidate = BluetoothAudioRouteObserver.Candidate
    private typealias RouteDevice = BluetoothAudioRouteObserver.Device

    // MARK: - Which watch launch starts

    /// A Mac that already allowed Bluetooth keeps the IOBluetooth watch and
    /// its battery levels, with no click: nothing changes for it.
    func testAMacThatAllowedBluetoothKeepsTheBluetoothWatch() {
        XCTAssertEqual(BluetoothAudioManager.deviceWatch(for: .allowedAlways), .bluetooth)
    }

    func testEveryOtherAnswerFollowsHeadphonesThroughCoreAudio() {
        for authorization: CBManagerAuthorization in [.notDetermined, .denied, .restricted] {
            XCTAssertEqual(BluetoothAudioManager.deviceWatch(for: authorization), .audioDevices, "\(authorization.rawValue)")
        }
    }

    func testOnlyANeverAskedMacGetsTheQuestion() {
        XCTAssertEqual(BluetoothAudioManager.batteryAccess(for: .notDetermined), .ask)
        XCTAssertEqual(BluetoothAudioManager.batteryAccess(for: .allowedAlways), .allowed)
        XCTAssertEqual(BluetoothAudioManager.batteryAccess(for: .denied), .refused)
        XCTAssertEqual(BluetoothAudioManager.batteryAccess(for: .restricted), .refused)
    }

    func testTheBatteryQuestionIsDueOnlyWithHeadphonesAndNoAnswer() {
        XCTAssertTrue(BluetoothAudioManager.isBatteryQuestionDue(authorization: .notDetermined, headphonesConnected: true, questionShown: false))
        XCTAssertFalse(BluetoothAudioManager.isBatteryQuestionDue(authorization: .notDetermined, headphonesConnected: false, questionShown: false))
        XCTAssertFalse(BluetoothAudioManager.isBatteryQuestionDue(authorization: .allowedAlways, headphonesConnected: true, questionShown: false))
        XCTAssertFalse(BluetoothAudioManager.isBatteryQuestionDue(authorization: .denied, headphonesConnected: true, questionShown: false))
    }

    /// `bluetoothQuestionShown`: the question is asked once per install.
    func testTheBatteryQuestionIsNotAskedTwice() {
        XCTAssertFalse(BluetoothAudioManager.isBatteryQuestionDue(authorization: .notDetermined, headphonesConnected: true, questionShown: true))
    }

    // MARK: - What CoreAudio counts as headphones

    func testBluetoothAndBluetoothLETransportsAreHeadphones() {
        XCTAssertTrue(BluetoothAudioRouteObserver.isBluetooth(transportType: kAudioDeviceTransportTypeBluetooth))
        XCTAssertTrue(BluetoothAudioRouteObserver.isBluetooth(transportType: kAudioDeviceTransportTypeBluetoothLE))
        for transport in [kAudioDeviceTransportTypeBuiltIn, kAudioDeviceTransportTypeUSB,
                          kAudioDeviceTransportTypeAirPlay, kAudioDeviceTransportTypeAggregate] {
            XCTAssertFalse(BluetoothAudioRouteObserver.isBluetooth(transportType: transport))
        }
    }

    /// The address is spelt as IOBluetooth spells it, so the battery lookups
    /// match the same device once Bluetooth is allowed.
    func testTheDeviceUIDGivesIOBluetoothsAddress() {
        XCTAssertEqual(BluetoothAudioRouteObserver.bluetoothAddress(fromDeviceUID: "F4-34-F0-A6-4C-1B:output"), "f4-34-f0-a6-4c-1b")
        XCTAssertEqual(BluetoothAudioRouteObserver.bluetoothAddress(fromDeviceUID: "F4-34-F0-A6-4C-1B:input"), "f4-34-f0-a6-4c-1b")
        XCTAssertEqual(BluetoothAudioRouteObserver.bluetoothAddress(fromDeviceUID: "SomeVendorUID"), "somevendoruid")
    }

    func testOnlyBluetoothOutputsCountAndAHeadsetCountsOnce() {
        let candidates = [
            Candidate(uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers", transportType: kAudioDeviceTransportTypeBuiltIn, hasOutput: true),
            Candidate(uid: "F4-34-F0-A6-4C-1B:input", name: "AirPods Pro", transportType: kAudioDeviceTransportTypeBluetooth, hasOutput: false),
            Candidate(uid: "F4-34-F0-A6-4C-1B:output", name: "AirPods Pro", transportType: kAudioDeviceTransportTypeBluetooth, hasOutput: true),
            Candidate(uid: "F4-34-F0-A6-4C-1B", name: "AirPods Pro", transportType: kAudioDeviceTransportTypeBluetooth, hasOutput: true),
            Candidate(uid: "00-11-22-33-44-55:output", name: "Speaker LE", transportType: kAudioDeviceTransportTypeBluetoothLE, hasOutput: true),
        ]

        XCTAssertEqual(BluetoothAudioRouteObserver.headphones(in: candidates), [
            RouteDevice(name: "AirPods Pro", address: "f4-34-f0-a6-4c-1b"),
            RouteDevice(name: "Speaker LE", address: "00-11-22-33-44-55"),
        ])
    }

    // MARK: - Feeding the connection HUD

    /// Headphones already on at launch are no news, as with IOBluetooth's
    /// first look at the paired devices.
    func testTheFirstReportFillsTheListWithoutAToast() {
        let update = BluetoothAudioManager.audioRouteUpdate(
            known: [],
            reported: [RouteDevice(name: "AirPods Max", address: "aa-bb")],
            isFirstReport: true
        )

        XCTAssertEqual(update.devices.map(\.name), ["AirPods Max"])
        XCTAssertTrue(update.arrived.isEmpty)
    }

    func testANewPairIsAnnouncedWithoutABatteryLevel() {
        let update = BluetoothAudioManager.audioRouteUpdate(
            known: [],
            reported: [RouteDevice(name: "Test AirPods Pro", address: "aa-bb")],
            isFirstReport: false
        )

        XCTAssertEqual(update.arrived.count, 1)
        XCTAssertEqual(update.arrived.first?.address, "aa-bb")
        XCTAssertNil(update.arrived.first?.batteryLevel)
        XCTAssertEqual(update.arrived.first?.deviceType, .airpodsPro)
    }

    /// The HUD names and draws `lastConnectedDevice`, and the lock screen reads
    /// `.last`: the device that just arrived goes last, as IOBluetooth's path
    /// appends it, whatever CoreAudio's order. A speaker already on and
    /// AirPods arriving ahead of it in CoreAudio's list toast the AirPods.
    func testANewcomerGoesLastWhateverOrderCoreAudioListsIt() {
        let speaker = BluetoothAudioDevice(name: "JBL Flip 6", address: "aa-aa", batteryLevel: nil, deviceType: .speaker)

        let update = BluetoothAudioManager.audioRouteUpdate(
            known: [speaker],
            reported: [
                RouteDevice(name: "AirPods Pro", address: "bb-bb"),
                RouteDevice(name: "JBL Flip 6", address: "aa-aa"),
            ],
            isFirstReport: false
        )

        XCTAssertEqual(update.devices.map(\.address), ["aa-aa", "bb-bb"])
        XCTAssertEqual(update.devices.first?.id, speaker.id)
        XCTAssertEqual(update.arrived.map(\.address), ["bb-bb"])
    }

    /// CoreAudio listing the same devices in another order is no change: the
    /// list keeps its order and identities, so nothing is republished.
    func testCoreAudioReorderingTheSameDevicesChangesNothing() {
        let first = BluetoothAudioDevice(name: "AirPods", address: "aa-aa", batteryLevel: nil, deviceType: .airpods)
        let second = BluetoothAudioDevice(name: "JBL Flip 6", address: "bb-bb", batteryLevel: nil, deviceType: .speaker)

        let update = BluetoothAudioManager.audioRouteUpdate(
            known: [first, second],
            reported: [
                RouteDevice(name: "JBL Flip 6", address: "bb-bb"),
                RouteDevice(name: "AirPods", address: "aa-aa"),
            ],
            isFirstReport: false
        )

        XCTAssertEqual(update.devices.map(\.id), [first.id, second.id])
        XCTAssertTrue(update.arrived.isEmpty)
    }

    func testAPairStillThereKeepsItsIdentityAndOneThatLeftIsDropped() {
        let kept = BluetoothAudioDevice(name: "AirPods", address: "aa-bb", batteryLevel: nil, deviceType: .airpods)
        let gone = BluetoothAudioDevice(name: "Beats Solo", address: "cc-dd", batteryLevel: nil, deviceType: .beatssolo)

        let update = BluetoothAudioManager.audioRouteUpdate(
            known: [kept, gone],
            reported: [RouteDevice(name: "AirPods", address: "aa-bb")],
            isFirstReport: false
        )

        XCTAssertEqual(update.devices.map(\.id), [kept.id])
        XCTAssertTrue(update.arrived.isEmpty)
    }

    /// CoreAudio knows a name and nothing else; a name that says nothing is a
    /// pair of headphones.
    func testAnUnknownNameIsTreatedAsHeadphones() {
        let update = BluetoothAudioManager.audioRouteUpdate(
            known: [],
            reported: [RouteDevice(name: "WH-1000XM5", address: "ee-ff")],
            isFirstReport: false
        )

        XCTAssertEqual(update.arrived.first?.deviceType, .headphones)
    }

    func testTheNameGivesAwayTheModel() {
        XCTAssertEqual(BluetoothAudioManager.deviceType(forName: "AirPods Max"), .airpodsMax)
        XCTAssertEqual(BluetoothAudioManager.deviceType(forName: "AirPods Pro 3"), .airpodsPro3)
        XCTAssertEqual(BluetoothAudioManager.deviceType(forName: "Beats Studio Pro"), .beatsstudio)
        XCTAssertEqual(BluetoothAudioManager.deviceType(forName: "JBL Boombox 3"), .speaker)
        XCTAssertNil(BluetoothAudioManager.deviceType(forName: "WH-1000XM5"))
    }
}
