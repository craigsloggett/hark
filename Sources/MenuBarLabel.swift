import SwiftUI

/// The menu bar icon, Hark's waveform at rest, with distinct recording and transcribing states.
struct MenuBarLabel: View {
    @Environment(AudioRecorder.self) private var recorder

    var body: some View {
        switch iconState {
        case .idle:
            Image("MenuBarIcon")
                .renderingMode(.template)
        case .recording:
            Image(systemName: "record.circle.fill")
        case .transcribing:
            Image(systemName: "ellipsis.circle")
        }
    }

    private enum IconState {
        case idle
        case recording
        case transcribing
    }

    private var iconState: IconState {
        if recorder.transcriptionState == .running {
            return .transcribing
        }
        return recorder.isRecording ? .recording : .idle
    }
}
