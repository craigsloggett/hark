import SwiftUI

/// The sidebar: the global voices manager, then past recordings newest first, titled by when they
/// were recorded.
struct SessionListView: View {
    @Bindable var model: LabelingModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section {
                Label("All Voices", systemImage: "person.2.wave.2")
                    .tag(SidebarItem.voices)
            }
            Section("Recordings") {
                ForEach(model.library.sessions) { session in
                    Text(session.title).tag(SidebarItem.session(session.url))
                }
                if model.library.sessions.isEmpty {
                    Text("No recordings yet")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Hark")
    }
}
