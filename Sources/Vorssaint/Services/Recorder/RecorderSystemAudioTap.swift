// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AVFoundation
import CoreAudio
import Darwin

/// A flag the audio thread raises and another thread reads later.
final class RecorderAudioFlag {
    private var bits: Int32 = 0

    var value: Bool { OSAtomicAdd32Barrier(0, &bits) != 0 }

    func raise() {
        OSAtomicCompareAndSwap32Barrier(0, 1, &bits)
    }
}

/// A host time one thread stores and others read, 0 for none.
final class RecorderAudioHostTime {
    private var bits: Int64 = 0

    var value: UInt64 {
        get { UInt64(bitPattern: OSAtomicAdd64Barrier(0, &bits)) }
        set {
            let replacement = Int64(bitPattern: newValue)
            while true {
                let current = OSAtomicAdd64Barrier(0, &bits)
                if OSAtomicCompareAndSwap64Barrier(current, replacement, &bits) { return }
            }
        }
    }
}

/// Pre-allocated lock-free SPSC ring buffer transferring raw float audio frames
/// and host timestamps from CoreAudio's real-time `HALB_IOThread` to the serial
/// consumer/writer queue with zero heap allocation or lock contention.
final class RecorderAudioSampleRing: @unchecked Sendable {
    struct SlotMeta {
        var sampleCount: Int32 = 0
        var inputHostTime: UInt64 = 0
        var nowHostTime: UInt64 = 0
        var hasInputHostTime: Bool = false
    }

    let slotCount: Int
    let maxSamplesPerSlot: Int
    private let slotMask: Int64
    private let sampleStorage: UnsafeMutablePointer<Float>
    private let metaStorage: UnsafeMutablePointer<SlotMeta>
    private var writeIndex: Int64 = 0
    private var readIndex: Int64 = 0

    init(slotCount: Int = 64, maxFramesPerSlot: Int = 8192, channels: Int) {
        var power = 2
        while power < max(2, slotCount) { power <<= 1 }
        self.slotCount = power
        self.slotMask = Int64(power - 1)
        self.maxSamplesPerSlot = max(1, maxFramesPerSlot * max(1, channels))
        self.sampleStorage = UnsafeMutablePointer<Float>.allocate(capacity: power * self.maxSamplesPerSlot)
        self.sampleStorage.initialize(repeating: 0, count: power * self.maxSamplesPerSlot)
        self.metaStorage = UnsafeMutablePointer<SlotMeta>.allocate(capacity: power)
        self.metaStorage.initialize(repeating: SlotMeta(), count: power)
    }

    deinit {
        metaStorage.deinitialize(count: slotCount)
        metaStorage.deallocate()
        sampleStorage.deinitialize(count: slotCount * maxSamplesPerSlot)
        sampleStorage.deallocate()
    }

    /// Producer (`HALB_IOThread` only): copies float samples into fixed pre-allocated
    /// ring slots without allocating or blocking. Drops excess if consumer falls behind.
    @discardableResult
    func push(samples: UnsafeRawPointer,
              byteCount: Int,
              channels: Int,
              inputHostTime: UInt64,
              hasInputHostTime: Bool,
              nowHostTime: UInt64,
              hostTicksPerFrame: Double = 0) -> Bool {
        let safeChannels = max(1, channels)
        let totalFrames = byteCount / (safeChannels * MemoryLayout<Float>.size)
        guard totalFrames > 0 else { return false }
        let maxFrames = maxSamplesPerSlot / safeChannels
        guard maxFrames > 0 else { return false }

        var frameOffset = 0
        var pushedAny = false
        while frameOffset < totalFrames {
            let w = OSAtomicAdd64Barrier(0, &writeIndex)
            let r = OSAtomicAdd64Barrier(0, &readIndex)
            if w - r >= Int64(slotCount) { break }

            let chunkFrames = min(maxFrames, totalFrames - frameOffset)
            let chunkSamples = chunkFrames * safeChannels
            let slot = Int(w & slotMask)
            let dst = sampleStorage.advanced(by: slot * maxSamplesPerSlot)
            let src = samples.advanced(by: frameOffset * safeChannels * MemoryLayout<Float>.size)
            memcpy(dst, src, chunkSamples * MemoryLayout<Float>.size)

            let adjustedInputHostTime: UInt64
            if hasInputHostTime, frameOffset > 0, hostTicksPerFrame > 0 {
                adjustedInputHostTime = inputHostTime &+ UInt64((Double(frameOffset) * hostTicksPerFrame).rounded())
            } else {
                adjustedInputHostTime = inputHostTime
            }
            metaStorage[slot] = SlotMeta(
                sampleCount: Int32(chunkSamples),
                inputHostTime: adjustedInputHostTime,
                nowHostTime: nowHostTime,
                hasInputHostTime: hasInputHostTime
            )
            OSAtomicAdd64Barrier(1, &writeIndex)
            pushedAny = true
            frameOffset += chunkFrames
        }
        return pushedAny
    }

