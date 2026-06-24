import Foundation

/// The audio capture format shared by both recording tracks.
enum CaptureFormat {
    /// Sample rate in hertz. Both tracks record at this rate because it is what FluidAudio's
    /// Parakeet model requires (`ASRConstants.sampleRate`, pinned by `FluidAudioContractTests`).
    static let sampleRate: Double = 16000
}
