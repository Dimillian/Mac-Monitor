import AppKit
import SwiftUI
import Observation

struct MenuBarConversationView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case agent
        case system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .agent: return "Agent"
            case .system: return "System"
            }
        }
    }

    @Bindable var conversationStore: ConversationStore
    @Bindable var systemStore: MacSystemStore

    @State private var selectedTab: Tab = .agent

    private var lastMessageScrollKey: String {
        guard let last = conversationStore.messages.last else {
            return "empty"
        }

        return "\(last.id)-\(last.text.count)-\(last.isStreaming)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Picker("Panel", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if selectedTab == .agent {
                agentPanel
            } else {
                SystemStatusView(
                    conversationStore: conversationStore,
                    systemStore: systemStore
                )
            }

            Divider()

            footer
        }
        .padding(12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("MacMonitor")
                    .font(.headline)

                Spacer()

                Text("Status: \(conversationStore.connectionLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let threadID = conversationStore.threadID {
                    Text("Thread: \(threadID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Thread: (not ready)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if conversationStore.isTurnInProgress {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Instr: \(conversationStore.instructionsSourceSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var agentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = conversationStore.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if conversationStore.hasPendingApprovals {
                approvalsSection
            }

            messageList
            composer
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(conversationStore.messages) { message in
                        MessageRowView(message: message)
                            .id(message.id)
                    }
                }
            }
            .onChange(of: conversationStore.messages.count) {
                guard let lastID = conversationStore.messages.last?.id else {
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: lastMessageScrollKey) {
                guard let lastID = conversationStore.messages.last?.id else {
                    return
                }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private var approvalsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Approvals")
                .font(.subheadline.weight(.semibold))

            ForEach(conversationStore.pendingApprovals) { approval in
                VStack(alignment: .leading, spacing: 4) {
                    Text(approval.kind == .commandExecution ? "Command request" : "File change request")
                        .font(.caption.weight(.semibold))

                    if let command = approval.command {
                        Text(command)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }

                    if let cwd = approval.cwd {
                        Text("cwd: \(cwd)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let reason = approval.reason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Approve") {
                            Task {
                                await conversationStore.respondToApproval(approval, accept: true)
                            }
                        }

                        Button("Decline") {
                            Task {
                                await conversationStore.respondToApproval(approval, accept: false)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask MacMonitor to inspect or act...", text: $conversationStore.draftText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task {
                        await conversationStore.sendCurrentDraft()
                    }
                }

            Button("Send") {
                Task {
                    await conversationStore.sendCurrentDraft()
                }
            }
            .disabled(!conversationStore.canSend)

            if conversationStore.isSending {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Reconnect") {
                Task {
                    await conversationStore.reconnect()
                }
            }

            Button("New Thread") {
                Task {
                    await conversationStore.startNewThread()
                }
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
