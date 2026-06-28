import FluidAudio
import Foundation

/// User-tunable settings persisted in `UserDefaults`, the macOS defaults system.
enum Preferences {
    /// `UserDefaults` keys, unprefixed since the app's domain already namespaces them.
    enum Key {
        static let diarizationClusteringThreshold = "diarizationClusteringThreshold"
        static let diarizationSpeakerSensitivity = "diarizationSpeakerSensitivity"
        static let diarizationStepRatio = "diarizationStepRatio"
        static let diarizationMinSegmentDuration = "diarizationMinSegmentDuration"
        static let speakerMatchThreshold = "speakerMatchThreshold"
        static let utteranceGap = "utteranceGap"
    }

    /// Defaults, in seconds where applicable. The two that defer to FluidAudio reference its
    /// constants so they track the library.
    enum Default {
        /// Euclidean distance threshold for clustering speaker embeddings; higher keeps more of
        /// them apart as separate speakers.
        static let diarizationClusteringThreshold = 0.75

        /// FluidAudio's VBx warm-start `Fa` parameter; higher splits embeddings into more speakers,
        /// lower merges them.
        static let diarizationSpeakerSensitivity = 0.13

        /// Silence between tokens, in seconds, that ends an utterance.
        static let utteranceGap = 0.4

        /// Maximum cosine distance for matching a session speaker to an enrolled voiceprint;
        /// FluidAudio's `SpeakerManager` default, mirrored here (it's an init default, not an
        /// exposed constant) and pinned by a contract test. Lower matches more strictly. This is a
        /// cosine-distance scale, unrelated to the euclidean `diarizationClusteringThreshold`.
        static let speakerMatchThreshold = 0.65

        /// Community-1's segmentation step ratio; lower sharpens turn boundaries at roughly 2x cost.
        static var diarizationStepRatio: Double {
            OfflineDiarizerConfig.Segmentation.community.stepRatio
        }

        /// Community-1's minimum embedding-segment length, in seconds; lower lets brief turns get
        /// their own speaker embedding.
        static var diarizationMinSegmentDuration: Double {
            OfflineDiarizerConfig.Embedding.community.minSegmentDurationSeconds
        }
    }

    /// Seeds the registration domain so `defaults read` shows the effective defaults; reads fall
    /// back to `Default` without it.
    static func register(into defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.diarizationClusteringThreshold: Default.diarizationClusteringThreshold,
            Key.diarizationSpeakerSensitivity: Default.diarizationSpeakerSensitivity,
            Key.diarizationStepRatio: Default.diarizationStepRatio,
            Key.diarizationMinSegmentDuration: Default.diarizationMinSegmentDuration,
            Key.speakerMatchThreshold: Default.speakerMatchThreshold,
            Key.utteranceGap: Default.utteranceGap,
        ])
    }

    static var diarizationClusteringThreshold: Double {
        resolved(Key.diarizationClusteringThreshold, default: Default.diarizationClusteringThreshold)
    }

    static var diarizationSpeakerSensitivity: Double {
        resolved(Key.diarizationSpeakerSensitivity, default: Default.diarizationSpeakerSensitivity)
    }

    static var diarizationStepRatio: Double {
        resolved(Key.diarizationStepRatio, default: Default.diarizationStepRatio)
    }

    static var diarizationMinSegmentDuration: Double {
        resolved(Key.diarizationMinSegmentDuration, default: Default.diarizationMinSegmentDuration)
    }

    static var speakerMatchThreshold: Double {
        resolved(Key.speakerMatchThreshold, default: Default.speakerMatchThreshold)
    }

    static var utteranceGap: Double {
        resolved(Key.utteranceGap, default: Default.utteranceGap)
    }

    /// The stored `Double` for `key`, or `fallback` when it is unset.
    static func resolved(
        _ key: String,
        default fallback: Double,
        in defaults: UserDefaults = .standard
    ) -> Double {
        // `double(forKey:)` can't tell an unset key from a stored 0, so read the optional object.
        guard let stored = defaults.object(forKey: key) as? Double else { return fallback }
        return stored
    }
}
