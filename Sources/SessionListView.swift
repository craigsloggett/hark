import SwiftUI

/// The recordings sidebar: past sessions, newest first, titled by when they were recorded.
struct SessionListView: View {
    @Bindable var model: LabelingModel

    var body: some View {
        List(model.library.sessions, selection: $model.selection) { session in
            Text(session.title)
        }
        .navigationTitle("Recordings")
        .overlay {
            if model.library.sessions.isEmpty {
                ContentUnavailableView(
                    "No recordings yet",
                    systemImage: "waveform",
                    description: Text("Transcribed recordings show up here.")
                )
            }
        }
    }
}
