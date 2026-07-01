import SwiftUI

extension Color {
    private static let speakerPalette: [Color] = [
        Color(red: 0.18, green: 0.83, blue: 0.78), // teal
        Color(red: 0.75, green: 0.48, blue: 0.96), // purple
        Color(red: 1.00, green: 0.65, blue: 0.24), // orange
        Color(red: 1.00, green: 0.43, blue: 0.54), // pink
        Color(red: 0.36, green: 0.60, blue: 1.00), // blue
        Color(red: 0.44, green: 0.83, blue: 0.46), // green
    ]

    /// A stable chip and dot color for a speaker, hashed from its identity key (voiceprint id or
    /// token) so the same voice keeps its color across a session.
    static func speaker(for key: String) -> Color {
        guard !key.isEmpty else { return speakerPalette[0] }
        var hash = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return speakerPalette[abs(hash) % speakerPalette.count]
    }
}
