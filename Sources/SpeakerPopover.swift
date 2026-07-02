import SwiftUI

/// The chip's naming popover, reduced to name-or-confirm: one Name field that routes through
/// `nameSpeaker` (which renames, saves a new person, or falls back to a transcript label, so the user
/// never picks a storage tier), a yes/no pair for a tentative match, and the list of known people to
/// reassign to. Recognition upkeep (teaching, enrolling) happens implicitly behind those answers.
struct SpeakerPopover: View {
    let token: String
    let model: LabelingModel
    @Binding var isPresented: Bool
    @State private var draft = ""

    var body: some View {
        let binding = model.resolver.binding(for: token)
        let tentative = model.resolver.isLikelyMatch(for: token)
        VStack(alignment: .leading, spacing: 12) {
            header(binding, tentative: tentative)
            content(for: binding, tentative: tentative)
        }
        .padding(14)
        .frame(width: 272)
        .onAppear { draft = model.resolver.name(for: token) ?? "" }
    }

    @ViewBuilder
    private func content(for binding: SpeakerBinding, tentative: Bool) -> some View {
        switch binding {
        case .unknown:
            nameField
            knownList(title: "Someone you know")
        case .localLabel:
            nameField
            actionRow("Clear name", systemImage: "xmark.circle") { await model.clearLabel(token: token) }
            knownList(title: "Someone you know")
        case .savedVoice:
            if model.resolver.name(for: token) == nil {
                // Recognized but unnamed: name the known person in place, so the user isn't pushed to
                // fork this speaker into a duplicate identity.
                nameField
            }
            savedVoiceActions(tentative: tentative)
            knownList(title: "Switch to someone else")
        }
    }

    private func header(_ binding: SpeakerBinding, tentative: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle().fill(model.color(for: token)).frame(width: 10, height: 10)
                Text(model.resolver.name(for: token) ?? model.positionalLabel(token: token))
                    .font(.headline)
            }
            Text(subtitle(for: binding, tentative: tentative))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for binding: SpeakerBinding, tentative: Bool) -> String {
        switch binding {
        case .unknown:
            "Unidentified speaker"
        case .localLabel:
            "Named in this transcript only"
        case .savedVoice:
            savedVoiceSubtitle(tentative: tentative)
        }
    }

    private func savedVoiceSubtitle(tentative: Bool) -> String {
        let base = if tentative {
            "Possible match"
        } else if model.resolver.name(for: token) == nil {
            "Recognized, not yet named"
        } else {
            "Someone Hark knows"
        }
        let others = model.otherRecordings(token: token)
        guard others > 0 else { return base }
        return "\(base) · in \(String(count: others, "other transcript"))"
    }

    private func savedVoiceActions(tentative: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if tentative {
                actionRow("Yes, it's \(model.resolver.name(for: token) ?? "them")", systemImage: "checkmark.circle") {
                    await model.confirmMatch(token: token)
                }
            }
            actionRow("Not \(model.resolver.name(for: token) ?? "this person")", systemImage: "person.fill.xmark") {
                await model.unassign(token: token)
            }
        }
    }

    @ViewBuilder
    private func knownList(title: String) -> some View {
        let known = model.assignableVoiceprints(excluding: token)
        if !known.isEmpty {
            Divider()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                ForEach(known) { voiceprint in
                    knownRow(voiceprint)
                }
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. Priya, Marcus", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit { await model.nameSpeaker(token: token, to: draft) } }
            Text(nameFootnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// One sentence on where the name lands, so expectations are set without explaining machinery.
    private var nameFootnote: String {
        if case .savedVoice = model.resolver.binding(for: token) {
            return "Hark knows this voice. The name applies everywhere it appears."
        }
        if model.canEnroll(token: token) {
            return "Hark will recognize them in future recordings."
        }
        return "Names them in this transcript only."
    }

    private func actionRow(
        _ title: String,
        systemImage: String,
        _ action: @escaping () async -> Void
    ) -> some View {
        Button {
            submit(action)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func knownRow(_ voiceprint: Voiceprint) -> some View {
        Button {
            submit { await model.rebind(token: token, toVoiceprint: voiceprint.id) }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color.speaker(for: voiceprint.id)).frame(width: 8, height: 8)
                Text(voiceprint.name ?? "Unnamed")
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submit(_ action: @escaping () async -> Void) {
        Task {
            await action()
            isPresented = false
        }
    }
}
