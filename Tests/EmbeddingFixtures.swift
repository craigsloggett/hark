import FluidAudio
@testable import hark

/// A 256-d embedding with `leading` values at the front and zeros elsewhere, shared by the suites
/// that exercise matching (pure vector math, no models).
func embedding(_ leading: [Float]) -> Embedding {
    var values = [Float](repeating: 0, count: SpeakerManager.embeddingSize)
    for (index, value) in leading.enumerated() {
        values[index] = value
    }
    // The padded array is exactly the model dimension, so validation cannot fail.
    return Embedding(values)!
}
