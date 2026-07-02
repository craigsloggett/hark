/// A saved voice as the global Voices manager lists it.
struct VoiceSummary: Identifiable, Equatable {
    let id: String
    let name: String?
    let sampleCount: Int
    let recordingCount: Int

    var isNamed: Bool {
        name != nil
    }

    var displayName: String {
        name ?? "Unnamed voice"
    }
}
