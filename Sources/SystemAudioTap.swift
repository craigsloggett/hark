import AudioToolbox
import AVFoundation
import OSLog

/// Captures all system audio output to a file using a Core Audio process tap.
///
/// Tapped audio is delivered on `ioQueue`, where it is resampled into a fixed canonical format and written
/// to the output file. `controlQueue` owns the Core Audio object lifecycle and the sample-rate listener, and
/// publishes new capture state to the IOProc under `ioQueue.sync`. That queue isolation keeps the non-`Sendable`
/// `AVAudioFile` and `AVAudioConverter` safe to hand across actors.
final class SystemAudioTap: @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case propertyReadFailed(OSStatus)
        case tapCreationFailed(OSStatus)
        case aggregateDeviceCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case unsupportedStreamFormat
        case converterCreationFailed

        var description: String {
            switch self {
            case let .propertyReadFailed(status): "Core Audio property read failed (\(status))"
            case let .tapCreationFailed(status): "Process tap creation failed (\(status))"
            case let .aggregateDeviceCreationFailed(status): "Aggregate device creation failed (\(status))"
            case let .ioProcCreationFailed(status): "Audio I/O proc creation failed (\(status))"
            case let .deviceStartFailed(status): "Audio device failed to start (\(status))"
            case .unsupportedStreamFormat: "The system audio tap reported an unsupported stream format"
            case .converterCreationFailed: "Could not build an audio converter for the tap format"
            }
        }
    }

    /// Sample at 16 kHz mono Int16, independent of the device's live rate. The fixed, valid
    /// arguments mean the failable initializer never returns nil.
    private static let canonicalFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    private let logger = Logger(subsystem: "com.craigsloggett.hark", category: "SystemAudioTap")

    private let ioQueue = DispatchQueue(label: "com.craigsloggett.hark.system-audio-tap", qos: .userInitiated)
    private let controlQueue = DispatchQueue(label: "com.craigsloggett.hark.system-audio-tap.control")

    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    private var firstAudioWallTime: Date?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var rateListener: AudioObjectPropertyListenerBlock?
    private var nominalSampleRateAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// Flip to true to emit per-second IOProc liveness at .debug level.
    private let logsTapActivity = false

    private var tapCallbackCount = 0
    private var tapFrameCount = 0
    private var tapSawSignal = false
    private var activityTimer: DispatchSourceTimer?

    func start(writingTo url: URL) throws {
        ioQueue.sync { firstAudioWallTime = nil }
        file = try AVAudioFile(
            forWriting: url,
            settings: Self.canonicalFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        outputDeviceID = try defaultSystemOutputDeviceID()
        try controlQueue.sync { try buildCaptureChain() }
        registerRateListener()
        if logsTapActivity { startActivityTimer() }
    }

    func stop() {
        stopActivityTimer()
        removeRateListener()
        controlQueue.sync { teardownCaptureChain() }

        ioQueue.sync {
            file = nil
            converter = nil
            inputFormat = nil
        }
        outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    func firstAudioTime() -> Date? {
        ioQueue.sync { firstAudioWallTime }
    }

    // MARK: Capture

    private func buildCaptureChain() throws {
        let tapUUID = try createProcessTap()

        var streamDescription = try tapStreamFormat(tapID)
        guard let tapFormat = AVAudioFormat(streamDescription: &streamDescription) else {
            throw Failure.unsupportedStreamFormat
        }
        guard let converter = AVAudioConverter(from: tapFormat, to: Self.canonicalFormat) else {
            throw Failure.converterCreationFailed
        }

        try createAggregateDevice(tapUUID: tapUUID)

        var ioProcID: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, ioQueue, makeIOBlock())
        guard status == noErr, let ioProcID else { throw Failure.ioProcCreationFailed(status) }
        self.ioProcID = ioProcID

        ioQueue.sync {
            self.inputFormat = tapFormat
            self.converter = converter
        }

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else { throw Failure.deviceStartFailed(status) }
    }

    private func teardownCaptureChain() {
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            if let ioProcID {
                AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
                self.ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func makeIOBlock() -> AudioDeviceIOBlock {
        { [weak self] _, inputData, _, _, _ in
            guard let self else { return }
            if logsTapActivity { tapCallbackCount += 1 }
            guard let file, let converter, let inputFormat,
                  let inputBuffer = AVAudioPCMBuffer(
                      pcmFormat: inputFormat,
                      bufferListNoCopy: inputData,
                      deallocator: nil
                  )
            else { return }

            if logsTapActivity { recordTapActivity(inputBuffer) }
            guard inputBuffer.frameLength > 0 else { return }
            if firstAudioWallTime == nil { firstAudioWallTime = Date() }
            resampleAndWrite(inputBuffer, to: file, using: converter)
        }
    }

    private func recordTapActivity(_ inputBuffer: AVAudioPCMBuffer) {
        tapFrameCount += Int(inputBuffer.frameLength)
        if !tapSawSignal, Self.bufferHasSignal(inputBuffer) {
            tapSawSignal = true
        }
    }

    private func resampleAndWrite(
        _ inputBuffer: AVAudioPCMBuffer,
        to file: AVAudioFile,
        using converter: AVAudioConverter
    ) {
        let capacity = Self.outputCapacity(
            inputFrames: inputBuffer.frameLength,
            inputSampleRate: inputBuffer.format.sampleRate,
            outputSampleRate: Self.canonicalFormat.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: Self.canonicalFormat, frameCapacity: capacity)
        else { return }

        nonisolated(unsafe) let input = inputBuffer
        nonisolated(unsafe) var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return input
        }

        if let conversionError {
            logger.error("System audio conversion failed: \(conversionError, privacy: .public)")
            return
        }
        guard status == .haveData || status == .inputRanDry, outputBuffer.frameLength > 0 else { return }
        do {
            try file.write(from: outputBuffer)
        } catch {
            logger.error("Failed to write system audio buffer: \(error, privacy: .public)")
        }
    }

    private static let resamplerLatencySlackFrames: AVAudioFrameCount = 16

    /// Frames the resampled buffer can hold, with slack for the sample-rate converter's internal latency.
    static func outputCapacity(
        inputFrames: AVAudioFrameCount,
        inputSampleRate: Double,
        outputSampleRate: Double
    ) -> AVAudioFrameCount {
        let ratio = outputSampleRate / inputSampleRate
        return AVAudioFrameCount(Double(inputFrames) * ratio) + Self.resamplerLatencySlackFrames
    }

    // MARK: Rate Listener

    private func registerRateListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleRateChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            outputDeviceID,
            &nominalSampleRateAddress,
            controlQueue,
            listener
        )
        guard status == noErr else {
            logger.error("Could not observe output sample rate (\(status)); mid-recording rate changes are unhandled")
            return
        }
        rateListener = listener
    }

    private func removeRateListener() {
        guard let rateListener else { return }
        AudioObjectRemovePropertyListenerBlock(outputDeviceID, &nominalSampleRateAddress, controlQueue, rateListener)
        self.rateListener = nil
    }

    private func handleRateChange() {
        let previousRate = ioQueue.sync { inputFormat?.sampleRate } ?? 0
        teardownCaptureChain()
        do {
            try buildCaptureChain()
            let newRate = ioQueue.sync { inputFormat?.sampleRate } ?? 0
            logger.log("Rebuilt system audio tap after output rate change (\(previousRate) -> \(newRate) Hz)")
        } catch {
            logger.error("Failed to rebuild system audio tap after rate change: \(error, privacy: .public)")
        }
    }
}

