import SwiftUI

struct ContentView: View {
    @State private var recorder = AudioRecorder()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(recorder.isRecording ? Color.red : Color.secondary)
                .symbolEffect(.pulse, isActive: recorder.isRecording)

            Text(recorder.isRecording ? "Recording" : "Ready")
                .font(.headline)

            Button(recorder.isRecording ? "Stop" : "Record") {
                recorder.toggle()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(recorder.isRecording ? Color.red : Color.accentColor)

            if let url = recorder.lastRecordingURL {
                Text("Saved \(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(minWidth: 320, minHeight: 280)
    }
}
