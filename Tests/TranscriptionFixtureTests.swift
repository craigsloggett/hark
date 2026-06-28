import Foundation
@testable import hark
import Testing

/// Manual harness: transcribes a real recording session from the app's container with the new
/// pipeline and writes `transcript.parakeet.txt` beside it, leaving any existing reference
/// `transcript.txt` untouched. Disabled unless a `.hark-fixture` marker file naming the session
/// folder exists in the container's Documents, so it never runs in CI.
struct TranscriptionFixtureTests {
    private static var fixtureURL: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let marker = docs.appendingPathComponent(".hark-fixture")
        guard let raw = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return docs.appendingPathComponent(name, isDirectory: true)
    }

    @Test(.enabled(if: fixtureURL != nil))
    func transcribesFixtureSession() async throws {
        let sessionURL = try #require(Self.fixtureURL)
        let service = TranscriptionService()

        let start = Date()
        let transcript = try await service.transcribeSession(at: sessionURL).transcript
        let elapsed = Date().timeIntervalSince(start)

        let outURL = sessionURL.appendingPathComponent("transcript.parakeet.txt")
        try (transcript.plainText() + "\n").write(to: outURL, atomically: true, encoding: .utf8)

        let words = transcript.segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let speakers = Set(transcript.segments.map(\.speaker.label)).count
        let audioEnd = transcript.segments.map(\.end).max() ?? 0
        print(
            """
            FIXTURE \(sessionURL.lastPathComponent): \
            \(transcript.segments.count) segments, \(speakers) speakers, \(words) words, \
            audio ~\(Int(audioEnd))s, processed in \(Int(elapsed))s -> \(outURL.path)
            """
        )
        #expect(!transcript.segments.isEmpty)
    }
}
