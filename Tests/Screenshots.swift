import AppKit
@testable import hark
import SwiftUI
import Testing

/// Not a test in the assertion sense: renders a set of views to PNGs for visual inspection.
/// Writes into the sandbox container's Documents; `make screenshots` copies them into the repo.
@MainActor
struct ScreenshotRenderer {
    private struct Shot {
        let name: String
        let size: CGSize
        let view: AnyView
    }

    /// Empty/placeholder states plus populated states built from a fixed in-memory model, so the chat,
    /// chips, popovers, and roster render with real content without touching disk.
    private var shots: [Shot] {
        let model = Self.populatedModel()
        return [
            Shot(name: "Settings", size: CGSize(width: 480, height: 560),
                 view: AnyView(SettingsView())),
            Shot(name: "GeneralSettings", size: CGSize(width: 480, height: 420),
                 view: AnyView(GeneralSettingsView())),
            Shot(name: "AdvancedSettings", size: CGSize(width: 480, height: 900),
                 view: AnyView(AdvancedSettingsView())),
            Shot(name: "SessionList-Empty", size: CGSize(width: 260, height: 380),
                 view: AnyView(SessionListView(model: LabelingModel()))),
            Shot(name: "TranscriptChat-Empty", size: CGSize(width: 520, height: 380),
                 view: AnyView(TranscriptChatView(model: LabelingModel()))),
            Shot(name: "PeopleInspector-Empty", size: CGSize(width: 280, height: 380),
                 view: AnyView(PeopleInspectorView(model: LabelingModel()))),
            Shot(name: "TranscriptChat", size: CGSize(width: 540, height: 460),
                 view: AnyView(TranscriptChatView(model: model))),
            Shot(name: "PeopleInspector", size: CGSize(width: 300, height: 440),
                 view: AnyView(PeopleInspectorView(model: model))),
            Shot(name: "Voices", size: CGSize(width: 320, height: 480),
                 view: AnyView(VoicesManagerView(model: model))),
            Shot(name: "Voices-Empty", size: CGSize(width: 320, height: 400),
                 view: AnyView(VoicesManagerView(model: LabelingModel()))),
            Shot(name: "Popover-Unidentified", size: CGSize(width: 300, height: 340),
                 view: AnyView(popover(token: "speaker2", model: model))),
            Shot(name: "Popover-SavedVoice", size: CGSize(width: 300, height: 420),
                 view: AnyView(popover(token: "speaker1", model: model))),
            Shot(name: "Popover-Recognized", size: CGSize(width: 300, height: 420),
                 view: AnyView(popover(token: "speaker5", model: model))),
            Shot(name: "Popover-Label", size: CGSize(width: 300, height: 360),
                 view: AnyView(popover(token: "speaker3", model: model))),
            Shot(name: "Popover-NoSample", size: CGSize(width: 300, height: 340),
                 view: AnyView(popover(token: "speaker4", model: model))),
        ]
    }

    private func popover(token: String, model: LabelingModel) -> some View {
        SpeakerPopover(token: token, model: model, isPresented: .constant(true))
    }

    /// A three-speaker transcript covering every chip state: a saved voice (Priya), an unidentified
    /// speaker, and a transcript-only label (Guest), plus a second saved voice to populate the picker.
    private static func populatedModel() -> LabelingModel {
        let embedding: [Float] = [0.1, 0.2, 0.3]
        let enrolledAt = Date(timeIntervalSinceReferenceDate: 0)
        let priya = Voiceprint(
            id: "vp-priya", name: "Priya",
            samples: [VoiceSample(id: UUID(), embedding: embedding, duration: 30, enrolledAt: enrolledAt)]
        )
        let marcus = Voiceprint(
            id: "vp-marcus", name: "Marcus",
            samples: [VoiceSample(id: UUID(), embedding: embedding, duration: 20, enrolledAt: enrolledAt)]
        )
        let recognized = Voiceprint(
            id: "vp-recognized", name: nil,
            samples: [VoiceSample(id: UUID(), embedding: embedding, duration: 20, enrolledAt: enrolledAt)]
        )
        let segments = [
            TranscriptSegment(start: 0, end: 3, speaker: .remote(1), text: "Morning! Did you see the deck?"),
            TranscriptSegment(start: 3, end: 6, speaker: .you, text: "I did. Slide four needs a refresh."),
            TranscriptSegment(start: 6, end: 9, speaker: .remote(2), text: "I can take that, I have the figures."),
            TranscriptSegment(start: 9, end: 12, speaker: .remote(3), text: "And I'll tighten the summary."),
            TranscriptSegment(start: 12, end: 15, speaker: .remote(1), text: "Perfect. Let's regroup after lunch."),
        ]
        let overlay: [String: SessionSpeaker] = [
            // A borderline auto-match (distance past the 0.4 confident cutoff) reads as "Likely Priya".
            "speaker1": SessionSpeaker(
                voiceprintID: "vp-priya", matchDistance: 0.55, embedding: embedding, duration: 30
            ),
            "speaker2": SessionSpeaker(embedding: embedding, duration: 18),
            "speaker3": SessionSpeaker(nameOverride: "Guest", embedding: embedding, duration: 12),
            // A legacy speaker with no saved voice sample: naming can only label the transcript.
            "speaker4": SessionSpeaker(duration: 8),
            // Recognized (auto-enrolled) but never named: the popover names the voice in place.
            "speaker5": SessionSpeaker(voiceprintID: "vp-recognized", embedding: embedding, duration: 20),
        ]
        let detail = SessionDetail(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("hark-preview"),
            segments: segments,
            overlay: overlay
        )
        // Priya and the recognized-but-unnamed voice share an embedding, so they read as a likely
        // duplicate in the Voices manager's suggestions band.
        let suggestion = DuplicateSuggestion(
            primary: VoiceSummary(id: "vp-priya", name: "Priya", sampleCount: 1, recordingCount: 4),
            secondary: VoiceSummary(id: "vp-recognized", name: nil, sampleCount: 1, recordingCount: 2),
            distance: 0.03
        )
        return LabelingModel.preview(
            detail: detail, voiceprints: [priya, marcus, recognized],
            usage: ["vp-priya": 4, "vp-marcus": 2, "vp-recognized": 2],
            suggestions: [suggestion]
        )
    }

    @Test func renderAll() throws {
        let outDir = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for shot in shots {
            try render(shot.view, size: shot.size,
                       to: outDir.appendingPathComponent("\(shot.name).png"))
        }
        print("Screenshots written to: \(outDir.path)")
    }

    private func render(_ view: AnyView, size: CGSize, to url: URL) throws {
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        // Host the view in an offscreen window so NSTableView-backed Lists draw their rows, not just
        // empty content, in the capture.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // A short spin lets List/ScrollView content lay out before capture.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }
}
