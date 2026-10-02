import Foundation
import SQLite3

@main struct MonitorFixture {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "monitor-fixture-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func sql(_ db: String, _ statement: String) {
            var handle: OpaquePointer?
            precondition(sqlite3_open(root.appendingPathComponent(db).path, &handle) == SQLITE_OK)
            defer { sqlite3_close(handle) }
            precondition(sqlite3_exec(handle, statement, nil, nil, nil) == SQLITE_OK, String(cString: sqlite3_errmsg(handle)))
        }
        let history = "thread_history_1.sqlite", goals = "goals_1.sqlite", state = "state_5.sqlite"
        sql(state, "CREATE TABLE threads(id TEXT,title TEXT,project_id TEXT,updated_at_ms INTEGER,rollout_path TEXT); CREATE TABLE projects(id TEXT,name TEXT);")
        sql(history, "CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,rollout_ordinal INTEGER,status TEXT,error_json TEXT,started_at INTEGER,completed_at INTEGER,final_agent_item_id TEXT); CREATE TABLE thread_items(thread_id TEXT,turn_id TEXT,item_id TEXT,item_type TEXT,created_at_ms INTEGER,item_json TEXT);")
        sql(goals, "CREATE TABLE thread_goals(thread_id TEXT,status TEXT,updated_at_ms INTEGER);")
        // Legacy joins/projections can contain duplicate metadata and goal IDs.
        sql(state, "INSERT INTO threads VALUES ('duplicate','first',NULL,0,''),('duplicate','second',NULL,0,'');")
        sql(goals, "INSERT INTO thread_goals VALUES ('duplicate','active',0),('duplicate','complete',1);")
        let base = Int(Date().timeIntervalSince1970)
        func metadata(_ id: String) { sql(state, "INSERT OR IGNORE INTO threads VALUES ('\(id)','fixture',NULL,\(base*1000),'');") }
        let capacity = #"{"message":"Selected model is at capacity. Please try a different model.","codexErrorInfo":"serverOverloaded"}"#
        func turn(_ id: String, _ turnID: String, _ start: Int, _ end: Int?, _ status: String, _ error: String = "{}") {
            metadata(id)
            sql(history, "INSERT INTO thread_turns(thread_id,turn_id,rollout_ordinal,status,error_json,started_at,completed_at) VALUES ('\(id)','\(turnID)',\(start),'\(status)','\(error)',\(base+start),\(end.map { String(base+$0) } ?? "NULL"));")
        }
        func goal(_ id: String, _ status: String, _ at: Int) {
            metadata(id); sql(goals, "DELETE FROM thread_goals WHERE thread_id='\(id)'; INSERT INTO thread_goals VALUES ('\(id)','\(status)',\((base+at)*1000));")
        }
        func item(_ id: String, _ type: String, _ at: Int, _ json: String = "{}") {
            sql(history, "INSERT INTO thread_items VALUES ('\(id)','t','item-\(at)','\(type)',\((base+at)*1000),'\(json)');")
        }
        defaults.set(15, forKey: "taskAlertRepeatMinutes")
        defaults.set(["goal:old:blocked:legacy": Double(base-10)], forKey: "taskAlertDelivered")
        turn("old", "old-turn", -20, -10, "completed"); goal("old", "blocked", -10)
        metadata("null-times")
        sql(history, "INSERT INTO thread_turns(thread_id,turn_id,rollout_ordinal,status,error_json,started_at,completed_at) VALUES ('null-times','null1',0,'failed','{}',NULL,NULL),('null-times','null2',0,'failed','{}',NULL,NULL);")
        let monitor = CodexTaskMonitor(root: root, defaults: defaults, startedAt: Double(base))
        func poll(_ seconds: Int) -> [CodexTaskAlert] { monitor.collectAlerts(now: Double(base+seconds)) }
        precondition(poll(1).isEmpty, "startup must baseline old blocked events")
        precondition(defaults.integer(forKey: "taskAlertRepeatMinutes") == 0)
        precondition((defaults.dictionary(forKey: "taskAlertDelivered") ?? [:])["goal:old:blocked:legacy"] != nil)
        turn("capacity", "capacity-turn", 2, 3, "failed", capacity)
        let alerts = poll(4)
        precondition(alerts.count == 1 && alerts[0].threadID == "capacity" && alerts[0].reason == "所选模型暂时繁忙，换个模型再试", "capacity error must be attributed")
        precondition(poll(5).isEmpty, "same failure must not repeat")
        turn("capacity", "retry", 6, nil, "inProgress")
        precondition(!monitor.isActionable(alerts[0]), "retry cancels queued alert")
        turn("question", "q", 6, 7, "completed")
        item("question", "agentMessage", 7, #"{"phase":"final_answer","questions":[{"title":"reply"}]}"#)
        let question = poll(8)
        precondition(question.count == 1 && question[0].reason == "等待你的回复")
        item("question", "userMessage", 9)
        precondition(!monitor.isActionable(question[0]), "reply cancels queued question")
        turn("blocked", "b", 9, 10, "completed"); goal("blocked", "blocked", 10)
        let blocked = poll(11)
        precondition(blocked.count == 1)
        goal("blocked", "active", 12)
        precondition(!monitor.isActionable(blocked[0]), "resumed goal cancels queued problem")
        defaults.set(false, forKey: "taskProblemAlertEnabled")
        turn("disabled", "d", 12, 13, "failed", capacity)
        precondition(poll(14).isEmpty)
        defaults.set(true, forKey: "taskProblemAlertEnabled")
        precondition(poll(15).isEmpty, "enabling must not replay disabled events")
        let restarted = CodexTaskMonitor(root: root, defaults: defaults, startedAt: Double(base+15))
        precondition(restarted.collectAlerts(now: Double(base+16)).isEmpty, "restart replay")
        turn("sleep", "s", 100, 110, "failed", capacity)
        precondition(poll(120).isEmpty && poll(121).isEmpty, "wake must baseline old events")
        goal("orphan", "blocked", 122)
        metadata("screenshot")
        item("screenshot", "userMessage", 122, #"{"text":"Selected model is at capacity. Please try a different model."}"#)
        turn("ordinary", "o", 121, 122, "completed")
        precondition(poll(123).isEmpty, "idle orphan, quoted text, ordinary completion must be silent")
        turn("new", "n", 123, 124, "failed")
        let generic = poll(125)
        precondition(generic.count == 1 && generic[0].reason == "运行失败，需要查看")
        goal("new", "complete", 126)
        precondition(!monitor.isActionable(generic[0]))
        let complete = poll(127)
        precondition(complete.count == 1 && complete[0].kind == .complete)
        precondition(poll(128).isEmpty)
        // A fresh failure after an earlier completion must not be hidden.
        turn("new", "n2", 129, 130, "failed", capacity)
        precondition(poll(131).first?.reason == "所选模型暂时繁忙，换个模型再试")
        metadata("rollout")
        let rollout = root.appendingPathComponent("complete.jsonl")
        let result: [String: Any] = ["goal": ["threadId": "rollout", "status": "complete", "updatedAt": base+132], "completionBudgetReport": "Goal achieved"]
        let resultText = String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
        let entry: [String: Any] = ["payload": ["type": "custom_tool_call_output", "output": [["text": resultText]]]]
        try JSONSerialization.data(withJSONObject: entry).write(to: rollout)
        sql(state, "UPDATE threads SET rollout_path='\(rollout.path)',updated_at_ms=\((base+132)*1000) WHERE id='rollout';")
        precondition(poll(133).first?.kind == .complete, "deleted goal completion remains observable in rollout")
        func final(_ id: String, _ turnID: String, _ at: Int, _ phase: String = "final_answer", _ text: String = "已完成") {
            sql(history, "INSERT INTO thread_items VALUES ('\(id)','\(turnID)','final-\(turnID)','agentMessage',\((base+at)*1000),'{\"phase\":\"\(phase)\",\"text\":\"\(text)\"}'); UPDATE thread_turns SET final_agent_item_id='final-\(turnID)' WHERE thread_id='\(id)' AND turn_id='\(turnID)';")
        }
        turn("normal", "n1", 134, 135, "completed"); final("normal", "n1", 135)
        let normal = poll(136)
        precondition(normal.count == 1 && normal[0].reason == "本轮回复已完成")
        precondition(poll(137).isEmpty)
        turn("normal", "n2", 138, 139, "completed"); final("normal", "n2", 139)
        let next = poll(140)
        precondition(next.count == 1 && next[0].key != normal[0].key, "distinct turns under 60 seconds must not be swallowed")
        turn("commentary", "c", 140, 141, "completed"); final("commentary", "c", 141, "commentary")
        turn("blank", "b", 140, 141, "completed"); final("blank", "b", 141, "final_answer", " ")
        turn("working", "w", 140, nil, "inProgress"); final("working", "w", 141)
        precondition(poll(142).isEmpty, "commentary, blank and unfinished turns are not completion")
        turn("dual", "dual1", 142, 144, "completed")
        goal("dual", "complete", 143)
        let explicit = poll(144)
        precondition(explicit.count == 1)
        final("dual", "dual1", 144)
        precondition(poll(145).isEmpty, "goal and final answer share one turn event")
        turn("dual", "dual2", 146, nil, "inProgress")
        precondition(poll(147).isEmpty, "new turn must not change prior completion identity")
        precondition(monitor.isActionable(explicit[0]), "new turn must not swallow queued completed event")
        // Use the production async poll -> main queue callback, without UI/audio.
        let callbackSuite = "monitor-callback-\(UUID())"
        let callbackDefaults = UserDefaults(suiteName: callbackSuite)!
        defer { callbackDefaults.removePersistentDomain(forName: callbackSuite) }
        let callbackMonitor = CodexTaskMonitor(root: root, defaults: callbackDefaults, startedAt: Double(base-2))
        turn("callback", "cb", -1, 0, "completed"); final("callback", "cb", 0)
        var callbacks = [CodexTaskAlert]()
        callbackMonitor.onAlert = { callbacks.append($0) }
        callbackMonitor.poll()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        precondition(callbacks.contains { $0.threadID == "callback" && $0.kind == .complete }, "async callback route")
        var settings = CodexTaskAlertSettings.load(defaults: defaults)
        let calendar = Calendar.current
        let night = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        precondition(!settings.isQuiet(at: night), "23:00 must not silently disable default alerts")
        settings.quietEnabled = true
        precondition(settings.isQuiet(at: night) && !settings.isQuiet(at: morning))
        settings.save(defaults: defaults)
        precondition(CodexTaskAlertSettings.load(defaults: defaults).quietEnabled)
        settings.quietEnabled = false
        settings.volume = 2; settings.save(defaults: defaults)
        precondition(CodexTaskAlertSettings.load(defaults: defaults).volume == 2)
        for tick in stride(from: 151, through: 1100, by: 4) { precondition(poll(tick).isEmpty, "15-minute replay") }
        print("PASS: duplicate IDs/null timestamps, ordinary final replies, consecutive turns, goal/final deduplication, async callback, capacity attribution, once-only, reply/retry/resume/completion cancellation, disabled/restart/sleep silence, no-task/quoted-text silence, migration, volume, >15min idle")
    }
}
