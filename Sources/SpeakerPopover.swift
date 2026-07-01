import SwiftUI

/// The chip's naming and assignment popover. Its primary field depends on whether the speaker is
/// already labeled, keeping "relabel this transcript only" distinct from "name or enroll the voice".
struct SpeakerPopover: View {
    let token: String
    let model: LabelingModel
    @Binding var isPresented: Bool
    @State private var draft = ""

    var body: some View {
        let labeled = model.displayName(token: token) != nil
        VStack(alignment: .leading, spacing: 12) {
            header
            nameField(labeled: labeled)

            let known = model.assignableVoiceprints(excluding: token)
            if !known.isEmpty {
                Divider()
                Text("Someone you know")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(known) { voiceprint in
                        knownRow(voiceprint)
                    }
                }
            }

            Button("Add as a new voice") {
                submit { await model.addNewVoice(token: token, name: draft.isEmpty ? nil : draft) }
            }
            .disabled(!model.canEnroll(token: token))
        }
        .padding(14)
        .frame(width: 264)
        .onAppear { draft = model.displayName(token: token) ?? "" }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(model.color(for: token)).frame(width: 10, height: 10)
            Text(model.displayName(token: token) ?? model.positionalLabel(token: token))
                .font(.headline)
        }
    }

    private func nameField(labeled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(labeled ? "Rename in this transcript only" : "Name this voice")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(labeled ? "Label for this transcript" : "e.g. Priya, Marcus", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submit {
                        if labeled {
                            await model.renameOverride(token: token, to: draft)
                        } else {
                            await model.nameSpeaker(token: token, to: draft)
                        }
                    }
                }
            Text(labeled
                ? "Changes only this transcript, not the saved voice."
                : "Saves this voice so Hark recognises it in other recordings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
