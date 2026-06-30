import FluidAudio
import Foundation
@testable import hark
import Testing

/// Exercises the `Preferences` UserDefaults layer in an isolated, serialized suite using a single fixed
/// domain cleared around every test, so tests never race and the real preferences stay untouched.
@Suite(.serialized)
final class PreferencesTests {
    private static let suiteName = "hark.preferences.tests"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    @Test func registerSeedsEveryDefault() {
        Preferences.register(into: defaults)
        #expect(defaults.double(forKey: Preferences.Key.diarizationClusteringThreshold) == 0.75)
        #expect(defaults.double(forKey: Preferences.Key.diarizationSpeakerSensitivity) == 0.13)
        #expect(defaults.double(forKey: Preferences.Key.diarizationMinSegmentDuration) == 2.0)
        #expect(defaults.double(forKey: Preferences.Key.speakerMatchThreshold) == 0.65)
        #expect(defaults.double(forKey: Preferences.Key.speakerMinEnrollmentDuration) == 1.0)
        #expect(defaults.double(forKey: Preferences.Key.utteranceGap) == 0.4)
        #expect(defaults.integer(forKey: Preferences.Key.voiceprintMaxSamples) == 5)
        #expect(defaults.integer(forKey: Preferences.Key.diarizationMaxSpeakers) == 0)
        // Library-deferred keys register FluidAudio's live constants rather than mirrored literals.
        #expect(defaults.double(forKey: Preferences.Key.diarizationStepRatio)
            == OfflineDiarizerConfig.Segmentation.community.stepRatio)
        #expect(defaults.double(forKey: Preferences.Key.diarizationSpeakerRecall)
            == OfflineDiarizerConfig.Clustering.community.warmStartFb)
        #expect(defaults.double(forKey: Preferences.Key.diarizationMinGapDuration)
            == OfflineDiarizerConfig.PostProcessing.community.minGapDurationSeconds)
        #expect(defaults.bool(forKey: Preferences.Key.diarizationExclusiveSegments)
            == OfflineDiarizerConfig.PostProcessing.community.exclusiveSegments)
        #expect(defaults.bool(forKey: Preferences.Key.asrDualDecodeArbitration)
            == ASRConfig().dualDecodeArbitration)
        #expect(defaults.integer(forKey: Preferences.Key.asrParallelChunkConcurrency)
            == ASRConfig().parallelChunkConcurrency)
    }

    @Test func resolvedFallsBackToDefaultWhenUnset() {
        // With no register() and no stored value, the accessor must still return the Default, not 0.
        let value = Preferences.resolved(
            Preferences.Key.utteranceGap,
            default: Preferences.Default.utteranceGap,
            in: defaults
        )
        #expect(value == Preferences.Default.utteranceGap)
    }

    @Test func resolvedReadsStoredOverride() {
        defaults.set(0.9, forKey: Preferences.Key.diarizationClusteringThreshold)
        let value = Preferences.resolved(
            Preferences.Key.diarizationClusteringThreshold,
            default: Preferences.Default.diarizationClusteringThreshold,
            in: defaults
        )
        #expect(value == 0.9)
    }

    @Test func resolvedBoolAndIntFallBackWhenUnset() {
        // Keys Preferences never registers, so the lookup is truly unset and the fallback is returned
        // (a real Key would resolve to its seeded registration value, masking the fallback path).
        #expect(Preferences.resolved("hark.tests.unsetFlag", default: true, in: defaults))
        #expect(Preferences.resolved("hark.tests.unsetCount", default: 7, in: defaults) == 7)
    }

    @Test func resolvedReadsStoredBoolAndIntOverrides() {
        defaults.set(false, forKey: Preferences.Key.diarizationExclusiveSegments)
        #expect(!Preferences.resolved(Preferences.Key.diarizationExclusiveSegments, default: true, in: defaults))

        defaults.set(12, forKey: Preferences.Key.voiceprintMaxSamples)
        #expect(Preferences.resolved(Preferences.Key.voiceprintMaxSamples, default: 5, in: defaults) == 12)
    }
}
