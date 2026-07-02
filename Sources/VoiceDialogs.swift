import SwiftUI

extension Binding<Bool> {
    /// The presence of an optional as a `Bool`, for alerts and dialogs presented by setting an id.
    /// Dismissal (setting `false`) clears the value; setting `true` has nothing to present and is ignored.
    init(presence: Binding<(some Sendable)?>) {
        self.init(
            get: { presence.wrappedValue != nil },
            set: { if !$0 { presence.wrappedValue = nil } }
        )
    }
}

/// The rename, forget, and merge dialogs shared by the People inspector and the People manager, so
/// both surfaces present identical copy and semantics.
extension View {
    func renameVoiceAlert(
        id: Binding<String?>,
        draft: Binding<String>,
        onSave: @escaping (String, String) async -> Void
    ) -> some View {
        alert("Rename Person", isPresented: Binding(presence: id), presenting: id.wrappedValue) { renamingID in
            TextField("Name", text: draft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await onSave(renamingID, draft.wrappedValue) } }
        } message: { _ in
            Text("Renames this person everywhere they appear.")
        }
    }

    func forgetVoiceDialog(id: Binding<String?>, onForget: @escaping (String) async -> Void) -> some View {
        confirmationDialog(
            "Forget this person?",
            isPresented: Binding(presence: id),
            titleVisibility: .visible,
            presenting: id.wrappedValue
        ) { forgettingID in
            Button("Forget", role: .destructive) { Task { await onForget(forgettingID) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Hark stops recognizing their voice. Their turns become unlabeled. You can undo this.")
        }
    }

    func mergeVoicesDialog(isPresented: Binding<Bool>, onMerge: @escaping () async -> Void) -> some View {
        confirmationDialog("Merge these two people?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Merge", role: .destructive) { Task { await onMerge() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They become one person, keeping the named one. You can undo this.")
        }
    }
}