    /// Consumer (serial consumer/writer queue only): reads the next queued slot in place.
    func drainOne(_ body: (UnsafeMutablePointer<Float>, Int, UInt64, Bool, UInt64) -> Void) -> Bool {
        let r = OSAtomicAdd64Barrier(0, &readIndex)
        let w = OSAtomicAdd64Barrier(0, &writeIndex)
        guard r < w else { return false }
        let slot = Int(r & slotMask)
        let meta = metaStorage[slot]
        let ptr = sampleStorage.advanced(by: slot * maxSamplesPerSlot)
        body(ptr, Int(meta.sampleCount), meta.inputHostTime, meta.hasInputHostTime, meta.nowHostTime)
        OSAtomicAdd64Barrier(1, &readIndex)
        return true
    }
}

/// Whether linear float audio holds anything but silence.
enum RecorderAudioProbe {
    static func containsSound(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              stream.mFormatID == kAudioFormatLinearPCM,
              stream.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              stream.mBitsPerChannel == 32
        else { return false }
        let heard = try? sampleBuffer.withAudioBufferList(blockBufferMemoryAllocator: nil,
                                                          flags: []) { list, _ in
            list.contains { containsSound($0) }
        }
        return heard ?? false
    }

    /// One vectorised pass and no allocation, so the audio thread can ask.
    static func containsSound(_ buffer: AudioBuffer) -> Bool {
        guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { return false }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return false }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        return peak > 0
    }
}

/// The sound of the Mac for a recording, read from the audio system as one
/// mix of every process but this one. A recording of one window hears only
/// the app that owns it, so the sound follows the picture. An app that has
/// not played since it launched has no audio process to tap yet, so its tap
/// is built when the first one appears.
///
/// ScreenCaptureKit hands over the same mix, but an app the volume mixer
/// adjusts reaches it twice: its own muted stream and this app's re-render
/// of it, about 30 ms apart, and excluding this app from the stream's filter
/// does not drop that re-render (measured 2026-09-01, issue #692). A process
/// tap that excludes this process hears each app once.
///
/// Reading a tap needs an audio permission of its own. It is asked for at
/// the first start and, while missing, answered with silence rather than an
/// error, so the session keeps the stream's sound as the written source until
/// this tap has heard sound over a whole recording.
///
/// The tap's stereo mixdown loses level on outputs with more than two
/// channels, which `followProcesses` gives back.
///
/// Every mutable field is touched only on `queue`, except `heard`,
/// `pipelineStarted`, `ran` and `levelCompensation`, which are atomic, and
/// `onSample`, which the caller sets once before `start`. That confinement
/// is what makes the reference safe to hand across threads.
final class RecorderSystemAudioTap: @unchecked Sendable {
    /// Called on `consumerQueue` (off the real-time audio thread), with the
    /// sound retimed onto the recording's clock. Set before `start`.
    var onSample: ((CMSampleBuffer) -> Void)?

