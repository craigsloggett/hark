import FluidAudio
import Foundation

/// User-tunable settings persisted in `UserDefaults`, the macOS defaults system.
enum Preferences {
    /// `UserDefaults` keys, unprefixed since the app's domain already namespaces them.
    enum Key {
        static let diarizationClusteringThreshold = "diarizationClusteringThreshold"
        static let diarizationSpeakerSensitivity = "diarizationSpeakerSensitivity"
        static let diarizationSpeakerRecall = "diarizationSpeakerRecall"
        static let diarizationStepRatio = "diarizationStepRatio"
        static let diarizationMinSegmentDuration = "diarizationMinSegmentDuration"
        static let diarizationMinGapDuration = "diarizationMinGapDuration"
        static let diarizationExclusiveSegments = "diarizationExclusiveSegments"
        static let diarizationMaxSpeakers = "diarizationMaxSpeakers"
        static let speakerMatchThreshold = "speakerMatchThreshold"
        static let speakerMinEnrollmentDuration = "speakerMinEnrollmentDuration"
        static let voiceprintMaxSamples = "voiceprintMaxSamples"
        static let asrDualDecodeArbitration = "asrDualDecodeArbitration"
        static let asrParallelChunkConcurrency = "asrParallelChunkConcurrency"
        static let utteranceGap = "utteranceGap"
    }

    /// Defaults, in seconds where applicable. Those that defer to FluidAudio reference its
    /// constants so they track the library; hark-owned values stay literals.
    enum Default {
        /// Euclidean distance threshold for clustering speaker embeddings (higher keeps more of
        /// them apart as separate speakers).
        static let diarizationClusteringThreshold = 0.75

        /// FluidAudio's VBx warm-start `Fa` parameter (higher splits embeddings into more speakers,
        /// lower merges them).
        static let diarizationSpeakerSensitivity = 0.13

        /// Silence between tokens, in seconds, that ends an utterance.
        static let utteranceGap = 0.4

        /// Maximum cosine distance to match a session speaker to an enrolled voiceprint (lower is
        /// stricter). A different metric from `diarizationClusteringThreshold`, so the value doesn't carry over.
        static let speakerMatchThreshold = 0.65

        /// Community-1's segmentation step ratio (lower sharpens turn boundaries at roughly 2x cost).
        static var diarizationStepRatio: Double {
            OfflineDiarizerConfig.Segmentation.community.stepRatio
        }

        /// Minimum segment length, in seconds, that survives diarization. Set above community-1's 1.0
        /// default because compressed remote audio over-segments there (the cost is sub-2s turns merge
        /// into a neighbour).
        static let diarizationMinSegmentDuration = 2.0

        /// Minimum speech, in seconds, to enroll an unmatched speaker as a new voiceprint (shorter
        /// ones stay positional but still match existing voiceprints). Higher resists brief fragments.
        static var speakerMinEnrollmentDuration: Double {
            Double(SpeakerManager().minSpeechDuration)
        }

        /// FluidAudio's VBx warm-start `Fb` (recall counterpart to `Fa`; higher keeps more borderline
        /// embeddings with a speaker).
        static var diarizationSpeakerRecall: Double {
            OfflineDiarizerConfig.Clustering.community.warmStartFb
        }

        /// Silence, in seconds, below which adjacent same-speaker segments are bridged rather than split.
        static var diarizationMinGapDuration: Double {
            OfflineDiarizerConfig.PostProcessing.community.minGapDurationSeconds
        }

        /// Trim overlapping speech so only one speaker is active at a time.
        static var diarizationExclusiveSegments: Bool {
            OfflineDiarizerConfig.PostProcessing.community.exclusiveSegments
        }

        /// Cap on speakers found per session; 0 lets FluidAudio decide (hark-owned sentinel, since the
        /// SDK expresses "no cap" as a nil `maxSpeakers`).
        static let diarizationMaxSpeakers = 0

        /// Samples retained per voiceprint; the newest this many form its duration-weighted centroid
        /// (hark-owned, no SDK constant).
        static let voiceprintMaxSamples = 5

        /// Parakeet's three-strategy decode probe: better accuracy at roughly 1.1-1.5x cost.
        static var asrDualDecodeArbitration: Bool {
            ASRConfig().dualDecodeArbitration
        }

        /// Long-form chunks transcribed concurrently (throughput vs CPU/memory).
        static var asrParallelChunkConcurrency: Int {
            ASRConfig().parallelChunkConcurrency
        }
    }

