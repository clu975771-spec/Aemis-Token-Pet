import Foundation
import SQLite3

enum CodexTaskAlertKind: String { case complete, problem }

struct CodexTaskAlert {
    let key: String
    let threadID: String
    let kind: CodexTaskAlertKind
    let reason: String
    let title: String
    let project: String
    let timestamp: TimeInterval
}

struct CodexTaskAlertSettings {
    var completionEnabled: Bool
    var problemEnabled: Bool
    var quietEnabled: Bool = false
    var quietStartHour: Int
    var quietEndHour: Int
    var volume: Float
    var repeatMinutes: Int

    static func load(defaults d: UserDefaults = .standard) -> Self {
        return .init(completionEnabled: d.object(forKey: "taskCompletionAlertEnabled") == nil ? true : d.bool(forKey: "taskCompletionAlertEnabled"),
                     problemEnabled: d.object(forKey: "taskProblemAlertEnabled") == nil ? true : d.bool(forKey: "taskProblemAlertEnabled"),
                     quietEnabled: d.bool(forKey: "taskQuietHoursEnabled"),
                     quietStartHour: d.object(forKey: "taskQuietStartHour") == nil ? 23 : d.integer(forKey: "taskQuietStartHour"),
                     quietEndHour: d.object(forKey: "taskQuietEndHour") == nil ? 8 : d.integer(forKey: "taskQuietEndHour"),
                     volume: d.object(forKey: "taskAlertVolume") == nil ? 1.0 : max(0, min(2, d.float(forKey: "taskAlertVolume"))),
                     repeatMinutes: 0)
    }

    func save(defaults d: UserDefaults = .standard) {
        d.set(completionEnabled, forKey: "taskCompletionAlertEnabled")
        d.set(problemEnabled, forKey: "taskProblemAlertEnabled")
        d.set(quietEnabled, forKey: "taskQuietHoursEnabled")
        d.set(max(0, min(23, quietStartHour)), forKey: "taskQuietStartHour")
        d.set(max(0, min(23, quietEndHour)), forKey: "taskQuietEndHour")
        d.set(max(0, min(2, volume)), forKey: "taskAlertVolume")
        d.set(0, forKey: "taskAlertRepeatMinutes")
    }

    func isQuiet(at date: Date = Date()) -> Bool {
        guard quietEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if quietStartHour == quietEndHour { return false }
        if quietStartHour < quietEndHour { return hour >= quietStartHour && hour < quietEndHour }
        return hour >= quietStartHour || hour < quietEndHour
    }
}

private final class ReadOnlySQLite {
    private var database: OpaquePointer?
    init(_ path: String) {
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(database); database = nil; return
        }
        sqlite3_busy_timeout(database, 200)
    }
    deinit { sqlite3_close(database) }
    func rows(_ sql: String) -> [[String]] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append((0..<sqlite3_column_count(statement)).map { index in
                guard let value = sqlite3_column_text(statement, index) else { return "" }
                return String(cString: value)
            })
        }
        return result
    }
}

