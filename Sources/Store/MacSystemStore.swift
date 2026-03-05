import Foundation
import Observation

@MainActor
@Observable
final class MacSystemStore {
    var snapshot: MacSystemSnapshot = .empty
    var isRefreshing = false
    var lastUpdatedAt: Date?
    var lastErrorMessage: String?

    private var didStart = false
    private var refreshTask: Task<Void, Never>?

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true

        await refreshNow()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                await self?.refreshNow()
            }
        }
    }

    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        do {
            let collected = try await Task.detached(priority: .utility) {
                try SystemCollector.collect()
            }.value

            snapshot = collected
            lastUpdatedAt = Date()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

}

private enum SystemCollector {
    static func collect() throws -> MacSystemSnapshot {
        let totalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        let availableMemoryBytes = try parseAvailableMemoryBytes(from: run(command: "vm_stat"))
        let usedMemoryBytes = max(0, Int64(totalMemoryBytes) - Int64(availableMemoryBytes))

        let loadAverage = parseLoadAverage(run(command: "sysctl -n vm.loadavg"))
        let uptime = formatUptime(ProcessInfo.processInfo.systemUptime)

        let disk = try diskCapacity()

        return MacSystemSnapshot(
            uptime: uptime,
            loadAverage: loadAverage,
            memoryUsed: formatBytes(usedMemoryBytes),
            memoryTotal: formatBytes(Int64(totalMemoryBytes)),
            diskFree: formatBytes(Int64(disk.free)),
            diskTotal: formatBytes(Int64(disk.total)),
            topProcesses: parseTopProcesses(run(command: "ps -Aceo pid,pcpu,pmem,comm | sort -k2 -nr | head -n 8"))
        )
    }

    private static func run(command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: output, encoding: .utf8) ?? ""
    }

    private static func parseAvailableMemoryBytes(from vmStatOutput: String) throws -> UInt64 {
        let pageSize = UInt64(parseIntMatch(pattern: "page size of ([0-9]+) bytes", in: vmStatOutput) ?? 4096)
        let freePages = UInt64(parseIntMatch(pattern: "Pages free:\\s+([0-9]+)", in: vmStatOutput) ?? 0)
        let speculativePages = UInt64(parseIntMatch(pattern: "Pages speculative:\\s+([0-9]+)", in: vmStatOutput) ?? 0)
        return (freePages + speculativePages) * pageSize
    }

    private static func parseTopProcesses(_ output: String) -> [ProcessEntry] {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .dropFirst()

        return lines.compactMap { line in
            let parts = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 4,
                  let pid = Int(parts[0])
            else {
                return nil
            }

            return ProcessEntry(
                pid: pid,
                cpuPercent: String(parts[1]),
                memoryPercent: String(parts[2]),
                command: String(parts[3])
            )
        }
    }

    private static func parseLoadAverage(_ output: String) -> String {
        let numbers = output
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .split(whereSeparator: \.isWhitespace)
            .prefix(3)
            .map(String.init)

        return numbers.isEmpty ? "-" : numbers.joined(separator: " ")
    }

    private static func formatUptime(_ seconds: TimeInterval) -> String {
        let secondsInt = max(0, Int(seconds))
        let days = secondsInt / 86_400
        let hours = (secondsInt % 86_400) / 3_600
        let minutes = (secondsInt % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private static func diskCapacity() throws -> (free: UInt64, total: UInt64) {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let values = try homeURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])

        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        return (free, total)
    }

    private static func parseIntMatch(pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Int(text[valueRange])
    }

    private static func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}
