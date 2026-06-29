import FluidAudio
import Foundation
import OSLog

/// One session's diarized speaker: the diarizer's cluster id, its mean embedding, and speech duration.
struct SpeakerCluster {
    let id: String
    let embedding: [Float]
    let duration: Float
}

/// A persisted voiceprint. Hark's own type, not FluidAudio's `Speaker`, so the on-disk format stays
/// stable across library bumps.
struct Voiceprint: Codable, Equatable {
    let id: String
    let name: String?
    let embedding: [Float]
    let duration: Float
}

/// A session speaker's resolved identity; `name` is `nil` until the voiceprint is named.
struct SpeakerIdentity: Codable, Equatable {
    let id: String
    let name: String?
}

/// Matches each session's diarized speakers against a persisted voiceprint database so a recurring
/// voice keeps a stable identity across sessions. Matching is read-only against a pre-session
/// snapshot, so two voices in one meeting can't collapse together; unmatched speakers enroll only
/// past a duration floor, keeping brief diarization fragments out of the database.
actor SpeakerStore {
    private let directory: URL?
    private let logger = Logger(category: "SpeakerStore")

    /// - Parameter directory: where `voiceprints.json` lives; defaults to the sandbox container's
    ///   `Application Support/Hark`.
    init(directory: URL? = nil) {
        self.directory = directory
    }

    /// Resolves each cluster to a stable identity, enrolling and persisting new voiceprints.
    /// - Returns: cluster id to identity; empty when the database can't be read, so a corrupt file
    ///   degrades to positional speakers instead of being overwritten.
    func resolve(_ clusters: [SpeakerCluster]) -> [String: SpeakerIdentity] {
        let known: [Voiceprint]
        do {
            known = try load()
        } catch {
            logger.error("Couldn't read voiceprints, leaving speakers positional: \(error, privacy: .public)")
            return [:]
        }

        let threshold = Float(Preferences.speakerMatchThreshold)
        let enrollFloor = Float(Preferences.speakerMinEnrollmentDuration)
        let snapshot = matcher(seededWith: known, threshold: threshold)

        let (resolved, enrolled) = assign(
            clusters, against: snapshot, known: known, threshold: threshold, enrollFloor: enrollFloor
        )

        let summary = String(format: "Resolved %d/%d speakers, %d new", resolved.count, clusters.count, enrolled.count)
        logger.log("\(summary, privacy: .public)")

        if !enrolled.isEmpty {
            do {
                try save(known + enrolled)
            } catch {
                logger.error("Couldn't persist voiceprints: \(error, privacy: .public)")
            }
        }
        return resolved
    }

    /// Matches each cluster against the frozen snapshot and decides enrollments, without persisting.
    private func assign(
        _ clusters: [SpeakerCluster],
        against snapshot: SpeakerManager,
        known: [Voiceprint],
        threshold: Float,
        enrollFloor: Float
    ) -> (resolved: [String: SpeakerIdentity], enrolled: [Voiceprint]) {
        var byID: [String: Voiceprint] = [:]
        for voiceprint in known {
            byID[voiceprint.id] = voiceprint
        }

        var claimed: Set<String> = []
        var enrolled: [Voiceprint] = []
        var resolved: [String: SpeakerIdentity] = [:]

        // Longest-speaking cluster claims a contested identity first; later claimants enroll fresh.
        for cluster in clusters.sorted(by: { $0.duration > $1.duration }) {
            guard cluster.embedding.count == SpeakerManager.embeddingSize else { continue }
            let matches = snapshot.findMatchingSpeakers(with: cluster.embedding, speakerThreshold: threshold)
            if let match = matches.first(where: { !claimed.contains($0.id) }) {
                claimed.insert(match.id)
                resolved[cluster.id] = SpeakerIdentity(id: match.id, name: byID[match.id]?.name)
            } else if cluster.duration >= enrollFloor {
                let fresh = Voiceprint(
                    id: UUID().uuidString, name: nil, embedding: cluster.embedding, duration: cluster.duration
                )
                enrolled.append(fresh)
                claimed.insert(fresh.id)
                resolved[cluster.id] = SpeakerIdentity(id: fresh.id, name: nil)
            }
        }
        return (resolved, enrolled)
    }

    /// A `SpeakerManager` seeded with the known voiceprints for read-only matching. Built via
    /// `upsertSpeaker` to avoid naming FluidAudio's `Speaker`, which a same-named module type shadows.
    private func matcher(seededWith known: [Voiceprint], threshold: Float) -> SpeakerManager {
        var manager = SpeakerManager(speakerThreshold: threshold)
        for voiceprint in known where voiceprint.embedding.count == SpeakerManager.embeddingSize {
            manager.upsertSpeaker(
                id: voiceprint.id, currentEmbedding: voiceprint.embedding, duration: voiceprint.duration
            )
        }
        return manager
    }

    // MARK: Persistence

    private func load() throws -> [Voiceprint] {
        let url = try voiceprintsURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Voiceprint].self, from: Data(contentsOf: url))
    }

    private func save(_ voiceprints: [Voiceprint]) throws {
        try voiceprints.writeJSON(to: voiceprintsURL())
    }

    private func voiceprintsURL() throws -> URL {
        let folder: URL = if let directory {
            directory
        } else {
            try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Hark", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("voiceprints.json")
    }
}
