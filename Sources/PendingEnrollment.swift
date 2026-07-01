import Foundation

/// A duplicate an enroll would create, captured so the labeling window can ask whether to reuse the
/// voice Hark already knows or save a separate one. Without this, naming a speaker Hark has heard
/// before forks them into a second voiceprint, fragmenting one person across recordings.
struct PendingEnrollment: Identifiable {
    /// Why the enroll looks like a duplicate, which shapes the prompt.
    enum Reason: Equatable {
        /// The typed name already belongs to a saved voice.
        case sameName
        /// The voice is within the confident-match distance of a saved voice.
        case nearDuplicate(Float)
    }

    let id = UUID()
    let token: String
    /// The name the user typed, carried through if they enroll separately after all.
    let name: String?
    /// The undo label the eventual enroll should record.
    let undoLabel: String
    let match: Voiceprint
    let reason: Reason

    private var matchName: String {
        match.name ?? "a saved voice"
    }

    var dialogTitle: String {
        "Use \(matchName)?"
    }

    var useButtonTitle: String {
        "Add to \(matchName)"
    }

    var createButtonTitle: String {
        "Save Separately"
    }

    var dialogMessage: String {
        switch reason {
        case .sameName:
            "You already have a saved voice named \(matchName). Add this recording to it, "
                + "or keep them as separate voices?"
        case .nearDuplicate:
            "This sounds like \(matchName), which Hark already knows. Add this recording to "
                + "\(matchName), or save it as a separate voice?"
        }
    }
}