/// Local records distinguish explicit goal completion, a finished final reply,
/// and new actionable problems. Intermediate messages are never completion.
final class CodexTaskMonitor {
    private let root: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "CodexTaskMonitor", qos: .utility)
    private let launchedAt: TimeInterval
    private var lastPollAt: TimeInterval
    private var delivered: [String: TimeInterval]
    private var completionCache: [String: (size: UInt64, events: [String])] = [:]
    var onAlert: ((CodexTaskAlert) -> Void)?

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"), defaults: UserDefaults = .standard, startedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.launchedAt = startedAt
        self.lastPollAt = startedAt
        self.root = root
        self.defaults = defaults
        self.delivered = defaults.dictionary(forKey: "taskAlertDelivered") as? [String: TimeInterval] ?? [:]
        // Retain old delivered keys; disabling repeats must never replay them.
        defaults.set(0, forKey: "taskAlertRepeatMinutes")
    }

    func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let alerts = self.collectAlerts()
            for alert in alerts {
                DispatchQueue.main.async { [weak self] in self?.onAlert?(alert) }
            }
        }
    }

    /// Called on the monitor queue; also used by isolated fixtures without UI/audio.
    func collectAlerts(now: TimeInterval = Date().timeIntervalSince1970) -> [CodexTaskAlert] {
        let candidates = readCandidates(now: now)
        let settings = CodexTaskAlertSettings.load(defaults: defaults)
        // A long polling gap means sleep/suspension. Baseline it silently instead
        // of replaying failures that accumulated while the pet was unavailable.
        let resumedAfterGap = now - lastPollAt > 90
        lastPollAt = now
        var output: [CodexTaskAlert] = []
        for alert in candidates.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard delivered[alert.key] == nil else { continue }
            let legacyAlreadyDelivered = alert.kind == .complete && delivered.keys.contains { key in
                let prefixes = ["goal:\(alert.threadID):complete:", "complete:\(alert.threadID):"]
                return prefixes.contains { prefix in
                    guard key.hasPrefix(prefix), let ms = Double(key.dropFirst(prefix.count)) else { return false }
                    return abs(ms / 1000 - alert.timestamp) < 1
                }
            }
            // Consume disabled and stale events too, so toggling alerts cannot
            // resurrect an already observed failure. Persist before callbacks.
            delivered[alert.key] = now
            guard !legacyAlreadyDelivered, !resumedAfterGap, alert.timestamp > launchedAt,
                  alert.timestamp <= now, now - alert.timestamp <= 90 else { continue }
            let enabled = alert.kind == .complete ? settings.completionEnabled : settings.problemEnabled
            if enabled { output.append(alert) }
        }
        defaults.set(delivered, forKey: "taskAlertDelivered")
        return output
    }

    /// Revalidate queued bubbles immediately before presentation.
    func isActionable(_ alert: CodexTaskAlert) -> Bool {
        queue.sync {
            let settings = CodexTaskAlertSettings.load(defaults: defaults)
            guard alert.kind == .complete ? settings.completionEnabled : settings.problemEnabled,
                  Date().timeIntervalSince1970 - alert.timestamp <= 90 else { return false }
            // A valid completed event stays valid when the next turn starts or
            // its goal row disappears while waiting behind another bubble.
            if alert.kind == .complete { return true }
            return readCandidates(now: Date().timeIntervalSince1970).contains { $0.key == alert.key }
        }
    }

    private func readCandidates(now: TimeInterval) -> [CodexTaskAlert] {
        let state = ReadOnlySQLite(root.appendingPathComponent("state_5.sqlite").path)
        let goals = ReadOnlySQLite(root.appendingPathComponent("goals_1.sqlite").path)
        let history = ReadOnlySQLite(root.appendingPathComponent("thread_history_1.sqlite").path)
        let since = Int((now - 7 * 24 * 3600) * 1000)
        let metadata = Dictionary( state.rows("SELECT t.id, t.title, COALESCE(p.name, '') FROM threads t LEFT JOIN projects p ON p.id=t.project_id").compactMap { row -> (String, (String, String))? in
            guard row.count == 3 else { return nil }
            return (row[0], (row[1], row[2]))
        }, uniquingKeysWith: { first, _ in first })
        let latestTurns = Dictionary( history.rows("SELECT thread_id,turn_id,started_at,COALESCE(completed_at,0),status FROM (SELECT *,ROW_NUMBER() OVER (PARTITION BY thread_id ORDER BY COALESCE(started_at,0) DESC,rollout_ordinal DESC,turn_id DESC) AS latest_rank FROM thread_turns) WHERE latest_rank=1").compactMap { row -> (String, [String])? in
            row.count == 5 ? (row[0], row) : nil
        }, uniquingKeysWith: { first, _ in first })
        let latestReplies = Dictionary( history.rows("SELECT thread_id,MAX(created_at_ms) FROM thread_items WHERE item_type='userMessage' GROUP BY thread_id").compactMap { row -> (String, Double)? in
            guard row.count == 2, let ms = Double(row[1]) else { return nil }
            return (row[0], ms / 1000)
        }, uniquingKeysWith: max)
        let goalStates = Dictionary( goals.rows("SELECT thread_id,status,updated_at_ms FROM thread_goals").compactMap { row -> (String, [String])? in
            row.count == 3 ? (row[0], row) : nil
        }, uniquingKeysWith: { a, b in (Double(a[2]) ?? 0) >= (Double(b[2]) ?? 0) ? a : b })
        let completionTurns = history.rows("SELECT thread_id,turn_id,started_at,COALESCE(completed_at,0) FROM thread_turns WHERE started_at*1000 >= \(since) ORDER BY started_at DESC,rollout_ordinal DESC")
        func make(_ key: String, _ id: String, _ kind: CodexTaskAlertKind, _ reason: String, _ milliseconds: String) -> CodexTaskAlert? {
            guard let (title, project) = metadata[id], let timestamp = Double(milliseconds) else { return nil }
            var eventKey = key
            if kind == .complete, !key.hasPrefix("complete-turn:") {
                // Database milliseconds and rollout seconds describe one event.
                // Where possible share its turn identity with the final reply.
                if let turn = completionTurns.first(where: { row in
                    guard row.count == 4, row[0] == id, let started = Double(row[2]), started <= timestamp / 1000 else { return false }
                    return (Double(row[3]) ?? 0) == 0 || (Double(row[3]) ?? 0) + 1 >= timestamp / 1000
                }) {
                    eventKey = "complete-turn:\(id):\(turn[1])"
                } else {
                    eventKey = "complete-event:\(id):\(Int(timestamp / 1000))"
                }
            }
            if kind == .problem {
                let seconds = timestamp / 1000
                if let goal = goalStates[id], ["active", "paused", "complete"].contains(goal[1]),
                   (Double(goal[2]) ?? 0) >= timestamp { return nil }
                guard let turn = latestTurns[id], let started = Double(turn[2]), started <= seconds,
                      (latestReplies[id] ?? 0) <= seconds else { return nil }
                // A historical goal update without an associated current turn is
                // not a live problem. Completion timestamps have second precision.
                let ended = Double(turn[3]) ?? 0
                guard ended == 0 || ended + 1 >= seconds else { return nil }
                eventKey = "problem-turn:\(id):\(turn[1])"
            }
            return .init(key: eventKey, threadID: id, kind: kind, reason: reason,
                         title: title.isEmpty ? "Codex 任务" : title, project: project,
                         timestamp: timestamp / 1000)
        }
        var alerts: [CodexTaskAlert] = []
        if ProcessInfo.processInfo.environment["AEMIS_DEBUG_TASK_MONITOR"] == "1" { fputs("monitor metadata=\(metadata.keys.sorted()) since=\(since)\n", stderr) }
        for row in goals.rows("SELECT thread_id, status, updated_at_ms FROM thread_goals WHERE status IN ('complete','blocked','usage_limited','budget_limited') AND updated_at_ms >= \(since)") where row.count == 3 {
            let kind: CodexTaskAlertKind = row[1] == "complete" ? .complete : .problem
            let reason = row[1] == "blocked" ? "目标受阻，需要处理" : row[1] == "complete" ? "目标已明确标记完成" : "任务暂受额度限制"
            if let alert = make("goal:\(row[0]):\(row[1]):\(row[2])", row[0], kind, reason, row[2]) { alerts.append(alert) }
        }
        // Completed goals are removed from goals_1.sqlite by Codex. The actual
        // update_goal result remains in the thread rollout; inspect only the
        // recent tail of recently updated local threads for that explicit event.
        let rolloutSince = Int((now - 10 * 60) * 1000)
        let recentRollouts = state.rows("SELECT id, rollout_path FROM threads WHERE updated_at_ms >= \(rolloutSince) ORDER BY updated_at_ms DESC LIMIT 20")
        for row in recentRollouts where row.count == 2 {
            for completion in completionEvents(threadID: row[0], rolloutPath: row[1]) {
                if let alert = make("complete:\(row[0]):\(completion)", row[0], .complete, "目标已明确标记完成", completion) { alerts.append(alert) }
            }
        }
        // Ordinary chats normally have no explicit Goal. A completed turn must
        // point at a real, nonempty final answer (not commentary/tool output or
        // an unanswered question). An active/blocked goal can continue after a
        // final answer, so do not call that intermediate step a completion.
        let finalRows = history.rows("SELECT t.thread_id,t.turn_id,CAST(t.completed_at*1000 AS TEXT) FROM thread_turns t JOIN thread_items i ON i.thread_id=t.thread_id AND i.turn_id=t.turn_id AND i.item_id=t.final_agent_item_id WHERE t.status='completed' AND t.completed_at*1000 >= \(since) AND i.item_type='agentMessage' AND json_valid(i.item_json) AND json_extract(i.item_json,'$.phase')='final_answer' AND length(trim(COALESCE(json_extract(i.item_json,'$.text'),'')))>0 AND COALESCE(json_array_length(json_extract(i.item_json,'$.questions')),0)=0")
        for row in finalRows where row.count == 3 {
            guard latestTurns[row[0]]?[1] == row[1] else { continue }
            if let goal = goalStates[row[0]], goal[1] != "complete" { continue }
            if let alert = make("complete-turn:\(row[0]):\(row[1])", row[0], .complete, "本轮回复已完成", row[2]) { alerts.append(alert) }
        }
        // Only the latest turn can represent a current failure. Earlier failed
        // turns are resolved by a subsequent attempt and must not keep repeating.
        let failedRows = history.rows("SELECT t.thread_id, t.turn_id, CAST(t.completed_at * 1000 AS TEXT),COALESCE(t.error_json,'{}') FROM thread_turns t WHERE t.status='failed' AND t.completed_at * 1000 >= \(since) AND NOT EXISTS (SELECT 1 FROM thread_turns newer WHERE newer.thread_id=t.thread_id AND newer.started_at > t.started_at)")
        if ProcessInfo.processInfo.environment["AEMIS_DEBUG_TASK_MONITOR"] == "1" { fputs("monitor failed=\(failedRows)\n", stderr) }
        for row in failedRows where row.count == 4 {
            guard latestTurns[row[0]]?[1] == row[1] else { continue }
            let error = (try? JSONSerialization.jsonObject(with: Data(row[3].utf8))) as? [String: Any]
            let capacity = error?["codexErrorInfo"] as? String == "serverOverloaded" || (error?["message"] as? String)?.contains("Selected model is at capacity.") == true
            let reason = capacity ? "所选模型暂时繁忙，换个模型再试" : "运行失败，需要查看"
            if let alert = make("failed:\(row[0]):\(row[1])", row[0], .problem, reason, row[2]) { alerts.append(alert) }
        }
        // `questions` is an explicit Codex request for user input. A later user
        // message answers it, so it no longer remains actionable.
        let questionRows = history.rows("SELECT i.thread_id, i.item_id, CAST(i.created_at_ms AS TEXT) FROM thread_items i WHERE i.item_type='agentMessage' AND i.created_at_ms >= \(since) AND json_extract(i.item_json,'$.phase')='final_answer' AND json_array_length(json_extract(i.item_json,'$.questions')) > 0 AND NOT EXISTS (SELECT 1 FROM thread_items reply WHERE reply.thread_id=i.thread_id AND reply.item_type='userMessage' AND reply.created_at_ms > i.created_at_ms) AND NOT EXISTS (SELECT 1 FROM thread_items newer WHERE newer.thread_id=i.thread_id AND newer.item_type='agentMessage' AND newer.created_at_ms > i.created_at_ms AND json_extract(newer.item_json,'$.phase')='final_answer')")
        if ProcessInfo.processInfo.environment["AEMIS_DEBUG_TASK_MONITOR"] == "1" { fputs("monitor questions=\(questionRows)\n", stderr) }
        for row in questionRows where row.count == 3 {
            if let alert = make("question:\(row[0]):\(row[1])", row[0], .problem, "等待你的回复", row[2]) { alerts.append(alert) }
        }
        // Newer events supersede older state. Prefer a specific failure when
        // timestamps tie, rather than hiding it behind a generic blocked goal.
        var selected: [String: CodexTaskAlert] = [:]
        for alert in alerts {
            let identity = "\(alert.threadID):\(alert.kind.rawValue)"
            if let old = selected[identity], old.timestamp > alert.timestamp || (old.timestamp == alert.timestamp && old.reason == "所选模型暂时繁忙，换个模型再试") { continue }
            selected[identity] = alert
        }
        return Array(selected.values)
    }

    private func completionEvents(threadID: String, rolloutPath: String) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: rolloutPath) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if let cached = completionCache[rolloutPath], cached.size == size { return cached.events }
        let start = size > 1_048_576 ? size - 1_048_576 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let contents = String(data: data, encoding: .utf8) else { return [] }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true).dropFirst(start > 0 ? 1 : 0)
        var timestamps: [String] = []
        for line in lines {
            guard let raw = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let payload = entry["payload"] as? [String: Any],
                  payload["type"] as? String == "custom_tool_call_output",
                  let outputs = payload["output"] as? [[String: Any]] else { continue }
            for output in outputs {
                guard let text = output["text"] as? String,
                      text.contains("completionBudgetReport"),
                      let data = text.data(using: .utf8),
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let goal = result["goal"] as? [String: Any],
                      goal["threadId"] as? String == threadID,
                      goal["status"] as? String == "complete",
                      let updated = goal["updatedAt"] as? NSNumber else { continue }
                timestamps.append(String(updated.int64Value * 1000))
            }
        }
        completionCache[rolloutPath] = (size, timestamps)
        return timestamps
    }
}
