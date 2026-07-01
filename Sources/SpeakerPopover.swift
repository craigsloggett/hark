import SwiftUI

/// The chip's naming and assignment popover. It reshapes around the speaker's state so each state has
/// a full set of exits: an unidentified voice can be named or matched; a saved voice can be switched,
/// unassigned, or taught; a transcript label can be renamed or cleared. Assigning a voice only labels
/// this transcript, keeping "relabel here" distinct from "teach or enroll the voice".
struct SpeakerPopover: View {
    let token: String
    let model: LabelingModel
    @Binding var isPresented: Bool
    @State private var draft = ""

    var body: some View {
        let binding = model.binding(token: token)
        VStack(alignment: .leading, spacing: 12) {
            header(binding)
            content(for: binding)
        }
        .padding(14)
        .frame(width: 272)
        .onAppear { draft = model.displayName(token: token) ?? "" }
    }

    @ViewBuilder
    private func content(for binding: SpeakerBinding) -> some View {
        switch binding {
        case .unknown:
            nameField(
                title: "Name this voice",
                placeholder: "e.g. Priya, Marcus",
                footnote: "Saves this voice so Hark recognizes it in other recordings."
            ) { await model.nameSpeaker(token: token, to: draft) }
            knownList(title: "Someone you know")
            addNewButton
        case .localLabel:
            nameField(
                title: "Rename in this transcript only",
                placeholder: "Label for this transcript",
                footnote: "Changes only this transcript, not a saved voice."
            ) { await model.renameOverride(token: token, to: draft) }
            actionRow("Clear label", systemImage: "xmark.circle") { await model.clearLabel(token: token) }
            knownList(title: "Someone you know")
            addNewButton
        case .savedVoice:
            savedVoiceActions
            knownList(title: "Switch to someone else")
            addNewButton
        }
    }

    private func header(_ binding: SpeakerBinding) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle().fill(model.color(for: token)).frame(width: 10, height: 10)
                Text(model.displayName(token: token) ?? model.positionalLabel(token: token))
                    .font(.headline)
            }
            Text(subtitle(for: binding))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for binding: SpeakerBinding) -> String {
        switch binding {
        case .unknown:
            "Unidentified speaker"
        case .localLabel:
            "Labeled in this transcript only"
        case .savedVoice:
            savedVoiceSubtitle
        }
    }

    private var savedVoiceSubtitle: String {
        let others = model.otherRecordings(token: token)
        guard others > 0 else { return "Saved voice" }
        return "Saved voice · in \(others) other recording\(others == 1 ? "" : "s")"
    }

    private var savedVoiceActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionRow("Not \(model.displayName(token: token) ?? "this person")", systemImage: "person.fill.xmark") {
                await model.unassign(token: token)
            }
            if model.canEnroll(token: token) {
                actionRow("Teach Hark this voice", systemImage: "waveform.badge.plus") {
                    await model.teachVoice(token: token)
                }
                Text("Adds this clip to the saved voice to sharpen recognition.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    private var addNewButton: some View {
        Button("Add as a new voice") {
            submit { await model.addNewVoice(token: token, name: draft.isEmpty ? nil : draft) }
        }
        .disabled(!model.canEnroll(token: token))
    }

    private func nameField(
        title: String,
        placeholder: String,
        footnote: String,
        _ action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit(action) }
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
