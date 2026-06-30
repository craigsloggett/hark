import Foundation
@testable import hark
import Testing

/// Process-scoped A/B for the ASR dual-decode knob. `Transcriber` reads `asrDualDecodeArbitration`
/// once when its `AsrManager` loads and caches the manager, so this knob can only be varied across
/// separate processes. The driver runs this test twice (the pref written `NO` then `YES`) and the
/// wording diff between `dualdecode-off.txt` and `dualdecode-on.txt` is the deliverable.
///
/// Disabled unless a `.hark-asr-ab` marker names the session, so it never runs in CI.
struct AsrArbitrationTests {
    private static var target: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let raw = try? String(contentsOf: documents.appendingPathComponent(".hark-asr-ab"), encoding: .utf8)
        else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : documents.appendingPathComponent(name, isDirectory: true)
    }

    @Test(.enabled(if: AsrArbitrationTests.target != nil))
    func comparesDualDecode() async throws {
        let sessionURL = try #require(Self.target)
        // Reflects the value the driver wrote before launching this process.
        let mode = Preferences.asrDualDecodeArbitration ? "on" : "off"

        let start = Date()
        let transcript = try await TranscriptionService().transcribeSession(at: sessionURL).transcript
        let elapsed = Date().timeIntervalSince(start)

        let outDir = sessionURL.deletingLastPathComponent().appendingPathComponent(".hark-sweep-out", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try (transcript.plainText() + "\n")
            .write(to: outDir.appendingPathComponent("dualdecode-\(mode).txt"), atomically: true, encoding: .utf8)
        try transcript.segments.writeJSON(to: outDir.appendingPathComponent("dualdecode-\(mode).json"))

        let words = transcript.segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        print("ASR-AB \(mode): \(transcript.segments.count) segments, \(words) words, processed in \(Int(elapsed))s")
        #expect(!transcript.segments.isEmpty)
    }
}
