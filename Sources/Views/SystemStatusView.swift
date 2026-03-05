import SwiftUI
import Observation

struct SystemStatusView: View {
    @Bindable var conversationStore: ConversationStore
    @Bindable var systemStore: MacSystemStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mac Status")
                    .font(.headline)

                Spacer()

                Button {
                    Task {
                        await systemStore.refreshNow()
                    }
                } label: {
                    if systemStore.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .disabled(systemStore.isRefreshing)
            }

            if let error = systemStore.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    summaryRow("Uptime", systemStore.snapshot.uptime)
                    summaryRow("Load Avg", systemStore.snapshot.loadAverage)
                    summaryRow("Memory", "\(systemStore.snapshot.memoryUsed) / \(systemStore.snapshot.memoryTotal)")
                    summaryRow("Disk Free", "\(systemStore.snapshot.diskFree) / \(systemStore.snapshot.diskTotal)")
                }
            }

            HStack {
                Text("Top Processes")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button("Share Snapshot") {
                    Task {
                        await conversationStore.sendSystemSnapshot(systemStore.snapshot)
                    }
                }
                .buttonStyle(.link)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if systemStore.snapshot.topProcesses.isEmpty {
                        Text("No process data available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(systemStore.snapshot.topProcesses) { process in
                        HStack {
                            Text("PID \(process.pid)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)

                            Text("CPU \(process.cpuPercent)%")
                                .font(.caption2.monospaced())
                                .frame(width: 78, alignment: .leading)

                            Text("MEM \(process.memoryPercent)%")
                                .font(.caption2.monospaced())
                                .frame(width: 78, alignment: .leading)

                            Text(process.command)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}
