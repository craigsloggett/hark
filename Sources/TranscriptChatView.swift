import SwiftUI

/// The selected transcript as an iMessage-style chat: "You" on the trailing side, remote speakers
/// leading with a tappable chip above each run of turns.
struct TranscriptChatView: View {
    let model: LabelingModel

    var body: some View {
        Group {
            if model.detail == nil {
                ContentUnavailableView("Select a recording", systemImage: "text.bubble")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.turnGroups) { group in
                            TurnGroupView(group: group, model: model)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Transcript")
        .navigationSubtitle(model.detail == nil ? "" : model.currentTitle)
    }
}

private struct TurnGroupView: View {
    let group: TurnGroup
    let model: LabelingModel

    private var isYou: Bool {
        group.speaker == .you
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isYou { Spacer(minLength: 64) }
            VStack(alignment: isYou ? .trailing : .leading, spacing: 4) {
                if !isYou {
                    SpeakerChip(token: group.token, model: model)
                }
                ForEach(Array(group.segments.enumerated()), id: \.offset) { _, segment in
                    bubble(segment.text)
                }
            }
            if !isYou { Spacer(minLength: 64) }
        }
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .textSelection(.enabled)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                isYou ? Color.accentColor : Color.gray.opacity(0.22),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(isYou ? Color.white : Color.primary)
            .frame(maxWidth: 460, alignment: isYou ? .trailing : .leading)
    }
}
