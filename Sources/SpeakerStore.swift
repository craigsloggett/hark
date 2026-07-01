import FluidAudio
import Foundation
import OSLog

/// One session's diarized speaker, holding the diarizer's cluster id, its mean embedding, and speech duration.
struct SpeakerCluster {
    let id: String
    let embedding: [Float]
    let duration: Float
}

/// One enrollment sample for a voiceprint, a diarized mean embedding with its speech duration and
/// capture time. `id` addresses the sample stably across sessions.
struct VoiceSample: Codable, Equatable, Identifiable {
    let id: UUID
    let embedding: [Float]
    let duration: Float
    let enrolledAt: Date
}

/// A speaker's cross-session identity, backed by a capped list of enrollment samples. The vector
/// matched against is the samples' duration-weighted `centroid`, derived when seeding the matcher
/// rather than stored. Persisted as `{id, name, samples}`.
struct Voiceprint: Codable, Equatable {
    let id: String
    let name: String?
    let samples: [VoiceSample]
    /// When set, this voiceprint was merged into another; lookups follow the redirect to the survivor
    /// so other sessions still bound to this id resolve instead of falling back to positional.
    let redirectID: String?

    /// Cap on samples per voiceprint, from `Preferences`. The initializer keeps the newest this many.
    static var maxSamples: Int {
        Preferences.voiceprintMaxSamples
    }

    init(id: String, name: String?, samples: [VoiceSample], redirectID: String? = nil) {
        self.id = id
        self.name = name
        self.samples = Self.capped(samples)
        self.redirectID = redirectID
    }

    /// The samples' duration-weighted mean embedding, the vector matched against. A single-sample
    /// print returns that embedding unchanged.
    var centroid: [Float] {
        guard let first = samples.first else { return [] }
        guard samples.count > 1 else { return first.embedding }
        var weighted = [Float](repeating: 0, count: first.embedding.count)
        var weight: Float = 0
        for sample in samples where sample.embedding.count == weighted.count {
            weight += sample.duration
            for index in weighted.indices {
                weighted[index] += sample.embedding[index] * sample.duration
            }
        }
        guard weight > 0 else { return first.embedding }
        for index in weighted.indices {
            weighted[index] /= weight
        }
        return weighted
    }

    /// Total enrolled speech across the samples, seeded into the matcher as the speaker's duration.
    var totalDuration: Float {
        samples.reduce(0) { $0 + $1.duration }
    }

    /// When the newest sample was enrolled, the closest thing to "last heard" for the naming UI.
    var lastEnrolledAt: Date? {
        samples.map(\.enrolledAt).max()
    }

    /// The newest `maxSamples` by enrollment time, dropping the oldest (a no-op at or under the cap).
    private static func capped(_ samples: [VoiceSample]) -> [VoiceSample] {
        guard samples.count > maxSamples else { return samples }
        return Array(samples.sorted { $0.enrolledAt < $1.enrolledAt }.suffix(maxSamples))
    }
}

extension Voiceprint: Identifiable {}

extension Voiceprint {
    /// Follows `redirectID` chains to the surviving voiceprint after merges, or `nil` when the id is
    /// unknown or the chain breaks. Guards against cycles.
    static func survivor(of id: String, in voiceprints: [String: Voiceprint]) -> Voiceprint? {
        var current = id
        var seen: Set<String> = []
        while seen.insert(current).inserted, let voiceprint = voiceprints[current] {
            guard let redirect = voiceprint.redirectID else { return voiceprint }
            current = redirect
        }
        return nil
    }
}

enum SpeakerStoreError: Error {
    case invalidEmbedding
    case unknownVoiceprint
}

/// A speaker's resolved cross-session identity, the result of matching one session's clusters against
/// the voiceprint database. `TranscriptionService` maps these onto the persisted `SessionSpeaker` overlay.
struct SpeakerIdentity: Codable, Equatable {
    let id: String
    let name: String?
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
    private let now: @Sendable () -> Date
    private let uuid: @Sendable () -> UUID
    private let logger = Logger(category: "SpeakerStore")

    /// - Parameters:
    ///   - directory: where `voiceprints.json` lives (defaults to the sandbox container's
    ///     `Application Support/Hark`).
    ///   - now: enrollment-time source, injected so tests can pin `enrolledAt`.
    ///   - uuid: id source for fresh voiceprints and samples, injected so tests can pin ids.
    init(
        directory: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        uuid: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.directory = directory
        self.now = now
        self.uuid = uuid
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
        try Voiceprint.survivor(of: id, in: byID(load()))
    }

    /// Sets (or clears) a voiceprint's name. Whitespace-only names clear it back to unnamed. A
    /// missing `id` is a no-op so the caller doesn't have to guard against a since-deleted voice.
    func rename(id: String, to name: String?) throws {
        var voiceprints = try load()
        guard let index = voiceprints.firstIndex(where: { $0.id == id }) else { return }
        let existing = voiceprints[index]
        voiceprints[index] = Voiceprint(
            id: existing.id, name: normalizedName(name), samples: existing.samples, redirectID: existing.redirectID
        )
        try save(voiceprints)
    }

    /// Removes a voiceprint so a stray or misheard voice can be forgotten.
    func remove(id: String) throws {
        let voiceprints = try load()
        guard voiceprints.contains(where: { $0.id == id }) else { return }
        try save(voiceprints.filter { $0.id != id })
    }

