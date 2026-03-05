import Foundation

enum ChatRole: String, Sendable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: String
    let role: ChatRole
    var text: String
    let createdAt: Date
    var isStreaming: Bool

    init(
        id: String = UUID().uuidString,
        role: ChatRole,
        text: String,
        createdAt: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isStreaming = isStreaming
    }
}

enum ApprovalKind: String, Sendable {
    case commandExecution
    case fileChange
}

struct PendingApproval: Identifiable, Equatable, Sendable {
    let id: String
    let requestID: Int
    let kind: ApprovalKind
    let itemID: String
    let command: String?
    let cwd: String?
    let reason: String?

    init(
        requestID: Int,
        kind: ApprovalKind,
        itemID: String,
        command: String? = nil,
        cwd: String? = nil,
        reason: String? = nil
    ) {
        self.id = "approval-\(requestID)"
        self.requestID = requestID
        self.kind = kind
        self.itemID = itemID
        self.command = command
        self.cwd = cwd
        self.reason = reason
    }
}

struct ProcessEntry: Identifiable, Equatable, Sendable {
    var id: String { "\(pid)-\(command)" }

    let pid: Int
    let cpuPercent: String
    let memoryPercent: String
    let command: String
}

struct MacSystemSnapshot: Equatable, Sendable {
    let uptime: String
    let loadAverage: String
    let memoryUsed: String
    let memoryTotal: String
    let diskFree: String
    let diskTotal: String
    let topProcesses: [ProcessEntry]

    static let empty = MacSystemSnapshot(
        uptime: "-",
        loadAverage: "-",
        memoryUsed: "-",
        memoryTotal: "-",
        diskFree: "-",
        diskTotal: "-",
        topProcesses: []
    )

    var promptSummary: String {
        let processSummary = topProcesses
            .prefix(5)
            .map { "PID \($0.pid) CPU \($0.cpuPercent)% MEM \($0.memoryPercent)% \($0.command)" }
            .joined(separator: "\n")

        return """
        Mac status snapshot:
        - Uptime: \(uptime)
        - Load average: \(loadAverage)
        - Memory: \(memoryUsed) / \(memoryTotal)
        - Disk free: \(diskFree) / \(diskTotal)
        - Top processes:
        \(processSummary.isEmpty ? "(no data)" : processSummary)
        """
    }
}
