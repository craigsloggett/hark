import Foundation

/// Session identity edits: the name and tags in `metadata.json`. Deliberately outside the snapshot
/// undo stack: they are re-editable in place, and the titlebar rename commits through a Binding whose
/// set granularity SwiftUI does not document.
extension LabelingModel {
    func renameSession(_ url: URL, to rawName: String) async {
        guard let summary = library.sessions.first(where: { $0.url == url }) else { return }
        let name = rawName.normalizedName // Empty or whitespace clears back to the date title.
        guard name != summary.name else { return }
        // Committing the shown date text unchanged must not turn the date into a custom name.
        if summary.name == nil, name == summary.dateLabel { return }
        var metadata = summary.metadata
        metadata.name = name
        await saveMetadata(metadata, for: url)
    }

    func addSessionTag(_ raw: String, to url: URL) async {
        guard var metadata = library.sessions.first(where: { $0.url == url })?.metadata,
              metadata.addTag(raw)
        else { return }
        await saveMetadata(metadata, for: url)
    }

    func removeSessionTag(_ tag: String, from url: URL) async {
        guard var metadata = library.sessions.first(where: { $0.url == url })?.metadata else { return }
        metadata.removeTag(tag)
        await saveMetadata(metadata, for: url)
    }

    /// Applies the edit in memory even when the write fails, matching the overlay edits' degrade path.
    private func saveMetadata(_ metadata: SessionMetadata, for url: URL) async {
        await attempt("Save session metadata") { try Session(url: url).writeMetadata(metadata) }
        library.updateMetadata(metadata, for: url)
    }
}
