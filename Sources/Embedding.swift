import FluidAudio

/// A speaker embedding validated against the model's dimension at construction, so code past this
/// boundary never re-checks sizes (parse, don't validate).
struct Embedding: Equatable {
    let values: [Float]

    /// `nil` when `values` is not exactly the model's embedding size.
    init?(_ values: [Float]) {
        guard values.count == SpeakerManager.embeddingSize else { return nil }
        self.values = values
    }
}

extension Embedding: Codable {
    /// Encoded as the bare value array, so the JSON shape matches a plain `[Float]`.
    init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer().decode([Float].self)
        guard let embedding = Embedding(values) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected \(SpeakerManager.embeddingSize) values, got \(values.count)"
            ))
        }
        self = embedding
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}
