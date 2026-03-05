import Foundation
import Observation

@MainActor
@Observable
final class ConversationStore {
    private enum ConnectionStatus {
        case idle
        case connecting
        case connected
        case disconnected
        case failed

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            case .disconnected: return "Disconnected"
            case .failed: return "Failed"
            }
        }
    }

    private let threadIDDefaultsKey = "macmonitor.thread.id"
    private let workingDirectoryDefaultsKey = "macmonitor.workingDirectory"
    private let workingDirectory: String
    private let bundledAgentsFilePath: String?
    private let bundledAgentsInstructions: String?
    private var connectionStatus: ConnectionStatus = .idle
    private var didStart = false
    private var streamingMessageIDByItemID: [String: String] = [:]
    private var pendingThinkingMessageID: String?

    private var session: CodexAppServerSession?

    var messages: [ChatMessage] = [
        ChatMessage(
            role: .system,
            text: "MacMonitor is ready. Ask for diagnostics, process checks, or admin guidance."
        )
    ]
    var pendingApprovals: [PendingApproval] = []

    var threadID: String?
    var activeTurnID: String?
    var draftText = ""
    var isSending = false
    var isTurnInProgress = false
    var lastErrorMessage: String?

    init(workingDirectory: String? = nil) {
        let resolvedWorkingDirectory = Self.resolveWorkingDirectory(preferred: workingDirectory)
        let bundledAgents = Self.loadBundledAgentsInstructions()
        self.workingDirectory = resolvedWorkingDirectory
        self.bundledAgentsFilePath = bundledAgents.path
        self.bundledAgentsInstructions = bundledAgents.content

        UserDefaults.standard.set(self.workingDirectory, forKey: workingDirectoryDefaultsKey)
    }

    var connectionLabel: String {
        connectionStatus.label
    }

    var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTurnInProgress && !isSending
    }

    var hasPendingApprovals: Bool {
        !pendingApprovals.isEmpty
    }

    var instructionsSourceSummary: String {
        if bundledAgentsInstructions != nil {
            if let bundledAgentsFilePath {
                return "Bundle (\(bundledAgentsFilePath))"
            }
            return "Bundle AGENTS.md"
        }

        return "AGENTS.md not found"
    }

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        await connect()
    }

    func reconnect() async {
        stopSession()
        await connect()
    }

    func stopSession() {
        guard let session else {
            return
        }

        Task {
            await session.stop()
        }
        self.session = nil
        connectionStatus = .disconnected
    }

    func startNewThread() async {
        guard let session else { return }

        do {
            let threadID = try await session.startThread(
                cwd: workingDirectory,
                developerInstructions: developerInstructions
            )
            applyThreadID(threadID)
            activeTurnID = nil
            pendingApprovals.removeAll()
            streamingMessageIDByItemID.removeAll()
            appendSystemMessage("Started new MacMonitor thread.")
        } catch {
            handleError("Failed to start new thread: \(error.localizedDescription)")
        }
    }

    func sendCurrentDraft() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftText = ""
        await send(text: text)
    }

    func sendSystemSnapshot(_ snapshot: MacSystemSnapshot) async {
        await send(text: snapshot.promptSummary)
    }

    func respondToApproval(_ approval: PendingApproval, accept: Bool) async {
        guard let session else { return }

        do {
            switch approval.kind {
            case .commandExecution:
                try await session.respondToCommandApproval(requestID: approval.requestID, accept: accept)
            case .fileChange:
                try await session.respondToFileChangeApproval(requestID: approval.requestID, accept: accept)
            }

            pendingApprovals.removeAll(where: { $0.id == approval.id })
            let decision = accept ? "approved" : "declined"
            appendSystemMessage("\(approval.kind.rawValue) request \(decision).")
        } catch {
            handleError("Failed to respond to approval: \(error.localizedDescription)")
        }
    }

    private var developerInstructions: String? {
        return bundledAgentsInstructions
    }

    private func connect() async {
        connectionStatus = .connecting
        lastErrorMessage = nil

        let session = CodexAppServerSession { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleAppServerEvent(event)
            }
        }

        self.session = session

        do {
            try await session.start()
            connectionStatus = .connected
            if bundledAgentsInstructions != nil {
                if let bundledAgentsFilePath {
                    appendSystemMessage("Loaded bundled instructions from \(bundledAgentsFilePath).")
                } else {
                    appendSystemMessage("Loaded bundled instructions.")
                }
            } else {
                appendSystemMessage("No AGENTS.md found. Running without custom developer instructions.")
            }
            try await ensureThread(on: session)
        } catch {
            handleError(error.localizedDescription)
        }
    }

    private func ensureThread(on session: CodexAppServerSession) async throws {
        if let savedThreadID = UserDefaults.standard.string(forKey: threadIDDefaultsKey), !savedThreadID.isEmpty {
            do {
                try await session.resumeThread(threadID: savedThreadID)
                applyThreadID(savedThreadID)
                appendSystemMessage("Resumed thread \(savedThreadID).")
                return
            } catch {
                appendSystemMessage("Could not resume previous thread. Starting a new one.")
            }
        }

        let createdThreadID = try await session.startThread(
            cwd: workingDirectory,
            developerInstructions: developerInstructions
        )
        applyThreadID(createdThreadID)
        appendSystemMessage("Started thread \(createdThreadID).")
    }

    private func send(text: String) async {
        guard let session else {
            handleError("Not connected to codex app-server.")
            return
        }

        guard let threadID else {
            handleError("No active thread is available.")
            return
        }

        messages.append(ChatMessage(role: .user, text: text))
        isSending = true
        isTurnInProgress = true
        showThinkingPlaceholderIfNeeded()

        do {
            try await session.startTurn(threadID: threadID, text: text)
            isSending = false
        } catch {
            isSending = false
            isTurnInProgress = false
            clearThinkingPlaceholder()
            handleError("Failed to send turn: \(error.localizedDescription)")
        }
    }

    private func handleAppServerEvent(_ event: AppServerEvent) {
        switch event {
        case .connected:
            connectionStatus = .connected

        case .disconnected(let message):
            connectionStatus = .disconnected
            if !message.isEmpty {
                appendSystemMessage(message)
            }

        case .threadStarted(let threadID):
            applyThreadID(threadID)

        case .turnStarted(let turnID):
            activeTurnID = turnID
            isTurnInProgress = true

        case .turnCompleted(let turnID, let status, let errorMessage):
            if activeTurnID == turnID {
                activeTurnID = nil
            }
            isTurnInProgress = false
            clearThinkingPlaceholder()

            if status == "failed", let errorMessage {
                handleError(errorMessage)
            } else if status == "interrupted" {
                appendSystemMessage("Turn interrupted.")
            }

        case .agentMessageDelta(let itemID, let delta):
            appendAssistantDelta(itemID: itemID, delta: delta)

        case .agentMessageCompleted(let itemID, let text):
            finalizeAssistantMessage(itemID: itemID, text: text)

        case .commandApprovalRequest(let requestID, let itemID, let command, let cwd, let reason):
            pendingApprovals.append(
                PendingApproval(
                    requestID: requestID,
                    kind: .commandExecution,
                    itemID: itemID,
                    command: command,
                    cwd: cwd,
                    reason: reason
                )
            )

        case .fileChangeApprovalRequest(let requestID, let itemID, let reason):
            pendingApprovals.append(
                PendingApproval(
                    requestID: requestID,
                    kind: .fileChange,
                    itemID: itemID,
                    reason: reason
                )
            )

        case .toolUserInputRequest(let requestID, let questionIDs):
            Task {
                guard let session else { return }

                do {
                    let emptyAnswers = Dictionary(uniqueKeysWithValues: questionIDs.map { ($0, "") })
                    try await session.respondToToolUserInput(requestID: requestID, answersByQuestionID: emptyAnswers)
                    appendSystemMessage("Tool asked for user input; submitted blank answers (MVP behavior).")
                } catch {
                    handleError("Failed to answer tool user-input request: \(error.localizedDescription)")
                }
            }

        case .turnError(let message):
            handleError(message)
        }
    }

    private func appendAssistantDelta(itemID: String, delta: String) {
        if let pendingThinkingMessageID,
           let index = messages.firstIndex(where: { $0.id == pendingThinkingMessageID }) {
            messages[index].text = delta
            messages[index].isStreaming = true
            streamingMessageIDByItemID[itemID] = pendingThinkingMessageID
            self.pendingThinkingMessageID = nil
            return
        }

        if let messageID = streamingMessageIDByItemID[itemID],
           let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].text += delta
            return
        }

        let newMessage = ChatMessage(
            id: "assistant-\(itemID)",
            role: .assistant,
            text: delta,
            isStreaming: true
        )

        streamingMessageIDByItemID[itemID] = newMessage.id
        messages.append(newMessage)
    }

    private func finalizeAssistantMessage(itemID: String, text: String) {
        if let pendingThinkingMessageID,
           let index = messages.firstIndex(where: { $0.id == pendingThinkingMessageID }) {
            messages[index].text = text
            messages[index].isStreaming = false
            streamingMessageIDByItemID[itemID] = pendingThinkingMessageID
            self.pendingThinkingMessageID = nil
            return
        }

        if let messageID = streamingMessageIDByItemID[itemID],
           let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].text = text
            messages[index].isStreaming = false
            streamingMessageIDByItemID.removeValue(forKey: itemID)
            return
        }

        messages.append(ChatMessage(role: .assistant, text: text, isStreaming: false))
    }

    private func appendSystemMessage(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        messages.append(ChatMessage(role: .system, text: cleanText))
    }

    private func applyThreadID(_ threadID: String) {
        self.threadID = threadID
        UserDefaults.standard.set(threadID, forKey: threadIDDefaultsKey)
    }

    private func handleError(_ message: String) {
        connectionStatus = .failed
        lastErrorMessage = message
        clearThinkingPlaceholder()
        appendSystemMessage("Error: \(message)")
    }

    private func showThinkingPlaceholderIfNeeded() {
        guard pendingThinkingMessageID == nil else {
            return
        }

        let placeholder = ChatMessage(
            id: "assistant-thinking-\(UUID().uuidString)",
            role: .assistant,
            text: "Thinking...",
            isStreaming: true
        )
        pendingThinkingMessageID = placeholder.id
        messages.append(placeholder)
    }

    private func clearThinkingPlaceholder() {
        guard let pendingThinkingMessageID else {
            return
        }

        messages.removeAll(where: { $0.id == pendingThinkingMessageID })
        self.pendingThinkingMessageID = nil
    }

    private static func resolveWorkingDirectory(preferred: String?) -> String {
        let fileManager = FileManager.default
        var candidates: [String] = []

        if let preferred, !preferred.isEmpty {
            candidates.append(preferred)
        }

        if let envPath = ProcessInfo.processInfo.environment["MACMONITOR_WORKDIR"], !envPath.isEmpty {
            candidates.append(envPath)
        }

        if let saved = UserDefaults.standard.string(forKey: "macmonitor.workingDirectory"), !saved.isEmpty {
            candidates.append(saved)
        }

        candidates.append(FileManager.default.currentDirectoryPath)
        candidates.append(NSHomeDirectory() + "/Documents/Dev/MacMonitor")

        var seen = Set<String>()
        var normalized: [String] = []
        for candidate in candidates where !candidate.isEmpty {
            let path = URL(fileURLWithPath: candidate).standardizedFileURL.path
            if seen.insert(path).inserted {
                normalized.append(path)
            }
        }

        for candidate in normalized where fileManager.fileExists(atPath: candidate) {
            return candidate
        }

        return FileManager.default.currentDirectoryPath
    }

    private static func loadBundledAgentsInstructions() -> (path: String?, content: String?) {
        guard let bundledURL = Bundle.main.url(forResource: "AGENTS", withExtension: "md"),
              let content = try? String(contentsOf: bundledURL, encoding: .utf8)
        else {
            return (nil, nil)
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (bundledURL.path, nil)
        }

        return (bundledURL.path, trimmed)
    }
}
