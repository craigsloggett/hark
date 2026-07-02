import FluidAudio
import Foundation
import OSLog

/// One session's diarized speaker, holding the diarizer's cluster id, its mean embedding, and speech duration.
struct SpeakerCluster {
    let id: String
    let embedding: Embedding
    let duration: Float
}

/// Two saved voices close enough to be likely duplicates, with the cosine distance between them.
struct VoicePair {
    let first: Voiceprint
    let second: Voiceprint
    let distance: Float
}

enum SpeakerStoreError: Error {
    case unknownVoiceprint
}

/// Matches each session's diarized speakers against a persisted voiceprint database so a recurring
/// voice keeps a stable identity across sessions. Matching is read-only against a pre-session
/// snapshot, so two voices in one meeting can't collapse together (unmatched speakers enroll only
/// past a duration floor, keeping brief diarization fragments out of the database).
actor SpeakerStore {
    /// The process-wide store. The naming UI and the transcription pipeline share one instance so
    /// their writes to `voiceprints.json` serialize through a single actor.
    static let shared = SpeakerStore()

    private let directory: URL?
    private let logger = Logger(category: "SpeakerStore")

    /// - Parameter directory: where `voiceprints.json` lives (defaults to the sandbox container's
    ///   `Application Support/Hark`).
    init(directory: URL? = nil) {
        self.directory = directory
    }

    /// Resolves each cluster to a stable identity, enrolling and persisting new voiceprints.
    /// - Returns: cluster id to identity (empty when the database can't be read, so a corrupt file
    ///   degrades to positional speakers instead of being overwritten).
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
        writeDebugDump(clusters, against: snapshot, threshold: threshold)

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

    // MARK: Editing

    /// Every saved voiceprint, including merge tombstones so the caller can resolve redirects. Throws
    /// only when the file exists but can't be decoded (an absent file is an empty database).
    func voiceprints() throws -> [Voiceprint] {
        try load()
    }

    /// The surviving voiceprint for an id, following merge redirects, or `nil` if unknown.
    func voiceprint(id: String) throws -> Voiceprint? {
        try Voiceprint.survivor(of: id, in: load().byID)
    }

    /// Sets (or clears) a voiceprint's name, following merge redirects to the survivor. Whitespace-only
    /// names clear it back to unnamed. A missing `id` is a no-op so the caller doesn't have to guard
    /// against a since-deleted voice.
    func rename(id: String, to name: String?) throws {
        var voiceprints = try load()
        guard let index = survivorIndex(of: id, in: voiceprints) else { return }
        voiceprints[index] = voiceprints[index].renamed(to: name?.normalizedName)
        try save(voiceprints)
    }

    /// Removes a voiceprint, following merge redirects to the survivor. A missing `id` is a no-op.
    func remove(id: String) throws {
        let voiceprints = try load()
        guard let index = survivorIndex(of: id, in: voiceprints) else { return }
        let survivorID = voiceprints[index].id
        try save(voiceprints.filter { $0.id != survivorID })
    }

    /// Overwrites the whole database (the labeling window's undo primitive); tombstones are kept as given.
    func replaceAll(_ voiceprints: [Voiceprint]) throws {
        try save(voiceprints)
    }

    /// Enrolls a brand-new voiceprint from a diarized embedding, e.g. when the labeling window adds a
    /// new voice. A deliberate action, so it skips the automatic enrollment's duration floor.
    func enroll(embedding: Embedding, duration: Float, name: String?) throws -> Voiceprint {
        var voiceprints = try load()
        let sample = VoiceSample(id: UUID(), embedding: embedding, duration: duration, enrolledAt: Date())
        let voiceprint = Voiceprint(id: UUID().uuidString, name: name?.normalizedName, samples: [sample])
        voiceprints.append(voiceprint)
        try save(voiceprints)
        return voiceprint
    }

    /// Adds an enrollment sample to an existing voiceprint (following merge redirects to the survivor),
    /// e.g. when the user confirms "this is someone I know", so the identity learns the new session's voice.
    /// - Throws: `SpeakerStoreError.unknownVoiceprint`.
    func addSample(toVoiceprint id: String, embedding: Embedding, duration: Float) throws {
        var voiceprints = try load()
        guard let index = survivorIndex(of: id, in: voiceprints) else {
            throw SpeakerStoreError.unknownVoiceprint
        }
        let sample = VoiceSample(id: UUID(), embedding: embedding, duration: duration, enrolledAt: Date())
        voiceprints[index] = voiceprints[index].adding(sample)
        try save(voiceprints)
    }

    /// Merges one voiceprint into another (two over-split speakers are the same person): the survivor
    /// keeps its id and name, gains the source's samples, and the source becomes a redirect tombstone
    /// so other sessions bound to it still resolve. Both ids follow merge redirects; a no-op returning
    /// the survivor when they resolve to the same voiceprint.
    /// - Throws: `SpeakerStoreError.unknownVoiceprint` when either id is missing.
    func merge(_ sourceID: String, into destinationID: String) throws -> Voiceprint {
        var voiceprints = try load()
        guard let destinationIndex = survivorIndex(of: destinationID, in: voiceprints),
              let sourceIndex = survivorIndex(of: sourceID, in: voiceprints)
        else {
            throw SpeakerStoreError.unknownVoiceprint
        }
        let source = voiceprints[sourceIndex]
        let destination = voiceprints[destinationIndex]
        guard source.id != destination.id else { return destination }
        let merged = Voiceprint(
            id: destination.id,
            name: destination.name ?? source.name,
            samples: destination.samples + source.samples,
            redirectID: destination.redirectID
        )
        voiceprints[destinationIndex] = merged
        voiceprints[sourceIndex] = source.redirected(to: destination.id)
        try save(voiceprints)
        return merged
    }

    /// The nearest named voiceprint to an embedding and its cosine distance, for warning before a
    /// deliberate enroll duplicates a voice the user already saved. Considers only named survivors, so
    /// an unnamed auto-enrollment is never offered as the match. `nil` when there is no named voice.
    func nearestNamed(to embedding: Embedding) throws -> (voiceprint: Voiceprint, distance: Float)? {
        let named = try load().filter { !$0.isTombstone && $0.name != nil && $0.centroid != nil }
        guard !named.isEmpty else { return nil }
        // Seed permissively (threshold 2 spans the cosine-distance range) so the query ranks every
        // named voice; matches are nearest-first, so `.first` is the closest.
        let snapshot = matcher(seededWith: named, threshold: 2)
        guard let match = snapshot.findMatchingSpeakers(with: embedding.values, speakerThreshold: 2).first,
              let voiceprint = named.first(where: { $0.id == match.id })
        else { return nil }
        return (voiceprint, match.distance)
    }

    /// Unordered pairs of surviving voiceprints whose centroids are within `distance`, nearest first,
    /// for surfacing likely duplicate voices to merge. Each pair appears once; self-pairs are excluded.
    func duplicatePairs(within distance: Float) throws -> [VoicePair] {
        let survivors = try load().filter { !$0.isTombstone && $0.centroid != nil }
        guard survivors.count > 1 else { return [] }
        let snapshot = matcher(seededWith: survivors, threshold: 2)
        let lookup = survivors.byID
        var pairs: [VoicePair] = []
        var seen: Set<String> = []
        for voiceprint in survivors {
            guard let centroid = voiceprint.centroid else { continue }
            let matches = snapshot.findMatchingSpeakers(with: centroid.values, speakerThreshold: distance)
            for match in matches where match.id != voiceprint.id {
                let key = [voiceprint.id, match.id].sorted().joined(separator: "|")
                guard seen.insert(key).inserted, let other = lookup[match.id] else { continue }
                pairs.append(VoicePair(first: voiceprint, second: other, distance: match.distance))
            }
        }
        return pairs.sorted { $0.distance < $1.distance }
    }

    /// The array index of the surviving voiceprint for `id`. Sessions merged elsewhere can still hold
    /// a tombstoned id, so every edit resolves to the survivor rather than mutating a tombstone.
    private func survivorIndex(of id: String, in voiceprints: [Voiceprint]) -> Int? {
        guard let survivor = Voiceprint.survivor(of: id, in: voiceprints.byID) else { return nil }
        return voiceprints.firstIndex { $0.id == survivor.id }
    }

    // MARK: Matching

    /// Matches each cluster against the frozen snapshot and decides enrollments, without persisting.
    private func assign(
        _ clusters: [SpeakerCluster],
        against snapshot: SpeakerManager,
        known: [Voiceprint],
        threshold: Float,
        enrollFloor: Float
    ) -> (resolved: [String: SpeakerIdentity], enrolled: [Voiceprint]) {
        let byID = known.byID
        var claimed: Set<String> = []
        var enrolled: [Voiceprint] = []
        var resolved: [String: SpeakerIdentity] = [:]

        // Longest-speaking cluster claims a contested identity first; id breaks ties so the claim
        // order is deterministic (later claimants enroll fresh).
        for cluster in clusters.sorted(by: {
            $0.duration != $1.duration ? $0.duration > $1.duration : $0.id < $1.id
        }) {
            let matches = snapshot.findMatchingSpeakers(with: cluster.embedding.values, speakerThreshold: threshold)
            // matches is nearest-first so the first unclaimed match is the closest identity still
            // available to this cluster.
            if let match = matches.first(where: { !claimed.contains($0.id) }) {
                claimed.insert(match.id)
                resolved[cluster.id] = SpeakerIdentity(
                    id: match.id, name: byID[match.id]?.name, distance: match.distance
                )
            } else if cluster.duration >= enrollFloor {
                let sample = VoiceSample(
                    id: UUID(), embedding: cluster.embedding, duration: cluster.duration, enrolledAt: Date()
                )
                let fresh = Voiceprint(id: UUID().uuidString, name: nil, samples: [sample])
                enrolled.append(fresh)
                claimed.insert(fresh.id)
                resolved[cluster.id] = SpeakerIdentity(id: fresh.id, name: nil, distance: nil)
            }
        }
        return (resolved, enrolled)
    }

    /// A `SpeakerManager` seeded with the known voiceprints for read-only matching; tombstones are
    /// skipped so a merged-away id can never be matched again. Built via `upsertSpeaker` to avoid
    /// naming FluidAudio's `Speaker`, which a same-named module type shadows.
    private func matcher(seededWith known: [Voiceprint], threshold: Float) -> SpeakerManager {
        var manager = SpeakerManager(speakerThreshold: threshold)
        for voiceprint in known where !voiceprint.isTombstone {
            guard let centroid = voiceprint.centroid else { continue }
            manager.upsertSpeaker(
                id: voiceprint.id, currentEmbedding: centroid.values, duration: voiceprint.totalDuration
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

    // MARK: Debug

    /// When `HARK_SPEAKER_DEBUG` is set, writes each cluster's nearest known voiceprint and distance
    /// to `matches.debug.json` beside the database, for tuning `speakerMatchThreshold`.
    private func writeDebugDump(_ clusters: [SpeakerCluster], against snapshot: SpeakerManager, threshold: Float) {
        guard ProcessInfo.processInfo.flag(forKey: "HARK_SPEAKER_DEBUG") else { return }
        let dump = clusters
            .map { cluster -> DebugMatch in
                // 2 is the maximum cosine distance, so this ranks every known voiceprint (.first is nearest).
                let nearest = snapshot.findMatchingSpeakers(with: cluster.embedding.values, speakerThreshold: 2).first
                return DebugMatch(
                    cluster: cluster.id,
                    duration: Double(cluster.duration),
                    nearest: nearest?.id,
                    distance: nearest.map { Double($0.distance) },
                    threshold: Double(threshold)
                )
            }
        do {
            let folder = try voiceprintsURL().deletingLastPathComponent()
            try dump.writeJSON(to: folder.appendingPathComponent("matches.debug.json"), sortedKeys: true)
        } catch {
            logger.error("Couldn't write speaker debug dump: \(error, privacy: .public)")
        }
    }

    /// One cluster's match outcome in the `HARK_SPEAKER_DEBUG` dump.
    private struct DebugMatch: Encodable {
        let cluster: String
        let duration: Double
        let nearest: String?
        let distance: Double?
        let matched: Bool

        init(cluster: String, duration: Double, nearest: String?, distance: Double?, threshold: Double) {
            self.cluster = cluster
            self.duration = duration
            self.nearest = nearest
            self.distance = distance
            matched = distance.map { $0 <= threshold } ?? false
        }
    }
}