    /// Seeds the registration domain so `defaults read` shows the effective defaults (reads fall
    /// back to `Default` without it).
    static func register(into defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.diarizationClusteringThreshold: Default.diarizationClusteringThreshold,
            Key.diarizationSpeakerSensitivity: Default.diarizationSpeakerSensitivity,
            Key.diarizationSpeakerRecall: Default.diarizationSpeakerRecall,
            Key.diarizationStepRatio: Default.diarizationStepRatio,
            Key.diarizationMinSegmentDuration: Default.diarizationMinSegmentDuration,
            Key.diarizationMinGapDuration: Default.diarizationMinGapDuration,
            Key.diarizationExclusiveSegments: Default.diarizationExclusiveSegments,
            Key.diarizationMaxSpeakers: Default.diarizationMaxSpeakers,
            Key.speakerMatchThreshold: Default.speakerMatchThreshold,
            Key.speakerMinEnrollmentDuration: Default.speakerMinEnrollmentDuration,
            Key.voiceprintMaxSamples: Default.voiceprintMaxSamples,
            Key.asrDualDecodeArbitration: Default.asrDualDecodeArbitration,
            Key.asrParallelChunkConcurrency: Default.asrParallelChunkConcurrency,
            Key.utteranceGap: Default.utteranceGap,
        ])
    }

    static var diarizationClusteringThreshold: Double {
        resolved(Key.diarizationClusteringThreshold, default: Default.diarizationClusteringThreshold)
    }

    static var diarizationSpeakerSensitivity: Double {
        resolved(Key.diarizationSpeakerSensitivity, default: Default.diarizationSpeakerSensitivity)
    }

    static var diarizationSpeakerRecall: Double {
        resolved(Key.diarizationSpeakerRecall, default: Default.diarizationSpeakerRecall)
    }

    static var diarizationStepRatio: Double {
        resolved(Key.diarizationStepRatio, default: Default.diarizationStepRatio)
    }

    static var diarizationMinSegmentDuration: Double {
        resolved(Key.diarizationMinSegmentDuration, default: Default.diarizationMinSegmentDuration)
    }

    static var diarizationMinGapDuration: Double {
        resolved(Key.diarizationMinGapDuration, default: Default.diarizationMinGapDuration)
    }

    static var diarizationExclusiveSegments: Bool {
        resolved(Key.diarizationExclusiveSegments, default: Default.diarizationExclusiveSegments)
    }

    static var diarizationMaxSpeakers: Int {
        resolved(Key.diarizationMaxSpeakers, default: Default.diarizationMaxSpeakers)
    }

    static var speakerMatchThreshold: Double {
        resolved(Key.speakerMatchThreshold, default: Default.speakerMatchThreshold)
    }

    static var speakerMinEnrollmentDuration: Double {
        resolved(Key.speakerMinEnrollmentDuration, default: Default.speakerMinEnrollmentDuration)
    }

    static var voiceprintMaxSamples: Int {
        resolved(Key.voiceprintMaxSamples, default: Default.voiceprintMaxSamples)
    }

    static var asrDualDecodeArbitration: Bool {
        resolved(Key.asrDualDecodeArbitration, default: Default.asrDualDecodeArbitration)
    }

    static var asrParallelChunkConcurrency: Int {
        resolved(Key.asrParallelChunkConcurrency, default: Default.asrParallelChunkConcurrency)
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

    /// The stored `Bool` for `key`, or `fallback` when it is unset.
    static func resolved(
        _ key: String,
        default fallback: Bool,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard let stored = defaults.object(forKey: key) as? Bool else { return fallback }
        return stored
    }

    /// The stored `Int` for `key`, or `fallback` when it is unset.
    static func resolved(
        _ key: String,
        default fallback: Int,
        in defaults: UserDefaults = .standard
    ) -> Int {
        guard let stored = defaults.object(forKey: key) as? Int else { return fallback }
        return stored
    }
}

extension Preferences {
    /// The restart-scoped preferences as captured at app launch. The transcription engine reads the
    /// `asr*` prefs once when its `AsrManager` loads, so the Advanced pane compares the live values
    /// against these to flag a change that won't apply until Hark restarts. The `static let`s snapshot
    /// on first access, so `capture()` must run at launch, before any setting can change.
    enum Launch {
        static let asrDualDecodeArbitration = Preferences.asrDualDecodeArbitration
        static let asrParallelChunkConcurrency = Preferences.asrParallelChunkConcurrency

        static func capture() {
            _ = asrDualDecodeArbitration
            _ = asrParallelChunkConcurrency
        }
    }
}
