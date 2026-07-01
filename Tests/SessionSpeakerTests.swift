import Foundation
@testable import hark
import Testing

struct SessionSpeakerTests {
    // MARK: Codable

    @Test func decodesLegacyIdNameShape() throws {
        let legacy = Data(#"{"id":"v1","name":"Ada"}"#.utf8)
        let speaker = try JSONDecoder().decode(SessionSpeaker.self, from: legacy)
        #expect(speaker.voiceprintID == "v1") // legacy id becomes the bound voiceprint
        #expect(speaker.nameOverride == nil) // legacy name snapshot is dropped, the live voiceprint governs
        #expect(speaker.embedding == nil)
    }

    @Test func roundTripsNewShape() throws {
        let speaker = SessionSpeaker(voiceprintID: "v1", nameOverride: "Boss", embedding: [0.5, 0.25], duration: 3)
        let data = try JSONEncoder().encode(speaker)
        #expect(try JSONDecoder().decode(SessionSpeaker.self, from: data) == speaker)
    }

    @Test func omitsNilFields() throws {
        let data = try JSONEncoder().encode(SessionSpeaker())
        #expect(try #require(String(bytes: data, encoding: .utf8)) == "{}")
    }

    // MARK: SpeakerDisplay precedence

    private func voiceprint(_ id: String, name: String?, redirectID: String? = nil) -> Voiceprint {
        Voiceprint(id: id, name: name, samples: [], redirectID: redirectID)
    }

    @Test func overrideWinsOverVoiceprintName() {
        let overlay = ["speaker1": SessionSpeaker(voiceprintID: "v1", nameOverride: "Chair")]
        let byID = ["v1": voiceprint("v1", name: "Ada")]
        #expect(SpeakerDisplay.name(token: "speaker1", overlay: overlay, voiceprints: byID) == "Chair")
    }

    @Test func fallsBackToVoiceprintName() {
        let overlay = ["speaker1": SessionSpeaker(voiceprintID: "v1")]
        let byID = ["v1": voiceprint("v1", name: "Ada")]
        #expect(SpeakerDisplay.name(token: "speaker1", overlay: overlay, voiceprints: byID) == "Ada")
    }

    @Test func unlabeledWhenNoOverrideAndNoName() {
        let unnamed = ["v1": voiceprint("v1", name: nil)]
        let bound = ["speaker1": SessionSpeaker(voiceprintID: "v1")]
        #expect(SpeakerDisplay.name(token: "speaker1", overlay: bound, voiceprints: unnamed) == nil)
        // Positional-only (no binding) is also unlabeled.
        let positional = ["speaker2": SessionSpeaker()]
        #expect(SpeakerDisplay.name(token: "speaker2", overlay: positional, voiceprints: [:]) == nil)
    }

    @Test func followsMergeRedirect() {
        let overlay = ["speaker1": SessionSpeaker(voiceprintID: "old")]
        let byID = [
            "old": voiceprint("old", name: nil, redirectID: "new"),
            "new": voiceprint("new", name: "Ada"),
        ]
        #expect(SpeakerDisplay.name(token: "speaker1", overlay: overlay, voiceprints: byID) == "Ada")
    }

    @Test func namesDropsUnlabeledTokens() {
        let overlay = [
            "speaker1": SessionSpeaker(voiceprintID: "v1"),
            "speaker2": SessionSpeaker(),
        ]
        let byID = ["v1": voiceprint("v1", name: "Ada")]
        #expect(SpeakerDisplay.names(overlay: overlay, voiceprints: byID) == ["speaker1": "Ada"])
    }

    // MARK: SpeakerBinding classification

    @Test func bindingIsUnknownWithoutLabelOrVoice() {
        let overlay = ["speaker1": SessionSpeaker()]
        #expect(SpeakerDisplay.binding(token: "speaker1", overlay: overlay, voiceprints: [:]) == .unknown)
        // A missing token is unknown too.
        #expect(SpeakerDisplay.binding(token: "absent", overlay: overlay, voiceprints: [:]) == .unknown)
    }

    @Test func bindingIsLocalLabelForAnOverrideOnly() {
        let overlay = ["speaker1": SessionSpeaker(nameOverride: "Chair")]
        #expect(SpeakerDisplay.binding(token: "speaker1", overlay: overlay, voiceprints: [:]) == .localLabel("Chair"))
    }

    @Test func bindingIsSavedVoiceEvenWhenOverridden() {
        let overlay = ["speaker1": SessionSpeaker(voiceprintID: "v1", nameOverride: "Chair")]
        let byID = ["v1": voiceprint("v1", name: "Ada")]
        // A bound voice wins over the transcript label, so saved-voice actions apply.
        #expect(SpeakerDisplay.binding(token: "speaker1", overlay: overlay, voiceprints: byID) == .savedVoice(id: "v1"))
    }

    @Test func bindingDegradesWhenTheVoiceIsForgotten() {
        // The binding points at a voiceprint that is no longer in the database.
        let boundOnly = ["speaker1": SessionSpeaker(voiceprintID: "gone")]
        #expect(SpeakerDisplay.binding(token: "speaker1", overlay: boundOnly, voiceprints: [:]) == .unknown)
        // With a surviving label it falls back to that label rather than a dead binding.
        let labeled = ["speaker1": SessionSpeaker(voiceprintID: "gone", nameOverride: "Chair")]
        #expect(SpeakerDisplay.binding(token: "speaker1", overlay: labeled, voiceprints: [:]) == .localLabel("Chair"))
    }
}
