import AudioToolbox
import AVFoundation
import OSLog

/// Captures all system audio output (everything the user hears) to a file using a Core Audio process tap.
///
/// The tap and its aggregate device are Core Audio objects referenced by value-type IDs. Tapped audio is
/// delivered on a dedicated serial queue, and the output file is only ever touched on that queue, so the type
/// is safe to hand across actors despite holding a non-`Sendable` `AVAudioFile`.
final class SystemAudioTap: @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case propertyReadFailed(OSStatus)
        case tapCreationFailed(OSStatus)
        case aggregateDeviceCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case unsupportedStreamFormat

        var description: String {
            switch self {
            case let .propertyReadFailed(status): "Core Audio property read failed (\(status))"
            case let .tapCreationFailed(status): "Process tap creation failed (\(status))"
            case let .aggregateDeviceCreationFailed(status): "Aggregate device creation failed (\(status))"
            case let .ioProcCreationFailed(status): "Audio I/O proc creation failed (\(status))"
            case let .deviceStartFailed(status): "Audio device failed to start (\(status))"
            case .unsupportedStreamFormat: "The system audio tap reported an unsupported stream format"
            }
        }
    }

    private let logger = Logger(subsystem: "com.craigsloggett.hark", category: "SystemAudioTap")
    private let ioQueue = DispatchQueue(label: "com.craigsloggett.hark.system-audio-tap", qos: .userInitiated)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var file: AVAudioFile?

    /// Begins capturing system audio to `url`. The first call triggers the system-audio recording permission prompt.
    func start(writingTo url: URL) throws {
        let tapUUID = try createProcessTap()

        var streamDescription = try tapStreamFormat(tapID)
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw Failure.unsupportedStreamFormat
        }

        try createAggregateDevice(tapUUID: tapUUID)
        try startCapture(to: url, format: format)
    }

    /// Stops capture and releases the tap, aggregate device, and output file. Safe to call when not running.
    func stop() {
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
        // The device is stopped, so no further callbacks fire; draining the queue lets any in-flight write finish.
        ioQueue.sync { file = nil }
    }

    deinit { stop() }

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
        let outputUID = try defaultSystemOutputDeviceUID()

        // The output device is the aggregate's clock source; the tap rides on top of it as a private sub-tap.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "hark-system-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]

        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDeviceID)
        guard status == noErr else { throw Failure.aggregateDeviceCreationFailed(status) }
        self.aggregateDeviceID = aggregateDeviceID
    }

    private func startCapture(to url: URL, format: AVAudioFormat) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: format.streamDescription.pointee.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: format.isInterleaved
        )
        self.file = file

        let ioBlock: AudioDeviceIOBlock = { [weak self] _, inputData, _, _, _ in
            guard let self, let file = self.file else { return }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: inputData,
                deallocator: nil
            ) else { return }
            do {
                try file.write(from: buffer)
            } catch {
                logger.error("Failed to write system audio buffer: \(error, privacy: .public)")
            }
        }

        var ioProcID: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, ioQueue, ioBlock)
        guard status == noErr, let ioProcID else { throw Failure.ioProcCreationFailed(status) }
        self.ioProcID = ioProcID

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else { throw Failure.deviceStartFailed(status) }
    }

    private func defaultSystemOutputDeviceUID() throws -> String {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw Failure.propertyReadFailed(status) }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw Failure.propertyReadFailed(status) }
        return uid as String
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
