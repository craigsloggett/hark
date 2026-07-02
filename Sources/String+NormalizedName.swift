import Foundation

extension String {
    /// The trimmed text, or `nil` when nothing remains, so "no name" has one representation.
    var normalizedName: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
