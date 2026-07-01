import SwiftUI

/// A speaker's chip in the chat gutter. Its glyph and border read the voice's state at a glance:
/// dashed `waveform` for an unidentified voice, `tag` for a transcript-only label, `person` for a
/// saved voice. A borderline auto-match reads "Likely <name>" with inline confirm/reject. Hovering
/// reveals it is editable; tapping opens the naming and assignment popover.
struct SpeakerChip: View {
    let token: String
    let model: LabelingModel
    @State private var showsPopover = false
    @State private var hovering = false

    var body: some View {
        let tentative = model.isLikelyMatch(token: token)
        HStack(spacing: 5) {
            chip(tentative: tentative)
            if tentative {
                quickAction(systemImage: "checkmark", tint: .green, help: helpConfirm) {
                    await model.confirmMatch(token: token)
                }
                quickAction(systemImage: "xmark", tint: .red, help: helpReject) {
                    await model.unassign(token: token)
                }
            }
        }
    }

    private func chip(tentative: Bool) -> some View {
        let binding = model.binding(token: token)
        let color = model.color(for: token)
        return Button {
            showsPopover = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tentative ? "person.fill.questionmark" : glyph(for: binding))
                    .imageScale(.small)
                Text(chipLabel(tentative: tentative))
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
        .help(helpText(for: binding, tentative: tentative))
        .onHover { hovering = $0 }
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            SpeakerPopover(token: token, model: model, isPresented: $showsPopover)
        }
    }

    private func quickAction(
        systemImage: String,
        tint: Color,
        help: String,
        _ action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(help)
    }

    private func chipLabel(tentative: Bool) -> String {
        let name = model.displayName(token: token)
        guard tentative, let name else { return name ?? model.positionalLabel(token: token) }
        return "Likely \(name)"
    }

    private var helpConfirm: String {
        "Confirm this is \(model.displayName(token: token) ?? "them")"
    }

    private var helpReject: String {
        "Not \(model.displayName(token: token) ?? "them")"
    }

    private func glyph(for binding: SpeakerBinding) -> String {
        switch binding {
        case .unknown: "waveform"
        case .localLabel: "tag.fill"
        case .savedVoice: "person.fill"
        }
    }

    private func helpText(for binding: SpeakerBinding, tentative: Bool) -> String {
        if tentative {
            return "Likely match. Confirm, reject, or click to change."
        }
        switch binding {
        case .unknown: return "Unidentified speaker. Click to name or assign."
        case .localLabel: return "Labeled for this transcript only. Click to change."
        case .savedVoice:
            let name = model.displayName(token: token)
            return "Saved voice\(name.map { ": \($0)" } ?? ""). Click to change or unassign."
        }
    }
}
