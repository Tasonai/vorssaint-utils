// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import CoreAudio
import Foundation

/// Monitors active camera and microphone usage across the system
/// using CoreAudio HAL and AVFoundation properties, providing real-time
/// updates for Dynamic Island privacy indicators.
final class CameraMicrophonePrivacyMonitor: ObservableObject {
    static let shared = CameraMicrophonePrivacyMonitor()

    @Published private(set) var isCameraActive: Bool = false
    @Published private(set) var isMicrophoneActive: Bool = false
    @Published private(set) var activeCameraName: String? = nil
    @Published private(set) var activeMicrophoneName: String? = nil
    @Published private(set) var isMicrophoneMuted: Bool = MicMuteService.shared.isMuted

    var isAnyActive: Bool {
        isCameraActive || isMicrophoneActive
    }

    private let halQueue = DispatchQueue(label: "com.vorssaint.privacy.hal", qos: .utility)
    private var pollTimer: Timer?
    private var registeredDeviceIDs = Set<AudioDeviceID>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var isEvaluating = false
    private var pendingEvaluation = false

    private init() {
        start()
    }

    deinit {
        stop()
    }

    func start() {
        setupNotifications()
        halQueue.async { [weak self] in
            self?.syncAudioListeners()
            self?.evaluate()
        }
        DispatchQueue.main.async { [weak self] in
            self?.pollTimer?.invalidate()
            self?.pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.halQueue.async {
                    self?.evaluate()
                }
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        halQueue.sync {
            removeAudioListeners()
        }
    }

    func toggleMicrophoneMute() {
        MicMuteService.shared.toggle()
        DispatchQueue.main.async { [weak self] in
            self?.isMicrophoneMuted = MicMuteService.shared.isMuted
        }
    }

    // MARK: - Event Listeners

    private static let halPropertyListener: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let monitor = Unmanaged<CameraMicrophonePrivacyMonitor>.fromOpaque(client).takeUnretainedValue()
        monitor.scheduleEvaluation()
        return noErr
    }

    private var listenerPointer: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private func scheduleEvaluation() {
        halQueue.async { [weak self] in
            self?.syncAudioListeners()
            self?.evaluate()
        }
    }

    private func setupNotifications() {
        let center = NotificationCenter.default
        let connectToken = center.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasConnected,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleEvaluation()
        }
        let disconnectToken = center.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleEvaluation()
        }
        notificationObservers = [connectToken, disconnectToken]
    }

    private func syncAudioListeners() {
        // System-level listeners for default input and device list changes
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            Self.halPropertyListener,
            listenerPointer
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            Self.halPropertyListener,
            listenerPointer
        )

        // Listeners for running state on each input device
        let currentInputIDs = Set(allInputDeviceIDs())
        let newIDs = currentInputIDs.subtracting(registeredDeviceIDs)
        let removedIDs = registeredDeviceIDs.subtracting(currentInputIDs)

        for devID in newIDs {
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListener(devID, &runningAddress, Self.halPropertyListener, listenerPointer)
        }

        for devID in removedIDs {
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(devID, &runningAddress, Self.halPropertyListener, listenerPointer)
        }

        registeredDeviceIDs = currentInputIDs
    }

    private func removeAudioListeners() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            Self.halPropertyListener,
            listenerPointer
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            Self.halPropertyListener,
            listenerPointer
        )

        for devID in registeredDeviceIDs {
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(devID, &runningAddress, Self.halPropertyListener, listenerPointer)
        }
        registeredDeviceIDs.removeAll()
    }

    // MARK: - Evaluation

    private func evaluate() {
        if isEvaluating {
            pendingEvaluation = true
            return
        }
        isEvaluating = true

        let micState = checkMicrophoneInUse()
        let camState = checkCameraInUse()
        let micMuted = MicMuteService.shared.isMuted

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isMicrophoneActive != micState.isActive || self.activeMicrophoneName != micState.name {
                self.isMicrophoneActive = micState.isActive
                self.activeMicrophoneName = micState.name
            }
            if self.isCameraActive != camState.isActive || self.activeCameraName != camState.name {
                self.isCameraActive = camState.isActive
                self.activeCameraName = camState.name
            }
            if self.isMicrophoneMuted != micMuted {
                self.isMicrophoneMuted = micMuted
            }
        }

        isEvaluating = false
        if pendingEvaluation {
            pendingEvaluation = false
            halQueue.async { [weak self] in
                self?.evaluate()
            }
        }
    }

    private func checkCameraInUse() -> (isActive: Bool, name: String?) {
        // Check Vorssaint internal camera preview first
        if let session = CameraPreviewService.shared.session, session.isRunning {
            let selectedID = CameraPreviewService.shared.selectedDeviceID
            let device = CameraPreviewService.shared.devices.first { $0.uniqueID == selectedID }
            let name = device?.localizedName ?? "FaceTime HD Camera"
            return (true, name)
        }

        // Check system camera devices used by other applications
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        for device in session.devices {
            if device.isInUseByAnotherApplication {
                return (true, device.localizedName)
            }
        }
        return (false, nil)
    }

    private func checkMicrophoneInUse() -> (isActive: Bool, name: String?) {
        for devID in allInputDeviceIDs() {
            var runAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(devID, &runAddress, 0, nil, &isRunningSize, &isRunning) == noErr,
               isRunning != 0 {
                let name = deviceName(devID: devID)
                return (true, name)
            }
        }
        return (false, nil)
    }

    private func allInputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize) == noErr else {
            return []
        }
        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize, &deviceIDs) == noErr else {
            return []
        }

        var inputIDs: [AudioDeviceID] = []
        for devID in deviceIDs {
            guard isInputDevice(devID: devID) else { continue }
            if let name = deviceName(devID: devID), MicMuteSupport.isOwnDevice(name: name) {
                continue
            }
            inputIDs.append(devID)
        }
        return inputIDs
    }

    private func isInputDevice(devID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var bufferListSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(devID, &address, 0, nil, &bufferListSize) == noErr,
              bufferListSize > 0 else {
            return false
        }
        guard let rawBufferList = malloc(Int(bufferListSize)) else { return false }
        defer { free(rawBufferList) }
        let bufferListPtr = rawBufferList.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(devID, &address, 0, nil, &bufferListSize, bufferListPtr) == noErr else {
            return false
        }
        let numBuffers = Int(bufferListPtr.pointee.mNumberBuffers)
        guard numBuffers > 0 else { return false }
        return withUnsafePointer(to: &bufferListPtr.pointee.mBuffers) { ptr in
            let buffer = UnsafeBufferPointer<AudioBuffer>(start: ptr, count: numBuffers)
            return buffer.contains { $0.mNumberChannels > 0 }
        }
    }

    private func deviceName(devID: AudioDeviceID) -> String? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameCF: Unmanaged<CFString>? = nil
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &nameCF) { ptr in
            AudioObjectGetPropertyData(devID, &nameAddress, 0, nil, &nameSize, UnsafeMutableRawPointer(ptr))
        }
        guard status == noErr else { return nil }
        return nameCF?.takeRetainedValue() as String?
    }
}
