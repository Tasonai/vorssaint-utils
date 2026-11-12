// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreMediaIO
import Foundation

/// Monitors active camera and microphone usage across the system
/// using CoreAudio HAL, CoreMediaIO, and AVFoundation event listeners,
/// providing real-time updates for Dynamic Island privacy indicators.
final class CameraMicrophonePrivacyMonitor: ObservableObject {
    static let shared = CameraMicrophonePrivacyMonitor()

    @Published private(set) var isCameraActive: Bool = false
    @Published private(set) var isMicrophoneActive: Bool = false
    @Published private(set) var activeCameraName: String? = nil
    @Published private(set) var activeMicrophoneName: String? = nil
    @Published private(set) var isMicrophoneMuted: Bool = false

    var isAnyActive: Bool {
        isCameraActive || isMicrophoneActive
    }

    private struct CMIOListenerRegistration {
        let objectID: CMIOObjectID
        var address: CMIOObjectPropertyAddress
        let block: CMIOObjectPropertyListenerBlock
    }

    private static let activeReconcileInterval: TimeInterval = 15.0
    private static let activeReconcileTolerance: TimeInterval = 5.0

    private let halQueue = DispatchQueue(label: "com.vorssaint.privacy.hal", qos: .utility)
    private var reconcileTimer: Timer?
    private var displaysSleeping = false
    private var audioSystemListenersRegistered = false
    private var registeredDeviceIDs = Set<AudioDeviceID>()
    private var cmioSystemListener: CMIOListenerRegistration?
    private var cmioDeviceListeners: [CMIOObjectID: CMIOListenerRegistration] = [:]
    private var cameraDiscoverySession: AVCaptureDevice.DiscoverySession?
    private var cameraInUseObservations: [NSKeyValueObservation] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var pendingMuteTarget: (muted: Bool, expiresAt: TimeInterval)?
    private var muteReconcileWork: DispatchWorkItem?
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
            guard let self else { return }
            self.rebuildCameraDiscoverySession()
            self.syncCMIOListeners()
            self.syncAudioListeners()
            self.evaluate()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cancellables.removeAll()
            self.isMicrophoneMuted = MicMuteService.shared.isMuted
            MicMuteService.shared.$isMuted
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] muted in
                    self?.reconcileMutedStateOnMain(muted, fromPublisher: true)
                }
                .store(in: &self.cancellables)
            CameraPreviewService.shared.$state
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.scheduleEvaluation()
                }
                .store(in: &self.cancellables)
            self.syncReconcileTimerOnMain()
        }
    }

    func stop() {
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        cancellables.removeAll()
        muteReconcileWork?.cancel()
        muteReconcileWork = nil
        pendingMuteTarget = nil
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        halQueue.sync {
            cameraInUseObservations.removeAll()
            cameraDiscoverySession = nil
            removeCMIOListeners()
            removeAudioListeners()
        }
    }

    func toggleMicrophoneMute() {
        let applyToggle = { [weak self] in
            guard let self else { return }
            let target = !(self.pendingMuteTarget?.muted ?? self.isMicrophoneMuted)
            self.pendingMuteTarget = (muted: target, expiresAt: ProcessInfo.processInfo.systemUptime + 1.0)
            if self.isMicrophoneMuted != target {
                self.isMicrophoneMuted = target
            }
            self.muteReconcileWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingMuteTarget = nil
                let actual = MicMuteService.shared.isMuted
                if self.isMicrophoneMuted != actual {
                    self.isMicrophoneMuted = actual
                }
            }
            self.muteReconcileWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
            MicMuteService.shared.toggle()
        }
        if Thread.isMainThread {
            applyToggle()
        } else {
            DispatchQueue.main.async(execute: applyToggle)
        }
    }

    private func reconcileMutedStateOnMain(_ reportedMuted: Bool, fromPublisher: Bool) {
        if let pending = pendingMuteTarget {
            if reportedMuted == pending.muted || fromPublisher || ProcessInfo.processInfo.systemUptime >= pending.expiresAt {
                pendingMuteTarget = nil
                muteReconcileWork?.cancel()
                muteReconcileWork = nil
            } else {
                // Ignore stale pre-sweep poll reads while MicMuteService.toggle() is in flight.
                return
            }
        }
        if isMicrophoneMuted != reportedMuted {
            isMicrophoneMuted = reportedMuted
        }
    }

    // MARK: - Event Listeners

    private static let halPropertyListener: AudioObjectPropertyListenerProc = { _, numberAddresses, addresses, client in
        guard let client else { return noErr }
        let monitor = Unmanaged<CameraMicrophonePrivacyMonitor>.fromOpaque(client).takeUnretainedValue()
        var deviceListChanged = false
        if numberAddresses > 0 {
            let buffer = UnsafeBufferPointer(start: addresses, count: Int(numberAddresses))
            deviceListChanged = buffer.contains {
                $0.mSelector == kAudioHardwarePropertyDevices
                    || $0.mSelector == kAudioHardwarePropertyDefaultInputDevice
            }
        }
        monitor.scheduleEvaluation(resyncAudioDevices: deviceListChanged)
        return noErr
    }

    private var listenerPointer: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private func scheduleEvaluation(resyncAudioDevices: Bool = false, resyncCameras: Bool = false) {
        halQueue.async { [weak self] in
            guard let self else { return }
            if resyncCameras {
                self.rebuildCameraDiscoverySession()
                self.syncCMIOListeners()
            }
            if resyncAudioDevices {
                self.syncAudioListeners()
            }
            self.evaluate()
        }
    }

    private func syncReconcileTimerOnMain() {
        let shouldRun = !displaysSleeping && (isCameraActive || isMicrophoneActive)
        if !shouldRun {
            reconcileTimer?.invalidate()
            reconcileTimer = nil
            return
        }
        guard reconcileTimer == nil else { return }
        let timer = Timer(timeInterval: Self.activeReconcileInterval, repeats: true) { [weak self] _ in
            self?.scheduleEvaluation()
        }
        timer.tolerance = Self.activeReconcileTolerance
        RunLoop.main.add(timer, forMode: .common)
        reconcileTimer = timer
    }

    private func setupNotifications() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        let center = NotificationCenter.default
        let connectToken = center.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleEvaluation(resyncCameras: true)
        }
        let disconnectToken = center.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleEvaluation(resyncCameras: true)
        }
        notificationObservers = [connectToken, disconnectToken]

        let sleepToken = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.displaysSleeping = true
            self.syncReconcileTimerOnMain()
        }
        let wakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.displaysSleeping = false
            self.scheduleEvaluation(resyncAudioDevices: true, resyncCameras: true)
            self.syncReconcileTimerOnMain()
        }
        workspaceObservers = [sleepToken, wakeToken]
    }

    private func rebuildCameraDiscoverySession() {
        cameraInUseObservations.removeAll()
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        cameraDiscoverySession = session
        cameraInUseObservations = session.devices.map { device in
            device.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] _, _ in
                self?.scheduleEvaluation()
            }
        }
    }

    private func syncCMIOListeners() {
        if cmioSystemListener == nil {
            var devicesAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                self.syncCMIOListeners()
                self.rebuildCameraDiscoverySession()
                self.evaluate()
            }
            if CMIOObjectAddPropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject),
                &devicesAddress,
                halQueue,
                block
            ) == OSStatus(kCMIOHardwareNoError) {
                cmioSystemListener = CMIOListenerRegistration(
                    objectID: CMIOObjectID(kCMIOObjectSystemObject),
                    address: devicesAddress,
                    block: block
                )
            }
        }

        let currentIDs = Set(allCMIODeviceIDs())
        let currentKeys = Set(cmioDeviceListeners.keys)
        let added = currentIDs.subtracting(currentKeys)
        let removed = currentKeys.subtracting(currentIDs)

        for deviceID in removed {
            if var registration = cmioDeviceListeners.removeValue(forKey: deviceID) {
                CMIOObjectRemovePropertyListenerBlock(
                    registration.objectID,
                    &registration.address,
                    halQueue,
                    registration.block
                )
            }
        }

        for deviceID in added {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.evaluate()
            }
            if CMIOObjectAddPropertyListenerBlock(
                deviceID,
                &runningAddress,
                halQueue,
                block
            ) == OSStatus(kCMIOHardwareNoError) {
                cmioDeviceListeners[deviceID] = CMIOListenerRegistration(
                    objectID: deviceID,
                    address: runningAddress,
                    block: block
                )
            }
        }
    }

    private func removeCMIOListeners() {
        for (_, var registration) in cmioDeviceListeners {
            CMIOObjectRemovePropertyListenerBlock(
                registration.objectID,
                &registration.address,
                halQueue,
                registration.block
            )
        }
        cmioDeviceListeners.removeAll()

        if var systemListener = cmioSystemListener {
            CMIOObjectRemovePropertyListenerBlock(
                systemListener.objectID,
                &systemListener.address,
                halQueue,
                systemListener.block
            )
            cmioSystemListener = nil
        }
    }

    private func allCMIODeviceIDs() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == OSStatus(kCMIOHardwareNoError), dataSize > 0 else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        let status = ids.withUnsafeMutableBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else {
                return OSStatus(kCMIOHardwareUnspecifiedError)
            }
            return CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address,
                0,
                nil,
                dataSize,
                &dataUsed,
                baseAddress
            )
        }
        guard status == OSStatus(kCMIOHardwareNoError) else { return [] }
        let actualCount = min(count, Int(dataUsed) / MemoryLayout<CMIOObjectID>.size)
        return Array(ids.prefix(actualCount))
    }

    private func syncAudioListeners() {
        // System-level listeners for default input and device list changes
        if !audioSystemListenersRegistered {
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
            audioSystemListenersRegistered = true
        }

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
        if audioSystemListenersRegistered {
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
            audioSystemListenersRegistered = false
        }

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

        // Only thread-safe CoreAudio HAL and AVCaptureDevice discovery queries run
        // on `halQueue`. Main-thread `@Published` state on `CameraPreviewService`
        // and `MicMuteService` is read exclusively on the main queue below.
        let micState = checkMicrophoneInUse()
        let externalCamState = checkExternalCameraInUse()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let camState = Self.internalCameraInUseOnMain() ?? externalCamState
            if self.isMicrophoneActive != micState.isActive || self.activeMicrophoneName != micState.name {
                self.isMicrophoneActive = micState.isActive
                self.activeMicrophoneName = micState.name
            }
            if self.isCameraActive != camState.isActive || self.activeCameraName != camState.name {
                self.isCameraActive = camState.isActive
                self.activeCameraName = camState.name
            }
            self.reconcileMutedStateOnMain(MicMuteService.shared.isMuted, fromPublisher: false)
            self.syncReconcileTimerOnMain()
        }

        isEvaluating = false
        if pendingEvaluation {
            pendingEvaluation = false
            halQueue.async { [weak self] in
                self?.evaluate()
            }
        }
    }

    private static func internalCameraInUseOnMain() -> (isActive: Bool, name: String?)? {
        guard let session = CameraPreviewService.shared.session, session.isRunning else { return nil }
        let selectedID = CameraPreviewService.shared.selectedDeviceID
        let device = CameraPreviewService.shared.devices.first { $0.uniqueID == selectedID }
        let name = device?.localizedName ?? "FaceTime HD Camera"
        return (true, name)
    }

    private func checkExternalCameraInUse() -> (isActive: Bool, name: String?) {
        // Check cached system camera devices used by other applications.
        if cameraDiscoverySession == nil {
            rebuildCameraDiscoverySession()
        }
        if let session = cameraDiscoverySession {
            for device in session.devices where device.isInUseByAnotherApplication {
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
