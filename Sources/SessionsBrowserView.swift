import SwiftUI

/// The transcripts window: the transcript list, the chat pane, and the People inspector. Its appear
/// and disappear drive the app's Dock activation.
struct SessionsBrowserView: View {
    @Environment(AudioRecorder.self) private var recorder
    @State private var model = LabelingModel()
    @State private var showsPeople = true
    @State private var showsTags = false

    var body: some View {
        NavigationSplitView {
            SessionListView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detailPane
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
        // `initial: true` covers a fresh open, where the flag is already set at first evaluation.
        .onChange(of: SessionsNavigation.shared.wantsLatest, initial: true) {
            jumpToLatestIfRequested()
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

    /// The right pane: the selected transcript with its People inspector.
    private var detailPane: some View {
        TranscriptChatView(model: model)
            .inspector(isPresented: $showsPeople) {
                PeopleInspectorView(model: model)
                    .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        showsTags = true
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }
                    .disabled(model.selection == nil)
                    .popover(isPresented: $showsTags, arrowEdge: .bottom) {
                        SessionTagsPopover(model: model)
                    }
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

    /// Consumes the menu's one-shot request to select the newest transcript.
    private func jumpToLatestIfRequested() {
        guard SessionsNavigation.shared.wantsLatest else { return }
        SessionsNavigation.shared.wantsLatest = false
        model.library.reload()
        model.selection = model.library.sessions.first?.url
    }

    /// Drives the duplicate-voice confirmation from the model's pending enroll; dismissing cancels it.
    private var pendingEnrollmentPresented: Binding<Bool> {
        Binding(presence: Bindable(model).pendingEnrollment)
    }
}
