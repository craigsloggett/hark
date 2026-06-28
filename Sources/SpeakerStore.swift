import FluidAudio
import Foundation
import OSLog

/// One diarized speaker from a single session: the raw cluster id, its mean voiceprint, and how
/// long it spoke. The unit of cross-session matching.
struct SpeakerCluster {
    let id: String
    let centroid: [Float]
    let duration: Float
}

/// A persisted speaker voiceprint: a stable id, its mean embedding, and an optional name set once
/// the speaker is labelled. Hark's own minimal store, decoupled from FluidAudio's internal `Speaker`
/// struct so the on-disk format stays stable across library bumps.
struct Voiceprint: Codable, Equatable {
    let id: String
    let name: String?
    let embedding: [Float]
    let duration: Float
}

/// The stable identity a session speaker resolved to. `name` is `nil` until the voiceprint is named.
struct SpeakerIdentity: Codable, Equatable {
    let id: String
    let name: String?
}

/// Matches each session's diarized speakers against a persisted voiceprint database so a recurring
/// voice keeps a stable identity across sessions. Matching is read-only against the pre-session
/// snapshot, so two distinct voices in one meeting can't collapse into one another and one bad
/// session can't corrupt a stored voiceprint. An unmatched speaker is enrolled as a new, unnamed
/// voiceprint only when it spoke long enough to trust, so brief diarization fragments stay
/// positional instead of polluting the database.
actor SpeakerStore {
    private let directory: URL?
    private let logger = Logger(category: "SpeakerStore")

    /// - Parameter directory: the folder holding `voiceprints.json`; defaults to the sandbox
    ///   container's `Application Support/Hark`. Tests inject a temporary directory.
    init(directory: URL? = nil) {
        self.directory = directory
    }

    /// Resolves each cluster to a stable identity and persists any newly enrolled voiceprints.
    /// - Returns: cluster id to resolved identity. Empty when the database can't be read, so a
    ///   corrupt file degrades to positional speakers rather than being overwritten.
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
    /// - Returns: the per-cluster identities and the voiceprints to enroll.
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

        // The longest-speaking cluster claims a contested identity first; later claimants to an
        // already-claimed id enroll fresh.
        for cluster in clusters.sorted(by: { $0.duration > $1.duration }) {
            guard cluster.centroid.count == SpeakerManager.embeddingSize else {
                let line = "Cluster \(cluster.id): \(cluster.centroid.count)-d embedding, skipping"
                logger.warning("\(line, privacy: .public)")
                continue
            }
            let matches = snapshot.findMatchingSpeakers(with: cluster.centroid, speakerThreshold: threshold)
            if let match = matches.first(where: { !claimed.contains($0.id) }) {
                claimed.insert(match.id)
                resolved[cluster.id] = SpeakerIdentity(id: match.id, name: byID[match.id]?.name)
                let distance = String(format: "%.3f", match.distance)
                let line = "Cluster \(cluster.id) matched \(match.id) at \(distance)"
                logger.log("\(line, privacy: .public)")
            } else if cluster.duration >= enrollFloor {
                let fresh = Voiceprint(
                    id: UUID().uuidString, name: nil, embedding: cluster.centroid, duration: cluster.duration
                )
                enrolled.append(fresh)
                claimed.insert(fresh.id)
                resolved[cluster.id] = SpeakerIdentity(id: fresh.id, name: nil)
                let line = "Cluster \(cluster.id) enrolled \(fresh.id)"
                logger.log("\(line, privacy: .public)")
            } else {
                let secs = String(format: "%.1f", cluster.duration)
                let line = "Cluster \(cluster.id) unmatched, \(secs)s under enroll floor; left positional"
                logger.log("\(line, privacy: .public)")
            }
        }
        return (resolved, enrolled)
    }

    /// A `SpeakerManager` seeded with the known voiceprints, used read-only for distance matching.
    /// `upsertSpeaker` builds each entry internally, so we never name FluidAudio's `Speaker` type
    /// (its module exposes a same-named type that shadows the module qualifier).
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