    /// Serial queue that drains the real-time ring buffer, builds `CMSampleBuffer`s,
    /// and invokes `onSample`. Set before `start` (defaults to an internal serial queue).
    var consumerQueue: DispatchQueue?

    /// Called on this tap's own queue when a device or process change left it
    /// without a reader, so the recording can go back to the stream's sound
    /// instead of falling silent. Set before `start`.
    var onReaderLost: (() -> Void)?

    /// Whether any sample was more than silence. Read after `stop`.
    var heardSound: Bool { heard.value }

    /// Whether the tap hears one app rather than the whole Mac.
    var hearsOneApp: Bool { pid != nil }

    /// The host time the current pipeline started, or 0 while there is none:
    /// before `start`, while an app's tap waits for its app or is made again,
    /// after a rebuild that failed and after `stop`.
    var pipelineStart: UInt64 { pipelineStarted.value }

    /// Whether any pipeline started, so the tap could hear at all. Read after
    /// `stop`.
    var ranPipeline: Bool { ran.value }

    private let queue: DispatchQueue
    private let heard = RecorderAudioFlag()
    private let pipelineStarted = RecorderAudioHostTime()
    private let ran = RecorderAudioFlag()
    private let ownProcess: AudioObjectID
    /// The one app to hear, or nothing for the whole Mac.
    private let pid: pid_t?
    private var tapID = AudioObjectID(0)
    private var tapUID = ""
    private var tapChannels = 2
    /// The processes an app's tap was built from, to notice when they change.
    private var tapped: [AudioObjectID] = []
    /// An app's tap made before the app first played, built by the process
    /// list listener once one of the app's audio processes appears.
    private var awaitingApp = false
    private var clock: CMClock?
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var sampleSource: DispatchSourceUserDataAdd?
    private var sampleDrain: (() -> Void)?
    private var activeConsumerQueue: DispatchQueue?
    private var hostDeviceUID: String?
    private var sampleRate: Double = 0
    /// Name the default output, sample rate and process list listeners. See
    /// `AudioListenerClients`.
    private var deviceListenerClient: UnsafeMutableRawPointer?
    private var rateListenerClient: UnsafeMutableRawPointer?
    private var processListenerClient: UnsafeMutableRawPointer?
    private var stopped = false
    /// What the mixdown took from the sound, given back to every sample.
    private let levelCompensation = AtomicFloatBox(1)
    private var levelWatch: LevelCompensationWatch?

