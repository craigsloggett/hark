import FluidAudio
import Foundation
@testable import hark
import Testing

/// Exercises the `Preferences` UserDefaults layer in an isolated, serialized suite: a single fixed
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
        #expect(defaults.double(forKey: Preferences.Key.diarizationFa) == 0.13)
        #expect(defaults.double(forKey: Preferences.Key.utteranceGap) == 0.4)
        // Library-deferred keys register FluidAudio's live constants.
        #expect(defaults.double(forKey: Preferences.Key.diarizationStepRatio)
            == OfflineDiarizerConfig.Segmentation.community.stepRatio)
        #expect(defaults.double(forKey: Preferences.Key.diarizationMinSegmentDuration)
            == OfflineDiarizerConfig.Embedding.community.minSegmentDurationSeconds)
    }

    @Test func resolvedFallsBackToDefaultWhenUnset() {
        // No register(), no stored value: the accessor must still return the Default, not 0.
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
}
