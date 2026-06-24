import Foundation

extension Encodable {
    /// Encodes the value as pretty-printed JSON and writes it atomically to `url`.
    /// - Parameter sortedKeys: sort object keys for stable, diff-friendly debug dumps.
    func writeJSON(to url: URL, sortedKeys: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = sortedKeys ? [.prettyPrinted, .sortedKeys] : [.prettyPrinted]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
