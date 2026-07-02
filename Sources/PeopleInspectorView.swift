import SwiftUI

/// The People inspector, in two scopes: who is in this transcript (with stats and merge), and
/// everyone Hark knows across transcripts. Renaming and forgetting live in the rows' context menus.
struct PeopleInspectorView: View {
    private enum Scope {
        case transcript
        case everyone
    }

    @Bindable var model: LabelingModel
    @State private var scope: Scope = .transcript
    @State private var renamingID: String?
    @State private var renameDraft = ""
    @State private var forgettingID: String?
    @State private var confirmingMerge = false
    @Namespace private var scopeThumb

    var body: some View {
        VStack(spacing: 0) {
            scopePicker
            if scope == .transcript {
                transcriptPeople
            } else {
                AllPeopleView(model: model)
            }
        }
        .renameVoiceAlert(id: $renamingID, draft: $renameDraft) { id, name in
            await model.renameVoice(id: id, to: name)
        }
        .forgetVoiceDialog(id: $forgettingID) { await model.forgetVoice(id: $0) }
        .mergeVoicesDialog(isPresented: $confirmingMerge) { await model.mergeSelected() }
    }

    /// Hand-rolled because SwiftUI's segmented picker on macOS always hugs its content: AppKit's
    /// `segmentDistribution = .fillEqually` has no SwiftUI equivalent, so a stock Picker cannot
    /// span the inspector the way the HIG-style switchers in AppKit apps (Xcode, Calendar) do.
    private var scopePicker: some View {
        HStack(spacing: 0) {
            scopeSegment(.transcript, icon: "text.bubble", label: "This Transcript")
            scopeSegment(.everyone, icon: "person.3", label: "Everyone")
        }
        .background(Capsule().fill(.quinary))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func scopeSegment(_ target: Scope, icon: String, label: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                scope = target
            }
        } label: {
            Image(systemName: icon)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(scope == target ? Color.white : .primary)
        .background {
            if scope == target {
                Capsule()
                    .fill(Color.accentColor)
                    .matchedGeometryEffect(id: "thumb", in: scopeThumb)
            }
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(scope == target ? .isSelected : [])
    }

    @ViewBuilder
    private var transcriptPeople: some View {
        if model.detail == nil {
            Text("Select a transcript")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                List(model.rosterTokens, id: \.self, selection: $model.peopleSelection) { token in
                    PersonRow(token: token, model: model)
                        .selectionDisabled(token == Speaker.you.token)
                        .contextMenu { rowMenu(token) }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Button("Merge Selected") {
                        confirmingMerge = true
                    }
                    .disabled(!model.canMerge)
                    Text("Same person shown twice? Select both and merge.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ token: String) -> some View {
        if case let .savedVoice(id) = model.resolver.binding(for: token) {
            Button {
                renameDraft = model.resolver.name(for: token) ?? ""
                renamingID = id
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                forgettingID = id
            } label: {
                Label("Forget…", systemImage: "trash")
            }
        }
    }
}

private struct PersonRow: View {
    let token: String
    let model: LabelingModel

    var body: some View {
        let name = model.resolver.name(for: token)
        let isYou = token == Speaker.you.token
        HStack(spacing: 9) {
            Circle()
                .fill(isYou ? Color.accentColor : model.color(for: token))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? model.positionalLabel(token: token))
                    .foregroundStyle(name == nil && !isYou ? .secondary : .primary)
                Text(subtitle(isYou: isYou))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(isYou: Bool) -> String {
        var parts = [String(count: model.turnCount(token: token), "turn")]
        if let time = model.speakingTime(token: token) {
            parts.append(time)
        }
        let others = isYou ? 0 : model.otherRecordings(token: token)
        if others > 0 {
            parts.append("in \(String(count: others, "other transcript"))")
        }
        return parts.joined(separator: " · ")
    }
}
