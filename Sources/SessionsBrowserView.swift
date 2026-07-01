import SwiftUI

/// The recordings window: a session list, the transcript chat, and the People inspector. Its appear
/// and disappear drive the app's Dock activation.
struct SessionsBrowserView: View {
    @Environment(AudioRecorder.self) private var recorder
    @State private var model = LabelingModel()
    @State private var showsPeople = true

    var body: some View {
        NavigationSplitView {
            SessionListView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            TranscriptChatView(model: model)
                .inspector(isPresented: $showsPeople) {
                    PeopleInspectorView(model: model)
                        .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            Task { await model.undo() }
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!model.canUndo)
                        .help(model.undoActionLabel ?? "Nothing to undo")
                        .keyboardShortcut("z", modifiers: .command)
                    }
                    ToolbarItem {
                        Button {
                            showsPeople.toggle()
                        } label: {
                            Label("People", systemImage: "person.2")
                        }
                    }
                }
        }
        .task {
            model.library.reload()
            await model.refreshVoiceprints()
            if model.selection == nil {
                model.selection = model.library.sessions.first?.url
            }
        }
        .task(id: model.selection) {
            await model.loadSelected()
        }
        // A finished transcription adds a new session, so refresh the list when one lands.
        .onChange(of: recorder.transcriptionState) {
            model.library.reload()
        }
        .onAppear { WindowActivation.shared.didOpen() }
        .onDisappear { WindowActivation.shared.didClose() }
        .confirmationDialog(
            model.pendingEnrollment?.dialogTitle ?? "",
            isPresented: pendingEnrollmentPresented,
            titleVisibility: .visible,
            presenting: model.pendingEnrollment
        ) { pending in
            Button(pending.useButtonTitle) { Task { await model.addPendingToExistingVoice() } }
            Button(pending.createButtonTitle) { Task { await model.createPendingAsNewVoice() } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.dialogMessage)
        }
    }

    /// Drives the duplicate-voice confirmation from the model's pending enroll; dismissing cancels it.
    private var pendingEnrollmentPresented: Binding<Bool> {
        Binding(
            get: { model.pendingEnrollment != nil },
            set: { if !$0 { model.cancelPendingEnrollment() } }
        )
    }
}
