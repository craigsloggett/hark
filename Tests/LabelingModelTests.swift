import Foundation
@testable import hark
import Testing

/// Exercises the labeling window's view model through its `preview` seam, without touching disk or the
/// shared `SpeakerStore`. The same-name duplicate check resolves against the in-memory voiceprint
/// snapshot, so these stay hermetic.
@MainActor
struct LabelingModelTests {
    @Test func flagsAnEnrollThatReusesAnExistingName() async {
        let detail = SessionDetail(
            url: URL(fileURLWithPath: "/tmp/hark-test"),
            segments: [],
            overlay: ["speaker1": SessionSpeaker(embedding: [1], duration: 5)]
        )
        let dan = Voiceprint(id: "vp-dan", name: "Dan", samples: [])
        let model = LabelingModel.preview(detail: detail, voiceprints: [dan])

        // Typing a name that already belongs to a saved voice is caught before an enroll, regardless
        // of case, so the two "Dan"s don't fragment into separate voiceprints.
        let duplicate = await model.probableDuplicate(token: "speaker1", name: "dan")
        #expect(duplicate?.match.id == "vp-dan")
        #expect(duplicate?.reason == .sameName)
    }

    @Test func allowsAnEnrollWithAFreshName() async {
        let detail = SessionDetail(
            url: URL(fileURLWithPath: "/tmp/hark-test"),
            segments: [],
            overlay: ["speaker1": SessionSpeaker(duration: 5)]
        )
        let dan = Voiceprint(id: "vp-dan", name: "Dan", samples: [])
        let model = LabelingModel.preview(detail: detail, voiceprints: [dan])

        // A new name with no embedding to compare has nothing to duplicate, so the enroll proceeds.
        let duplicate = await model.probableDuplicate(token: "speaker1", name: "Priya")
        #expect(duplicate == nil)
    }
}
