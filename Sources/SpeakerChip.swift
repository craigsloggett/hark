import SwiftUI

/// A speaker's chip in the chat gutter. Its glyph and border read the voice's state at a glance:
/// dashed `waveform` for an unidentified voice, `tag` for a transcript-only label, `person` for a
/// saved voice. Hovering reveals it is editable; tapping opens the naming and assignment popover.
struct SpeakerChip: View {
    let token: String
    let model: LabelingModel
    @State private var showsPopover = false
    @State private var hovering = false

    var body: some View {
        let binding = model.binding(token: token)
        let name = model.displayName(token: token)
        let color = model.color(for: token)
        Button {
            showsPopover = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: glyph(for: binding))
                    .imageScale(.small)
                Text(name ?? model.positionalLabel(token: token))
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(hovering ? 0.7 : 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(hovering ? 0.28 : 0.16), in: Capsule())
            .overlay {
                if case .unknown = binding {
                    Capsule().strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [3]))
                }
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(helpText(for: binding, name: name))
        .onHover { hovering = $0 }
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            SpeakerPopover(token: token, model: model, isPresented: $showsPopover)
        }
    }

    private func glyph(for binding: SpeakerBinding) -> String {
        switch binding {
        case .unknown: "waveform"
        case .localLabel: "tag.fill"
        case .savedVoice: "person.fill"
        }
    }

    private func helpText(for binding: SpeakerBinding, name: String?) -> String {
        switch binding {
        case .unknown: "Unidentified speaker. Click to name or assign."
        case .localLabel: "Labeled for this transcript only. Click to change."
        case .savedVoice: "Saved voice\(name.map { ": \($0)" } ?? ""). Click to change or unassign."
        }
    }
}
