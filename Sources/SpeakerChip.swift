import SwiftUI

/// A speaker's chip in the chat gutter: dashed when the voice is unlabeled (editable), solid once
/// named. Tapping opens the naming and assignment popover.
struct SpeakerChip: View {
    let token: String
    let model: LabelingModel
    @State private var showsPopover = false

    var body: some View {
        let name = model.displayName(token: token)
        let color = model.color(for: token)
        Button {
            showsPopover = true
        } label: {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name ?? model.positionalLabel(token: token))
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .overlay {
                if name == nil {
                    Capsule().strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [3]))
                }
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            SpeakerPopover(token: token, model: model, isPresented: $showsPopover)
        }
    }
}
