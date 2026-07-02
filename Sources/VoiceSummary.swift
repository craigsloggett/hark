/// A known person as the People manager lists them.
struct VoiceSummary: Identifiable, Equatable {
    let id: String
    let name: String?
    let recordingCount: Int

    var isNamed: Bool {
        name != nil
    }

    var displayName: String {
        name ?? "Unnamed"
    }
}