    /// Destroying a device or a tap can park inside a broken audio path, so
    /// it never happens on a queue anything waits for. Serial, so the device
    /// that hosts a tap is always gone before the tap itself.
    private static let teardownQueue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio.teardown",
                                                     qos: .utility)
    /// The global listener must not wait behind a device destruction that
    /// can remain stuck for the rest of the session.
    private static let listenerQueue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio.listeners",
                                                     qos: .utility)

    /// The tap, or nothing when the audio system refuses one. A `pid` narrows
    /// it to that app's sound.
    static func make(hearing pid: pid_t?) async -> RecorderSystemAudioTap? {
        guard #available(macOS 14.4, *) else { return nil }
        let queue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio",
                                  qos: .userInitiated)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: RecorderSystemAudioTap(queue: queue, pid: pid))
            }
        }
    }

    @available(macOS 14.4, *)
    private init?(queue: DispatchQueue, pid: pid_t?) {
        self.queue = queue
        self.pid = pid
        guard let ownProcess = Self.processObject(for: ProcessInfo.processInfo.processIdentifier)
        else { return nil }
        self.ownProcess = ownProcess
        // Listed once, so the tap is built from the processes just checked.
        let gathered = pid.map { Self.processObjects(for: $0, excluding: ownProcess) }
        if gathered?.isEmpty == true {
            // Nothing of the app reaches the audio system yet, so it is
            // silent until one of its processes connects.
            awaitingApp = true
            return
        }
        guard buildTap(around: gathered) else { return nil }
    }

    /// One app's processes for a recording of its window, `gathered` when
    /// the caller just listed them, or every process but this one.
    @available(macOS 14.4, *)
    private func buildTap(around gathered: [AudioObjectID]? = nil) -> Bool {
        let description: CATapDescription
        if let pid {
            let objects = gathered ?? Self.processObjects(for: pid, excluding: ownProcess)
            guard !objects.isEmpty else { return false }
            tapped = objects
            description = CATapDescription(stereoMixdownOfProcesses: objects)
        } else {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        }
        description.name = "Vorssaint Recorder"
        description.isPrivate = true
        var tapID = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            return false
        }
        self.tapID = tapID
        tapUID = description.uuid.uuidString
        var format = AudioStreamBasicDescription()
        tapChannels = Self.read(tapID, kAudioTapPropertyFormat, &format) && format.mChannelsPerFrame > 0
            ? Int(format.mChannelsPerFrame)
            : 2
        return true
    }

    deinit {
        // A stopped tap's ID may already belong to another tap.
        let tapID = stopped ? 0 : self.tapID
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        sampleSource?.cancel()
        levelWatch?.stop()
        Self.removeListener(deviceListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                            kAudioHardwarePropertyDefaultOutputDevice)
        Self.removeListener(processListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                            kAudioHardwarePropertyProcessObjectList)
        Self.removeListener(rateListenerClient, from: aggregateID, kAudioDevicePropertyNominalSampleRate)
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: tapID)
    }

    // MARK: - Lifecycle

    /// Starts delivering and answers whether a reader is now running. The
    /// first start on a Mac may raise the system's audio permission prompt;
    /// until it is granted, the reader runs but every buffer is silent.
    /// A false answer means no reader exists, so its sound must come from
    /// elsewhere for this recording. A tap waiting for its app to play
    /// answers true: the app is silent until then.
    @discardableResult
    func start(synchronizingTo clock: CMClock) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.clock = clock
                if !stopped {
                    if !awaitingApp {
                        // Read before the first cycle, so the head of the
                        // file already has its level.
                        followProcesses()
                        buildPipeline()
                    }
                    watchDefaultOutputDevice()
                    watchProcessList()
                }
                continuation.resume(returning: aggregateID != 0 || awaitingApp)
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // Cancelling startup stops the tap there and again when the
                // session finishes. The HAL may already have reused its ID.
                guard !stopped else { continuation.resume(); return }
                stopped = true
                Self.removeListener(deviceListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                                    kAudioHardwarePropertyDefaultOutputDevice)
                deviceListenerClient = nil
                Self.removeListener(processListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                                    kAudioHardwarePropertyProcessObjectList)
                processListenerClient = nil
                levelWatch?.stop()
                levelWatch = nil
                teardownPipeline()
                Self.destroy(aggregateID: 0, ioProc: nil, tapID: tapID)
                continuation.resume()
            }
        }
    }

    // MARK: - Pipeline

    /// The tap needs an aggregate device to be read through, and that device
    /// needs a real one beneath it for its clock: the default output, as the
    /// volume mixer does.
    private func buildPipeline() {
        guard aggregateID == 0, let clock,
              let hostUID = Self.hostDeviceUID() else { return }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vorssaint Recorder",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: hostUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: hostUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        var aggregateID = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else { return }
        let sampleRate = Self.nominalSampleRate(of: aggregateID)
        guard let format = Self.format(sampleRate: sampleRate, channels: tapChannels) else {
            Self.destroy(aggregateID: aggregateID, ioProc: nil, tapID: 0)
            return
        }

        // Pre-allocate the SPSC ring buffer and coalescing dispatch source before
        // `AudioDeviceStart` so `HALB_IOThread` never allocates heap memory,
        // constructs `CMSampleBuffer`s, or dispatches async closures per cycle.
        let channels = tapChannels
        let heard = self.heard
        let onSample = self.onSample
        let compensation = levelCompensation
        let ramp = TapLevelRamp()
        let limiter = LimiterState(release: BoostLimiter.release(sampleRate: sampleRate))
        let timescale = CMTimeScale(sampleRate.rounded())
        let hostClock = CMClockGetHostTimeClock()
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let hostFrequency = timebase.numer > 0 ? 1_000_000_000.0 * Double(timebase.denom) / Double(timebase.numer) : 0
        let hostTicksPerFrame = sampleRate > 0 ? hostFrequency / sampleRate : 0
        let ring = RecorderAudioSampleRing(slotCount: 64, maxFramesPerSlot: 8192, channels: channels)
        let targetQueue = consumerQueue
            ?? DispatchQueue(label: "com.vorssaint.recorder.systemaudio.consumer", qos: .userInitiated)
        let source = DispatchSource.makeUserDataAddSource(queue: targetQueue)
        let drainSamples: () -> Void = {
            guard let onSample else {
                while ring.drainOne({ _, _, _, _, _ in }) {}
                return
            }
            while ring.drainOne({ samples, sampleCount, inputHostTime, hasInputHostTime, nowHostTime in
                let gain = ramp.next(toward: compensation.value, hostTime: nowHostTime)
                if gain > 1 {
                    RecorderSupport.restoreTapLevel(samples, count: sampleCount, channels: channels,
                                                    gain: gain, limiter: &limiter.limiter,
                                                    release: limiter.release)
                } else {
                    limiter.limiter = BoostLimiter()
                }
                let hostTime = hasInputHostTime
                    ? CMClockMakeHostTimeFromSystemUnits(inputHostTime)
                    : CMClockMakeHostTimeFromSystemUnits(nowHostTime)
                let time = CMSyncConvertTime(hostTime, from: hostClock, to: clock)
                guard time.isValid else { return }
                let buffer = AudioBuffer(
                    mNumberChannels: UInt32(channels),
                    mDataByteSize: UInt32(sampleCount * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(samples)
                )
                guard let sample = Self.sampleBuffer(from: buffer, format: format,
                                                     timescale: timescale, time: time)
                else { return }
                onSample(sample)
            }) {}
        }
        source.setEventHandler(handler: drainSamples)
        source.resume()

        var ioProc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) {
            now, input, inputTime, output, _ in
            // The device beneath the aggregate would otherwise play whatever
            // this memory last held.
            MixerRender.silence(UnsafeMutableAudioBufferListPointer(output))
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let index = MixerRender.tapBufferIndex(in: inputBuffers, tapChannels: channels)
            else { return }
            let buffer = inputBuffers[index]
            if !heard.value, RecorderAudioProbe.containsSound(buffer) { heard.raise() }
            guard onSample != nil, let rawData = buffer.mData, buffer.mDataByteSize > 0 else { return }
            if ring.push(samples: rawData,
                         byteCount: Int(buffer.mDataByteSize),
                         channels: channels,
                         inputHostTime: inputTime.pointee.mHostTime,
                         hasInputHostTime: inputTime.pointee.mFlags.contains(.hostTimeValid),
                         nowHostTime: now.pointee.mHostTime,
                         hostTicksPerFrame: hostTicksPerFrame) {
                source.add(data: 1)
            }
        }
        guard created == noErr, let ioProc,
              AudioDeviceStart(aggregateID, ioProc) == noErr else {
            source.cancel()
            Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
            return
        }
        self.aggregateID = aggregateID
        self.ioProc = ioProc
        self.sampleSource = source
        self.sampleDrain = drainSamples
        self.activeConsumerQueue = targetQueue
        hostDeviceUID = hostUID
        self.sampleRate = sampleRate
        pipelineStarted.value = mach_absolute_time()
        ran.raise()
        watchSampleRate(of: aggregateID)
    }

    private func teardownPipeline() {
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        let rateListenerClient = self.rateListenerClient
        let sampleSource = self.sampleSource
        let sampleDrain = self.sampleDrain
        let activeConsumerQueue = self.activeConsumerQueue
        self.aggregateID = 0
        self.ioProc = nil
        self.rateListenerClient = nil
        self.sampleSource = nil
        self.sampleDrain = nil
        self.activeConsumerQueue = nil
        hostDeviceUID = nil
        pipelineStarted.value = 0
        guard aggregateID != 0 else {
            sampleSource?.cancel()
            return
        }
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
        }
        if let activeConsumerQueue {
            activeConsumerQueue.async {
                sampleDrain?()
                sampleSource?.cancel()
            }
        } else {
            sampleSource?.cancel()
        }
        Self.removeListener(rateListenerClient, from: aggregateID, kAudioDevicePropertyNominalSampleRate)
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
    }

    /// Headphones that come and go, or a device that changes its rate for a
    /// call, would otherwise leave the rest of the recording silent or at
    /// the wrong pitch. Only a real change rebuilds, so the notifications a
    /// rebuild itself raises settle instead of looping.
    private func rebuildPipelineIfChanged() {
        guard !stopped, aggregateID != 0 else { return }
        let hostChanged = Self.hostDeviceUID() != hostDeviceUID
        let rateChanged = Self.nominalSampleRate(of: aggregateID) != sampleRate
        guard hostChanged || rateChanged else { return }
        teardownPipeline()
        buildPipeline()
        // Nothing came back, and with no aggregate left this tap can no longer
        // see a later change, so the rest of the recording needs the stream.
        if aggregateID == 0 { onReaderLost?() }
    }

    /// A browser makes its sound in a helper process that comes and goes with
    /// its tabs, and a tap hears only the processes it was built from, so an
    /// app's tap is made again around its processes as they are now, and its
    /// level is read from them. Only a real change rebuilds, because any app
    /// launching stirs the same list. A tap waiting for its app is built the
    /// first time one of the app's processes appears.
    private func rebuildTapIfProcessesChanged() {
        guard !stopped, let pid, #available(macOS 14.4, *) else { return }
        let current = Self.processObjects(for: pid, excluding: ownProcess)
        if awaitingApp {
            guard !current.isEmpty, clock != nil else { return }
            awaitingApp = false
            if buildTap(around: current) {
                followProcesses()
                buildPipeline()
            }
            if aggregateID == 0 { onReaderLost?() }
            return
        }
        guard aggregateID != 0,
              RecorderSupport.rebuildsAppTap(tapped: Set(tapped), current: Set(current)) else { return }
        teardownPipeline()
        Self.destroy(aggregateID: 0, ioProc: nil, tapID: tapID)
        // The HAL may hand this ID to another tap from here on.
        tapID = 0
        levelWatch?.stop()
        levelWatch = nil
        if buildTap(around: current) {
            followProcesses()
            buildPipeline()
        }
        if aggregateID == 0 { onReaderLost?() }
    }

    private func watchProcessList() {
        guard pid != nil, processListenerClient == nil else { return }
        processListenerClient = listen(to: AudioObjectID(kAudioObjectSystemObject),
                                       kAudioHardwarePropertyProcessObjectList)
        // The app may have opened a helper since the tap was made.
        rebuildTapIfProcessesChanged()
    }

    private func watchDefaultOutputDevice() {
        guard deviceListenerClient == nil else { return }
        deviceListenerClient = listen(to: AudioObjectID(kAudioObjectSystemObject),
                                      kAudioHardwarePropertyDefaultOutputDevice)
    }

    private func watchSampleRate(of aggregateID: AudioObjectID) {
        rateListenerClient = listen(to: aggregateID, kAudioDevicePropertyNominalSampleRate)
    }

    /// Registers `pipelineDeviceChanged` for one property under a client
    /// number, or nothing when the HAL refuses.
    private func listen(to object: AudioObjectID,
                        _ selector: AudioObjectPropertySelector) -> UnsafeMutableRawPointer? {
        let client = AudioListenerClients.reserve(for: self)
        var address = Self.address(selector)
        guard AudioObjectAddPropertyListener(object, &address, Self.pipelineDeviceChanged,
                                             client) == noErr else {
            AudioListenerClients.forget(client)
            return nil
        }
        return client
    }

    /// The default output and the aggregate's rate ask the same question: is
    /// the tap still read through the device the sound plays on. The process
    /// list asks whether an app's tap still holds that app's processes. Each
    /// check rebuilds only on a real change, so both answer every listener.
    private static let pipelineDeviceChanged: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let tap = AudioListenerClients.owner(of: client) as? RecorderSystemAudioTap else {
            return noErr
        }
        tap.queue.async { [weak tap] in
            tap?.rebuildPipelineIfChanged()
            tap?.rebuildTapIfProcessesChanged()
        }
        return noErr
    }

    /// Forgets the client at once, so a callback on its way finds nothing,
    /// and gives the global registration back independently of device
    /// destruction. A rate listener still goes on the teardown queue ahead
    /// of the aggregate it listens to.
    private static func removeListener(_ client: UnsafeMutableRawPointer?, from object: AudioObjectID,
                                       _ selector: AudioObjectPropertySelector) {
        guard let client else { return }
        AudioListenerClients.forget(client)
        let removalQueue = object == AudioObjectID(kAudioObjectSystemObject)
            ? listenerQueue
            : teardownQueue
        removalQueue.async {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListener(object, &address, Self.pipelineDeviceChanged, client)
        }
    }

    // MARK: - Level

    /// Keeps the level the tap gives back right for where the processes it
    /// hears play: every other one for the whole Mac, the app's own for an
    /// app's tap.
    ///
    /// The stereo mixdown divides what a process plays on an output with more
    /// than two channels by that output's channel pairs, a known system issue
    /// (FB13479345), so a recording made with a TV over HDMI or an audio
    /// interface as the output came out at a half or a quarter of its level.
    /// The mix holds every process wherever it plays (measured 2026-10-07:
    /// two apps on two outputs, neither of them the default, both reached it
    /// whole), so the correction is read from all of them, and the narrowest
    /// output decides, as in the mixer: no process is ever recorded louder
    /// than it plays. One gain cannot suit outputs of different widths at
    /// once, so while an app holds a narrower output, the rest keeps the
    /// level it had before this correction. The watch follows processes that
    /// come or go, since a video started during the recording can play
    /// through one the first read never saw.
    private func followProcesses() {
        guard !stopped, levelWatch == nil else { return }
        let compensation = levelCompensation
        let store: (Float) -> Void = { compensation.value = $0 }
        // An app's tap is read like one of the mixer's, from its own processes.
        let watch = pid == nil
            ? LevelCompensationWatch.started(everyProcessExcept: [ownProcess], store: store)
            : LevelCompensationWatch.started(objects: tapped, store: store)
        // Briefly, as the mixer's engines do, so the head of the file
        // already has its level.
        watch.waitForFirstRead()
        levelWatch = watch
    }

    private static func destroy(aggregateID: AudioObjectID,
                                ioProc: AudioDeviceIOProcID?,
                                tapID: AudioObjectID) {
        guard aggregateID != 0 || tapID != 0 else { return }
        teardownQueue.async {
            if aggregateID != 0 {
                if let ioProc {
                    AudioDeviceDestroyIOProcID(aggregateID, ioProc)
                }
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID != 0, #available(macOS 14.4, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    // MARK: - Samples

    /// The limiter's memory, touched only on the audio thread.
    private final class LimiterState {
        var limiter = BoostLimiter()
        let release: Float

        init(release: Float) {
            self.release = release
        }
    }

    /// The samples a buffer just made holds, to change in place before anyone
    /// else sees them.
    private static func withSamples(of sampleBuffer: CMSampleBuffer,
                                    _ body: (UnsafeMutablePointer<Float>, Int) -> Void) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var data: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length,
                                          totalLengthOut: nil,
                                          dataPointerOut: &data) == kCMBlockBufferNoErr,
              let data else { return }
        let count = length / MemoryLayout<Float>.size
        data.withMemoryRebound(to: Float.self, capacity: count) { body($0, count) }
    }

    private static func format(sampleRate: Double, channels: Int) -> CMAudioFormatDescription? {
        guard sampleRate > 0, channels > 0 else { return nil }
        let bytesPerFrame = UInt32(channels * MemoryLayout<Float>.size)
        var stream = AudioStreamBasicDescription(mSampleRate: sampleRate,
                                                 mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat
                                                     | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: bytesPerFrame,
                                                 mFramesPerPacket: 1,
                                                 mBytesPerFrame: bytesPerFrame,
                                                 mChannelsPerFrame: UInt32(channels),
                                                 mBitsPerChannel: 32,
                                                 mReserved: 0)
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                             asbd: &stream,
                                             layoutSize: 0,
                                             layout: nil,
                                             magicCookieSize: 0,
                                             magicCookie: nil,
                                             extensions: nil,
                                             formatDescriptionOut: &description) == noErr
        else { return nil }
        return description
    }

    /// The samples copied out of the audio system's buffer, which is reused
    /// as soon as this cycle returns.
    private static func sampleBuffer(from buffer: AudioBuffer,
                                     format: CMAudioFormatDescription,
                                     timescale: CMTimeScale,
                                     time: CMTime) -> CMSampleBuffer? {
        let frames = MixerRender.frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels)
        guard frames > 0 else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: timescale),
                                        presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                   dataBuffer: nil,
                                   dataReady: false,
                                   makeDataReadyCallback: nil,
                                   refcon: nil,
                                   formatDescription: format,
                                   sampleCount: frames,
                                   sampleTimingEntryCount: 1,
                                   sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0,
                                   sampleSizeArray: nil,
                                   sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer
        else { return nil }
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: &list) == noErr
        else { return nil }
        return sampleBuffer
    }

    // MARK: - Audio system

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    /// Every audio process the app answers for. A browser makes its sound in
    /// a helper process, so a tap on the app's own pid alone would never hear
    /// it; the mixer and the island's level reader gather theirs the same way.
    /// The audio system lists only processes connected to it, so an app that
    /// has not played since it launched has none. Sound the system plays for
    /// an app from a process of its own, such as a call, is not the app's
    /// and stays out. This process is left out even when the app answers for
    /// it, as a terminal does for what it starts, since it plays the mixer's
    /// re-render of every other app.
    @available(macOS 14.4, *)
    private static func processObjects(for pid: pid_t, excluding own: AudioObjectID) -> [AudioObjectID] {
        var objects: [AudioObjectID] = []
        for object in AppVolumeMixer.audioProcessObjects() where object != own {
            var owner: pid_t = -1
            guard read(object, kAudioProcessPropertyPID, &owner), owner > 0,
                  owner == pid || ResponsibleProcess.regularAppOwner(of: owner)?.processIdentifier == pid
            else { continue }
            objects.append(object)
        }
        return objects
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(0)
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<pid_t>.size), pidPointer,
                                       &size, &object)
        }
        guard status == noErr, object != 0 else { return nil }
        return object
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var sampleRate: Float64 = 0
        guard read(deviceID, kAudioDevicePropertyNominalSampleRate, &sampleRate), sampleRate > 0
        else { return 48_000 }
        return sampleRate
    }

    /// The device that clocks the aggregate: the current default output, the
    /// same choice the volume mixer makes. A device that also records puts
    /// its input in front of the tap in the buffer list, which the shared
    /// `MixerRender.tapBufferIndex` already steps over.
    private static func readCFString(_ object: AudioObjectID,
                                     _ selector: AudioObjectPropertySelector,
                                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var address = address(selector, scope: scope)
        var unmanagedRef: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanagedRef) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr else { return nil }
        return unmanagedRef?.takeRetainedValue() as String?
    }

    private static func hostDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultOutputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        return readCFString(defaultDevice, kAudioDevicePropertyDeviceUID)
    }
}