// MARK: Activity

extension SystemAudioTap {
    /// Logs IOProc liveness once per second (gated by `logsTapActivity`):
    /// zero callbacks means the device stalled
    /// callbacks with zero frames means the tap data path died
    /// signal=false on nonzero frames means only silence arrived
    private func startActivityTimer() {
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + 1, repeating: .seconds(1))
        timer.setEventHandler { [weak self] in self?.logTapActivity() }
        activityTimer = timer
        timer.resume()
    }

    private func stopActivityTimer() {
        activityTimer?.cancel()
        activityTimer = nil
    }

    private func logTapActivity() {
        var callbacks = 0, frames = 0, signal = false, rate = 0.0
        ioQueue.sync {
            callbacks = tapCallbackCount
            frames = tapFrameCount
            signal = tapSawSignal
            rate = inputFormat?.sampleRate ?? 0
            tapCallbackCount = 0
            tapFrameCount = 0
            tapSawSignal = false
        }
        logger.debug("Tap activity: \(callbacks) callbacks, \(frames) frames, signal=\(signal), in=\(Int(rate)) Hz")
    }

    /// Distinguishes real audio from a tap delivering only silence.
    private static func bufferHasSignal(_ buffer: AVAudioPCMBuffer) -> Bool {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        for audioBuffer in bufferList {
            guard let data = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { continue }
            let bytes = UnsafeRawBufferPointer(start: data, count: Int(audioBuffer.mDataByteSize))
            if bytes.contains(where: { $0 != 0 }) { return true }
        }
        return false
    }
}

// MARK: Core Audio

extension SystemAudioTap {
    private func createProcessTap() throws -> UUID {
        // An empty exclusion list taps every process, capturing exactly what the user hears.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw Failure.tapCreationFailed(status) }
        self.tapID = tapID
        return description.uuid
    }

    private func createAggregateDevice(tapUUID: UUID) throws {
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "hark-system-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]

        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDeviceID)
        guard status == noErr else { throw Failure.aggregateDeviceCreationFailed(status) }
        self.aggregateDeviceID = aggregateDeviceID
    }

    private func defaultSystemOutputDeviceID() throws -> AudioObjectID {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw Failure.propertyReadFailed(status) }
        return deviceID
    }

    private func tapStreamFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = withUnsafeMutablePointer(to: &streamDescription) {
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw Failure.propertyReadFailed(status) }
        return streamDescription
    }
}
