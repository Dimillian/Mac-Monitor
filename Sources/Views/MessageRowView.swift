import SwiftUI

struct MessageRowView: View {
    let message: ChatMessage

    private var alignment: HorizontalAlignment {
        switch message.role {
        case .user:
            return .trailing
        case .assistant, .system:
            return .leading
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.18)
        case .assistant:
            return Color.secondary.opacity(0.12)
        case .system:
            return Color.orange.opacity(0.12)
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Agent"
        case .system:
            return "System"
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(roleLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(message.text)
                .textSelection(.enabled)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(bubbleColor)
                )

            if message.isStreaming {
                Text("streaming...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