    /// Enrolls a brand-new voiceprint from a diarized embedding, e.g. when the labeling window adds a
    /// new voice. A deliberate action, so it skips the automatic enrollment's duration floor.
    /// - Throws: `SpeakerStoreError.invalidEmbedding` when the embedding is the wrong size.
    func enroll(embedding: [Float], duration: Float, name: String?) throws -> Voiceprint {
        guard embedding.count == SpeakerManager.embeddingSize else { throw SpeakerStoreError.invalidEmbedding }
        var voiceprints = try load()
        let sample = VoiceSample(id: uuid(), embedding: embedding, duration: duration, enrolledAt: now())
        let voiceprint = Voiceprint(id: uuid().uuidString, name: normalizedName(name), samples: [sample])
        voiceprints.append(voiceprint)
        try save(voiceprints)
        return voiceprint
    }

    /// Adds an enrollment sample to an existing voiceprint, e.g. when the user confirms "this is
    /// someone I know", so the identity learns the new session's voice.
    /// - Throws: `SpeakerStoreError.invalidEmbedding` or `.unknownVoiceprint`.
    func addSample(toVoiceprint id: String, embedding: [Float], duration: Float) throws {
        guard embedding.count == SpeakerManager.embeddingSize else { throw SpeakerStoreError.invalidEmbedding }
        var voiceprints = try load()
        guard let index = voiceprints.firstIndex(where: { $0.id == id }) else {
            throw SpeakerStoreError.unknownVoiceprint
        }
        let existing = voiceprints[index]
        let sample = VoiceSample(id: uuid(), embedding: embedding, duration: duration, enrolledAt: now())
        voiceprints[index] = Voiceprint(
            id: existing.id, name: existing.name, samples: existing.samples + [sample], redirectID: existing.redirectID
        )
        try save(voiceprints)
    }

    /// Merges one voiceprint into another (two over-split speakers are the same person): the survivor
    /// keeps its id and name, gains the source's samples, and the source becomes a redirect tombstone
    /// so other sessions bound to it still resolve. A no-op returning the survivor when the ids match.
    /// - Throws: `SpeakerStoreError.unknownVoiceprint` when either id is missing.
    func merge(_ sourceID: String, into destinationID: String) throws -> Voiceprint {
        var voiceprints = try load()
        guard let destinationIndex = voiceprints.firstIndex(where: { $0.id == destinationID }) else {
            throw SpeakerStoreError.unknownVoiceprint
        }
        guard sourceID != destinationID else { return voiceprints[destinationIndex] }
        guard let sourceIndex = voiceprints.firstIndex(where: { $0.id == sourceID }) else {
            throw SpeakerStoreError.unknownVoiceprint
        }
        let source = voiceprints[sourceIndex]
        let destination = voiceprints[destinationIndex]
        let merged = Voiceprint(
            id: destination.id,
            name: destination.name ?? source.name,
            samples: destination.samples + source.samples,
            redirectID: destination.redirectID
        )
        voiceprints[destinationIndex] = merged
        voiceprints[sourceIndex] = Voiceprint(id: source.id, name: nil, samples: [], redirectID: destination.id)
        try save(voiceprints)
        return merged
    }

    private func byID(_ voiceprints: [Voiceprint]) -> [String: Voiceprint] {
        Dictionary(voiceprints.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func normalizedName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
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
        var byID: [String: Voiceprint] = [:]
        for voiceprint in known {
            byID[voiceprint.id] = voiceprint
        }

        var claimed: Set<String> = []
        var enrolled: [Voiceprint] = []
        var resolved: [String: SpeakerIdentity] = [:]

        // Longest-speaking cluster claims a contested identity first; id breaks ties so the claim
        // order is deterministic (later claimants enroll fresh).
        for cluster in clusters.sorted(by: {
            $0.duration != $1.duration ? $0.duration > $1.duration : $0.id < $1.id
        }) {
            guard cluster.embedding.count == SpeakerManager.embeddingSize else { continue }
            let matches = snapshot.findMatchingSpeakers(with: cluster.embedding, speakerThreshold: threshold)
            // matches is nearest-first so the first unclaimed match is the closest identity still
            // available to this cluster.
            if let match = matches.first(where: { !claimed.contains($0.id) }) {
                claimed.insert(match.id)
                resolved[cluster.id] = SpeakerIdentity(id: match.id, name: byID[match.id]?.name)
            } else if cluster.duration >= enrollFloor {
                let sample = VoiceSample(
                    id: uuid(), embedding: cluster.embedding, duration: cluster.duration, enrolledAt: now()
                )
                let fresh = Voiceprint(id: uuid().uuidString, name: nil, samples: [sample])
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
        for voiceprint in known {
            let centroid = voiceprint.centroid
            guard centroid.count == SpeakerManager.embeddingSize else { continue }
            manager.upsertSpeaker(
                id: voiceprint.id, currentEmbedding: centroid, duration: voiceprint.totalDuration
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
            .filter { $0.embedding.count == SpeakerManager.embeddingSize }
            .map { cluster -> DebugMatch in
                // 2 is the maximum cosine distance, so this ranks every known voiceprint (.first is nearest).
                let nearest = snapshot.findMatchingSpeakers(with: cluster.embedding, speakerThreshold: 2).first
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
