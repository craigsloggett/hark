import Foundation

/// A session's user-assigned identity in `metadata.json`: an optional custom name and tags. A missing
/// file is the common case and means the session has neither.
struct SessionMetadata: Hashable {
    var name: String?
    var tags: [String]

    init(name: String? = nil, tags: [String] = []) {
        self.name = name
        self.tags = tags
    }

    /// Adds a trimmed tag, ignoring blanks and case-insensitive duplicates; keeps insertion order.
    @discardableResult
    mutating func addTag(_ raw: String) -> Bool {
        guard let tag = raw.normalizedName,
              !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
        else { return false }
        tags.append(tag)
        return true
    }

    mutating func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

extension SessionMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    /// Sparse, like `SessionSpeaker`: absent fields stay out of the JSON so "nothing assigned" has one
    /// representation.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        if !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
    }
}
