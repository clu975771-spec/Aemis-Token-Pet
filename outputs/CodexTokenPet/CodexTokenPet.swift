import AppKit
import ApplicationServices
import CoreGraphics
import ColorSync
import UniformTypeIdentifiers
import AVFoundation
import SQLite3

struct UsageSnapshot { let projectName: String; let projectTokens: Int; let lastTokens: Int }
enum DisplayMode: String { case automatic, tokenOnly, appOnly }

struct BuiltInCharacterProfile {
    let id: String; let name: String; let bubbleFill: NSColor; let accent: NSColor; let detail: NSColor; let persona: String
    static func profile(for id: String) -> BuiltInCharacterProfile {
        switch id {
        default: return .init(id: "aemis", name: "爱弥斯", bubbleFill: NSColor(calibratedRed: 1, green: 0.93, blue: 0.97, alpha: 0.98), accent: NSColor(calibratedRed: 0.82, green: 0.30, blue: 0.49, alpha: 1), detail: NSColor(calibratedRed: 0.10, green: 0.64, blue: 0.72, alpha: 1), persona: "你是《鸣潮》的爱弥斯：来自星炬学院、以电子幽灵形态陪伴用户。轻快温柔、喜欢游戏与星光意象，偶尔俏皮但不浮夸；重视家人与陪伴。回答使用简短自然的中文，不冒犯、不假装无所不知，也不要编造官方经历。")
        }
    }
}
enum ParticleStyle: String, CaseIterable {
    case stars, hearts, petals, bubbles, mixed, off
    var title: String { switch self { case .stars: return "星光"; case .hearts: return "爱心"; case .petals: return "花瓣"; case .bubbles: return "泡泡"; case .mixed: return "混合"; case .off: return "关闭" } }
    var glyphs: [String] { switch self { case .stars: return ["✦", "✧", "⋆"]; case .hearts: return ["♥", "♡", "❤"]; case .petals: return ["❀", "✿", "❁"]; case .bubbles: return ["○", "◌", "◦"]; case .mixed: return ["✦", "♡", "❀", "○", "✧"]; case .off: return [] } }
}
enum DockPosition: String { case bottomRight, bottomLeft, topRight, topLeft
    var title: String { switch self { case .bottomRight: return "右下角"; case .bottomLeft: return "左下角"; case .topRight: return "右上角"; case .topLeft: return "左上角" } }
}
enum InteractionTrigger: String, CaseIterable {
    case doubleTap, tripleTaps, fiveTaps, tenTaps, fifteenTaps, idleFifteenSeconds, appSwitch, focusComplete, hourlyGreeting, dailyFiftyTaps, ambientRandomVoice
    var title: String { switch self { case .doubleTap: return "连续点击 2 次"; case .tripleTaps: return "连续点击 3 次"; case .fiveTaps: return "连续点击 5 次"; case .tenTaps: return "连续点击 10 次"; case .fifteenTaps: return "连续点击 15 次"; case .idleFifteenSeconds: return "15 秒未互动"; case .appSwitch: return "切换前台软件"; case .focusComplete: return "专注计时结束"; case .hourlyGreeting: return "整点问候"; case .dailyFiftyTaps: return "今日互动每满 50 次"; case .ambientRandomVoice: return "随机空闲语音" } }
}
enum TapSound: String, CaseIterable {
    case basso, pop, funk, blow, bottle, frog, purr, submarine, custom
    var title: String {
        switch self {
        case .basso: return "低沉咚咚"; case .pop: return "清脆啵啵"; case .funk: return "活泼噗噗"; case .blow: return "轻吹呼呼"
        case .bottle: return "玻璃叮咚"; case .frog: return "小青蛙"; case .purr: return "猫咪呼噜"; case .submarine: return "潜水雷达"; case .custom: return "自定义音效"
        }
    }
    var filePath: String? {
        switch self {
        case .basso: return "/System/Library/Sounds/Basso.aiff"; case .pop: return "/System/Library/Sounds/Pop.aiff"; case .funk: return "/System/Library/Sounds/Funk.aiff"; case .blow: return "/System/Library/Sounds/Blow.aiff"
        case .bottle: return "/System/Library/Sounds/Bottle.aiff"; case .frog: return "/System/Library/Sounds/Frog.aiff"; case .purr: return "/System/Library/Sounds/Purr.aiff"; case .submarine: return "/System/Library/Sounds/Submarine.aiff"; case .custom: return nil
        }
    }
}

struct SavedColor: Codable { let red: CGFloat; let green: CGFloat; let blue: CGFloat; let alpha: CGFloat }
struct CharacterPreset: Codable, Identifiable {
    let id: String; var name: String; var mascotPath: String?; var color: SavedColor; var mascotSize: CGFloat; var bubbleSize: CGFloat
    var patMessage: String; var tapSound: String; var customSoundPath: String?; var soundVolume: Float
    var eventImages: [TriggeredAsset]?; var eventSounds: [TriggeredAsset]?; var clickSoundPaths: [String]?
    var persona: String? = nil
}
struct TriggeredAsset: Codable, Identifiable { let id: String; let trigger: String; let path: String }
struct PresetPack: Codable { let formatVersion: Int; var preset: CharacterPreset }

struct FrontmostContext {
    let appName: String
    let windowTitle: String?
    let pageURL: String?
    let isCodex: Bool

    var activity: String {
        let clue = "\(appName) \(windowTitle ?? "") \(pageURL ?? "")".lowercased()
        if clue.contains("douyin") || clue.contains("抖音") || clue.contains("bilibili") || clue.contains("哔哩") || clue.contains("youtube") || clue.contains("视频") { return "正在刷视频" }
        if clue.contains("chrome") || clue.contains("safari") || clue.contains("firefox") || clue.contains("edge") { return "正在浏览网页" }
        return "正在使用"
    }

    var sourceLabel: String? {
        guard let pageURL, let host = URL(string: pageURL)?.host else { return windowTitle }
        if host.contains("douyin.com") { return "抖音 · \(host)" }
        if host.contains("bilibili.com") { return "哔哩哔哩 · \(host)" }
        if host.contains("youtube.com") { return "YouTube · \(host)" }
        if host.contains("github.com") { return "GitHub · \(host)" }
        return host
    }
}

final class FrontmostAppReader {
    func current() -> FrontmostContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let name = app.localizedName ?? "未知应用"
        let identifier = app.bundleIdentifier?.lowercased() ?? ""
        let isCodex = identifier.contains("openai") || name.lowercased().contains("chatgpt") || name.lowercased().contains("codex")
        return FrontmostContext(appName: name, windowTitle: windowTitle(for: app.processIdentifier), pageURL: browserURL(for: identifier), isCodex: isCodex)
    }

    private func windowTitle(for pid: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let title = window[kCGWindowName as String] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return title
        }
        return nil
    }

    private func browserURL(for bundleIdentifier: String) -> String? {
        let script: String
        switch bundleIdentifier {
        case "com.google.chrome":
            script = "tell application \"Google Chrome\" to return URL of active tab of front window"
        case "com.apple.safari":
            script = "tell application \"Safari\" to return URL of front document"
        case "com.microsoft.edgemac":
            script = "tell application \"Microsoft Edge\" to return URL of active tab of front window"
        case "com.brave.browser":
            script = "tell application \"Brave Browser\" to return URL of active tab of front window"
        default:
            return nil
        }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0,
              let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class UsageReader {
    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    private let focusLock = NSLock()
    private var focusedThreadID: String?
    private var lastFocusEventTimestamp: Double = 0
    private var didInitializeFocus = false

    func latestSnapshot(codexIsFrontmost: Bool = true) -> UsageSnapshot? {
        focusLock.lock()
        defer { focusLock.unlock() }

        updateFocusedThread()
        if codexIsFrontmost,
           let selection = focusedCodexSelectionFromAccessibility(),
           let threadID = resolveThreadID(label: selection.threadLabel, projectName: selection.projectName) {
            focusedThreadID = threadID
        }
        guard let project = focusedThreadID.flatMap({ usage(forThreadID: $0) }) ?? mostRecentlyActiveProject() else { return nil }
        return UsageSnapshot(projectName: project.name,
                             projectTokens: project.totalTokens, lastTokens: project.currentTaskTokens)
    }

    private typealias ProjectUsage = (name: String, totalTokens: Int, currentTaskTokens: Int)
    private typealias FocusEvent = (threadID: String, timestamp: Double)
    private typealias UpdatedThread = (threadID: String, timestamp: Double)

    /// Codex keeps the focused route inside the renderer, but its Sentry scope
    /// exposes a lightweight breadcrumb whenever a sidebar thread is selected.
    /// Remember that selection so background task updates cannot steal focus.
    private func updateFocusedThread() {
        let event = latestThreadSelectionEvent()
        if !didInitializeFocus {
            didInitializeFocus = true
            let updated = mostRecentlyUpdatedThread()
            if let event {
                lastFocusEventTimestamp = event.timestamp
                // If a task has had a newer foreground interaction since the last
                // recorded sidebar selection (for example navigation from a link),
                // use that task for initial calibration.
                if let updated, updated.timestamp > event.timestamp + 10_000 {
                    focusedThreadID = updated.threadID
                } else {
                    focusedThreadID = event.threadID
                }
            } else {
                focusedThreadID = updated?.threadID
            }
            return
        }

        if let event, event.timestamp > lastFocusEventTimestamp + 0.5 {
            lastFocusEventTimestamp = event.timestamp
            focusedThreadID = event.threadID
        }
    }

    private func latestThreadSelectionEvent() -> FocusEvent? {
        let scopeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex/sentry/scope_v3.json")
        guard let data = try? Data(contentsOf: scopeURL),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scope = document["scope"] as? [String: Any],
              let breadcrumbs = scope["breadcrumbs"] as? [[String: Any]] else { return nil }

        for breadcrumb in breadcrumbs.reversed() {
            guard breadcrumb["category"] as? String == "ui.click",
                  let message = breadcrumb["message"] as? String,
                  message.contains("app-action-sidebar-thread-selected=true"),
                  let label = ariaLabel(in: message),
                  let threadID = resolveThreadID(label: label, projectName: nil) else { continue }
            let seconds = (breadcrumb["timestamp"] as? NSNumber)?.doubleValue ?? 0
            return (threadID, seconds * 1_000)
        }
        return nil
    }

    private func ariaLabel(in message: String) -> String? {
        let marker = "[aria-label=\""
        guard let start = message.range(of: marker, options: .backwards) else { return nil }
        let suffix = message[start.upperBound...]
        guard let end = suffix.range(of: "\"]") else { return nil }
        let label = String(suffix[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    private func focusedCodexSelectionFromAccessibility() -> (projectName: String, threadLabel: String)? {
        let debug = ProcessInfo.processInfo.environment["AEMIS_DEBUG_FOCUS"] == "1"
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.lowercased() == "com.openai.codex" ||
            $0.localizedName?.lowercased() == "chatgpt"
        }) else {
            if debug { fputs("focus: Codex app not found\n", stderr) }
            return nil
        }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        // Chromium exposes only a shallow accessibility tree until accessibility
        // is explicitly requested. These writes are harmless when it is already
        // enabled, and make the current Codex project/task header observable.
        _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        if debug {
            fputs("focus: pid=\(app.processIdentifier), trusted=\(AXIsProcessTrusted())\n", stderr)
        }
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedValue)
        guard focusedStatus == .success, focusedValue != nil else {
            if debug { fputs("focus: AX focused window unavailable (\(focusedStatus.rawValue))\n", stderr) }
            return nil
        }

        func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }
        func children(of element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
            return value as? [AXUIElement] ?? []
        }
        func firstButtonTitle(in element: AXUIElement, depth: Int = 0) -> String? {
            guard depth < 4 else { return nil }
            if stringAttribute(element, kAXRoleAttribute) == kAXButtonRole as String,
               let title = stringAttribute(element, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty { return title }
            for child in children(of: element) {
                if let title = firstButtonTitle(in: child, depth: depth + 1) { return title }
            }
            return nil
        }

        // Start at the application root. In Chromium the focused-window node can
        // remain a shallow proxy while the full web accessibility tree hangs off
        // the application/window collection.
        var queue: [(AXUIElement, Int)] = [(application, 0)]
        var index = 0
        var currentProjectName: String?
        while index < queue.count, index < 2_500 {
            let (element, depth) = queue[index]
            index += 1
            let role = stringAttribute(element, kAXRoleAttribute)
            if debug, role == kAXPopUpButtonRole as String || role == kAXButtonRole as String {
                let title = stringAttribute(element, kAXTitleAttribute) ?? ""
                let description = stringAttribute(element, kAXDescriptionAttribute) ?? ""
                if !title.isEmpty || !description.isEmpty { fputs("focus node: \(role ?? "?") | \(title) | \(description)\n", stderr) }
            }
            if role == kAXPopUpButtonRole as String,
               let description = stringAttribute(element, kAXDescriptionAttribute),
               description.hasPrefix("项目：") {
                let projectName = String(description.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !projectName.isEmpty, let threadLabel = firstButtonTitle(in: element), !threadLabel.isEmpty {
                    if debug { fputs("focus: \(projectName) / \(threadLabel)\n", stderr) }
                    return (projectName, threadLabel)
                }
                if !projectName.isEmpty { currentProjectName = projectName }
            } else if role == kAXButtonRole as String,
                      let projectName = currentProjectName,
                      let threadLabel = stringAttribute(element, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !threadLabel.isEmpty {
                // Codex renders the task-title button as a sibling immediately
                // after the project selector, rather than as its AX child.
                if debug { fputs("focus: \(projectName) / \(threadLabel)\n", stderr) }
                return (projectName, threadLabel)
            }
            if depth < 18 { queue.append(contentsOf: children(of: element).map { ($0, depth + 1) }) }
        }
        if debug { fputs("focus: project header not found after \(index) AX elements\n", stderr) }
        return nil
    }

    private func resolveThreadID(label: String, projectName: String?) -> String? {
        let literal = sqlLiteral(label)
        let projectConstraint: String
        if let projectName, let roots = roots(forProjectName: projectName), !roots.isEmpty {
            projectConstraint = " AND (" + roots.map { cwdCondition(column: "cwd", rootPath: $0) }.joined(separator: " OR ") + ")"
        } else {
            projectConstraint = ""
        }
        let direct = """
        SELECT id FROM threads
        WHERE archived = 0 AND (name = \(literal) OR title = \(literal)
          OR instr(COALESCE(name, ''), \(literal)) > 0 OR instr(title, \(literal)) > 0)
          \(projectConstraint)
        ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC LIMIT 1;
        """
        if let id = sqlite(direct), !id.isEmpty { return id }

        // Sidebar titles can be shorter than the database title. Codex's own
        // generated thread descriptions provide the stable ID mapping in that case.
        guard let state = globalState(),
              let atoms = state["electron-persisted-atom-state"] as? [String: Any],
              let descriptions = atoms["thread-descriptions-v1"] as? [String: Any] else { return nil }
        let candidates = descriptions.compactMap { id, value -> String? in
            guard let description = value as? String,
                  description.localizedCaseInsensitiveContains(label) || label.localizedCaseInsensitiveContains(description) else { return nil }
            return id
        }
        guard !candidates.isEmpty else { return nil }
        let ids = candidates.map(sqlLiteral).joined(separator: ",")
        return sqlite("SELECT id FROM threads WHERE archived = 0 AND id IN (\(ids)) ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC LIMIT 1;")
    }

    private func roots(forProjectName projectName: String) -> [String]? {
        guard let state = globalState(), let projects = state["local-projects"] as? [String: Any] else { return nil }
        for value in projects.values {
            guard let project = value as? [String: Any],
                  let name = project["name"] as? String,
                  name == projectName,
                  let roots = project["rootPaths"] as? [String], !roots.isEmpty else { continue }
            return roots
        }
        return nil
    }

    private func mostRecentlyUpdatedThread() -> UpdatedThread? {
        let query = "SELECT id, COALESCE(updated_at_ms, updated_at * 1000) FROM threads WHERE archived = 0 ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC LIMIT 1;"
        guard let parts = sqlite(query)?.split(separator: "\t", maxSplits: 1).map(String.init),
              parts.count == 2, let timestamp = Double(parts[1]) else { return nil }
        return (parts[0], timestamp)
    }

    private func usage(forThreadID threadID: String) -> ProjectUsage? {
        let literal = sqlLiteral(threadID)
        guard let result = sqlite("SELECT cwd, COALESCE(tokens_used, 0) FROM threads WHERE archived = 0 AND id = \(literal) LIMIT 1;")?.split(separator: "\t", maxSplits: 1).map(String.init),
              result.count == 2, let currentTokens = Int(result[1]) else { return nil }
        let cwd = result[0]

        if let project = project(containing: cwd) {
            let conditions = project.roots.map { cwdCondition(column: "cwd", rootPath: $0) }.joined(separator: " OR ")
            let total = Int(sqlite("SELECT COALESCE(SUM(tokens_used), 0) FROM threads WHERE archived = 0 AND (\(conditions));") ?? "") ?? currentTokens
            return (project.name, total, currentTokens)
        }

        let cwdLiteral = sqlLiteral(cwd)
        let total = Int(sqlite("SELECT COALESCE(SUM(tokens_used), 0) FROM threads WHERE archived = 0 AND cwd = \(cwdLiteral);") ?? "") ?? currentTokens
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return (name.isEmpty ? "Codex" : name, total, currentTokens)
    }

    private func globalState() -> [String: Any]? {
        let stateURL = root.appendingPathComponent(".codex-global-state.json")
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return state
    }

    private func project(containing cwd: String) -> (name: String, roots: [String])? {
        guard let state = globalState(), let projects = state["local-projects"] as? [String: Any] else { return nil }
        var best: (name: String, roots: [String], matchLength: Int)?
        for value in projects.values {
            guard let project = value as? [String: Any], let roots = project["rootPaths"] as? [String], !roots.isEmpty else { continue }
            for rootPath in roots {
                let normalized = URL(fileURLWithPath: rootPath).standardizedFileURL.path
                guard cwd == normalized || cwd.hasPrefix(normalized + "/") else { continue }
                let name = ((project["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? URL(fileURLWithPath: normalized).lastPathComponent
                if best == nil || normalized.count > best!.matchLength { best = (name, roots, normalized.count) }
            }
        }
        return best.map { ($0.name, $0.roots) }
    }

    // Compatibility fallback for projectless chats and older Codex versions.
    private func mostRecentlyActiveProject() -> ProjectUsage? {
        let query = """
        WITH active_project AS (SELECT cwd FROM threads WHERE archived = 0 ORDER BY recency_at_ms DESC LIMIT 1)
        SELECT active_project.cwd, COALESCE(SUM(threads.tokens_used), 0)
        FROM threads, active_project WHERE threads.archived = 0 AND threads.cwd = active_project.cwd
        GROUP BY active_project.cwd;
        """
        guard let result = sqlite(query)?.split(separator: "\t", maxSplits: 1).map(String.init),
              result.count == 2, let tokens = Int(result[1]) else { return nil }
        let cwd = result[0]
        let name = URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? "Codex" : URL(fileURLWithPath: cwd).lastPathComponent
        let literal = sqlLiteral(cwd)
        let current = Int(sqlite("SELECT COALESCE(tokens_used, 0) FROM threads WHERE archived = 0 AND cwd = \(literal) ORDER BY recency_at_ms DESC LIMIT 1;") ?? "") ?? 0
        return (name, tokens, current)
    }

    private func cwdCondition(column: String, rootPath: String) -> String {
        var normalized = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        if normalized.count > 1, normalized.hasSuffix("/") { normalized.removeLast() }
        let literal = sqlLiteral(normalized)
        return "(\(column) = \(literal) OR substr(\(column), 1, length(\(literal)) + 1) = \(literal) || '/')"
    }

    private func sqlLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func sqlite(_ query: String) -> String? {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-tabs", root.appendingPathComponent("state_5.sqlite").path, query]
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0,
              let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return nil }
        return text.split(separator: "\n").first.map(String.init)
    }

}

final class PassiveEmoticonView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class BubbleView: NSView {
    var snapshot: UsageSnapshot? { didSet { needsDisplay = true } }; var mascot: NSImage?
    var frontmostContext: FrontmostContext? { didSet { needsDisplay = true } }
    var onMascotTap: (() -> Void)?
    var onTenTapVoiceRequested: (() -> Void)?
    var shouldPlayLegacyVoice: ((InteractionTrigger) -> Bool)?
    var onCodexLaunchRequested: (() -> Void)?
    var onTaskAlertClicked: ((String) -> Void)?
    var onSetTaskAlertVolume: ((Float) -> Void)?
    var onPreviewTaskAlert: ((CodexTaskAlertKind) -> Void)?
    var onChooseMascot: (() -> Void)?; var onChooseColor: (() -> Void)?; var onResetAppearance: (() -> Void)?
    var onSetDisplayMode: ((DisplayMode) -> Void)?; var onSetMascotSize: ((CGFloat) -> Void)?; var onToggleClickSound: (() -> Void)?
    var onSetBubbleSize: ((CGFloat) -> Void)?; var onSetTapSound: ((TapSound) -> Void)?; var onSetSoundVolume: ((Float) -> Void)?
    var onSetBubbleOpacity: ((CGFloat) -> Void)?; var onChooseCustomSound: (() -> Void)?; var onSetPatMessage: (() -> Void)?; var onSavePreset: (() -> Void)?; var onImportPresetPack: (() -> Void)?; var onExportPresetPack: (() -> Void)?; var onImportClickSounds: (() -> Void)?; var onImportEventSounds: (() -> Void)?; var onApplyPreset: ((String) -> Void)?; var onSelectBuiltInMascot: ((String) -> Void)?; var onRememberPosition: (() -> Void)?; var onSaveCurrentPosition: (() -> Void)?; var onDockPosition: ((DockPosition) -> Void)?; var onInteraction: (() -> Void)?; var onStartFocus: (() -> Void)?; var onStopFocus: (() -> Void)?; var onOpenSettings: (() -> Void)?; var onOpenChat: (() -> Void)?
    var selectedBuiltInMascotID = "aemis"
    var characterProfile: BuiltInCharacterProfile { BuiltInCharacterProfile.profile(for: selectedBuiltInMascotID) }
    var themeColor = NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.96, alpha: 0.97) { didSet { needsDisplay = true } }
    var mascotSize: CGFloat = 1 { didSet { needsDisplay = true } }
    var bubbleSize: CGFloat = 1 { didSet { needsDisplay = true } }
    var bubbleOpacity: CGFloat = 0.97 { didSet { needsDisplay = true } }
    var displayMode: DisplayMode = .automatic { didSet { needsDisplay = true } }
    var clickSoundEnabled = true
    var tapSound: TapSound = .basso
    var customSoundPath: String?
    var soundVolume: Float = 0.55
    var ambientVoiceEnabled = false
    var ambientVoiceIntervalMinutes = 15
    var particleStyle: ParticleStyle = .stars
    var onAIQuoteRequested: (() -> Void)?
    var onClipboardPanelHeightChanged: ((CGFloat?) -> Void)?
    var clipboardHistory: [String] = [] { didSet { clipboardSelection = min(clipboardSelection, max(0, clipboardHistory.count - 1)); needsDisplay = true } }
    var visualContextEnabled = true
    var experimentalTTSEnabled = false
    var visualSuccessCount = 0
    var visualFallbackCount = 0
    private(set) var lastAIQuote: String?
    private var favoriteQuotes: [String] = UserDefaults.standard.stringArray(forKey: "favoriteAIQuotes") ?? []
    private var quotePauseUntil: Date? {
        get { UserDefaults.standard.object(forKey: "quotePauseUntil") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "quotePauseUntil") }
    }
    var patMessage = "不要再拍我了"
    var presets: [CharacterPreset] = []
    var todayInteractions = 0
    // Retained only to decode older .aemispreset files. Runtime rendering never
    // reads these images and the menu no longer exposes image-trigger imports.
    var eventImages: [TriggeredAsset] = []
    var eventSounds: [TriggeredAsset] = []
    var clickSoundPaths: [String] = []
    var positionMemoryEnabled = false { didSet { needsDisplay = true } }
    /// Expanded chat panels may grow toward the free side of the screen. Keeping the
    /// mascot on an explicit local X coordinate prevents that resize from moving it.
    var mascotAnchorX: CGFloat? { didSet { needsDisplay = true } }
    private(set) var chatExpanded = false
    var focusEndsAt: Date? { didSet { needsDisplay = true } }
    private var mascotScaleX: CGFloat = 1
    private var mascotScaleY: CGFloat = 1
    private var mascotYOffset: CGFloat = 0
    private var bubbleScaleX: CGFloat = 1
    private var bubbleScaleY: CGFloat = 1
    private var bubbleYOffset: CGFloat = 0
    private var jellyTimer: Timer?
    let layeredRig = AemisLayeredRig(directory: URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("assets/aemis-rig-v03"))
    private var rigTapX = 0.5
    private var legacyAudioPlayers: [AVAudioPlayer] = []
    func trackSpeech(_ player: AVAudioPlayer?) { if let player { layeredRig?.track(player) } }

    private var recentTapTimes: [Date] = []
    private var showingNoMorePatMessage = false
    private var showingTapSpeed = false
    private var tapSpeedDismissTimer: Timer?
    private var lastInteractionAt = Date()
    private var firedTapTriggers = Set<InteractionTrigger>()
    private var tapSessionResetTimer: Timer?
    private var idleTimer: Timer?
    private var hourlyTimer: Timer?
    private var ambientVoiceTimer: Timer?
    private var legacySoundProcesses: [Process] = []
    private weak var soundVolumeLabel: NSMenuItem?
    private weak var taskAlertVolumeLabel: NSMenuItem?
    private weak var mascotSizeLabel: NSMenuItem?
    private weak var bubbleSizeLabel: NSMenuItem?
    private weak var bubbleOpacityLabel: NSMenuItem?
    private var lastTapSpeed: Double = 0
    private struct SparkleParticle {
        let glyph: String
        let color: NSColor
        let origin: NSPoint
        let drift: CGFloat
        let bornAt: Date
    }
    private var sparkleParticles: [SparkleParticle] = []
    private var sparkleTimer: Timer?
    private var startupPulseStartedAt: Date?
    private var startupPulseTimer: Timer?
    private var startupPhaseQueue: [String] = []
    private var startupPhasePresentationTimer: Timer?
    private var isPresentingStartupPhase = false
    private var emoticonTimer: Timer?
    private var emoticonDismissTimer: Timer?
    private var emoticonURLs: [URL] = []
    private var lastEmoticonURL: URL?
    private let emoticonView = PassiveEmoticonView()
    private var emoticonShowing = false
    private var messageTitle: String?
    private var messageBody: String?
    private var messageDetail: String?
    private var messageAccentColorOverride: NSColor?
    private var messageDetailColorOverride: NSColor?
    private var messageTimer: Timer?
    private var taskAlertThreadID: String?
    var isTaskAlertVisible: Bool { taskAlertThreadID != nil }
    private var lastHourlyGreetingHour: Int?
    private var embeddedChat: AemisBubbleChatView?
    private var dragStartPointer: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private enum PointerTarget: Equatable { case bubble, mascot }
    private var pointerTarget: PointerTarget?
    private var pointerDidDrag = false
    private var pendingSingleClick: DispatchWorkItem?
    private var visibleMascotCache: [ObjectIdentifier: NSImage] = [:]
    private var clipboardExpanded = false
    private var clipboardSelection = 0

    /// 每张表情图都使用同一块“人物舞台”。这样图本身较宽、较窄或透明留白不同，
    /// 都不会带着整个桌宠窗口一起忽宽忽窄；人物则始终按相同可见高度绘制。
    private let mascotStageAspectRatio: CGFloat = 1.40
    var mascotStageWidth: CGFloat {
        154 * mascotSize * mascotStageAspectRatio
    }
    var mascotAreaHeight: CGFloat { 154 * mascotSize }
    private var mascotCenterX: CGFloat { mascotAnchorX ?? bounds.midX }

    private var compactBubbleHitRect: NSRect {
        let bubbleBase = mascotAreaHeight - 1
        let expandedHeight = clipboardExpanded ? 226 * bubbleSize : 111 * bubbleSize
        let raw = NSRect(x: mascotCenterX - 121 * bubbleSize,
                         y: bubbleBase,
                         width: 242 * bubbleSize,
                         height: expandedHeight)
        return NSRect(x: raw.midX - raw.width * bubbleScaleX / 2,
                      y: raw.midY - raw.height * bubbleScaleY / 2 + bubbleYOffset - 10,
                      width: raw.width * bubbleScaleX,
                      height: raw.height * bubbleScaleY + 20)
    }

    override func mouseDown(with event: NSEvent) {
        guard !chatExpanded else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        let hitTarget: PointerTarget = compactBubbleHitRect.contains(point) ? .bubble : .mascot
        if event.modifierFlags.contains(.control) {
            cancelPendingSingleClick()
            showSettingsMenu(at: point)
            return
        }
        if event.clickCount >= 2, hitTarget == .bubble {
            cancelPendingSingleClick()
            dragStartPointer = nil
            dragStartWindowOrigin = nil
            pointerTarget = nil
            pointerDidDrag = false
            if let threadID = taskAlertThreadID {
                onTaskAlertClicked?(threadID)
                return
            }
            // AppKit may report 3/4 for a rapid sequence. Only the first complete
            // pair is a launch gesture; AppDelegate applies a second safety gate.
            if event.clickCount == 2 {
                fputs("interaction: double-click launch-request\n", stderr)
                startJelly()
                lastInteractionAt = Date()
                onInteraction?()
                onCodexLaunchRequested?()
            }
            return
        }
        // Only the painted bubble owns the launch gesture. Mascot clicks always
        // remain ordinary pet interactions, including the second click of a pair.
        pointerTarget = hitTarget
        pointerDidDrag = false
        if pointerTarget == .mascot {
            rigTapX = Double(max(0,min(1,(point.x-mascotCenterX)/mascotStageWidth+0.5)))
            cancelPendingSingleClick()
            dragStartPointer = NSEvent.mouseLocation
            dragStartWindowOrigin = window?.frame.origin
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard !chatExpanded else { super.scrollWheel(with: event); return }
        if isTaskAlertVisible { super.scrollWheel(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        guard compactBubbleHitRect.contains(point) || clipboardExpanded else { super.scrollWheel(with: event); return }
        guard !clipboardHistory.isEmpty else {
            showMessage(title: "剪贴板历史", body: "还没有文字记录", detail: "复制文字后再滚动试试", duration: 4)
            return
        }
        if !clipboardExpanded { setClipboardExpanded(true) }
        if abs(event.scrollingDeltaY) > 0.3 {
            clipboardSelection = (clipboardSelection + (event.scrollingDeltaY < 0 ? 1 : -1) + clipboardHistory.count) % clipboardHistory.count
        }
        needsDisplay = true
    }

    private func setClipboardExpanded(_ expanded: Bool) {
        guard clipboardExpanded != expanded else { return }
        clipboardExpanded = expanded
        onClipboardPanelHeightChanged?(expanded ? mascotAreaHeight + 226 * bubbleSize + 18 : nil)
        needsDisplay = true
    }

    func showClipboardHistoryForTesting(_ entries: [String]) {
        clipboardHistory = entries
        clipboardSelection = 0
        setClipboardExpanded(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !chatExpanded, pointerTarget == .mascot, let startPointer = dragStartPointer, let startOrigin = dragStartWindowOrigin, let window else { return }
        let pointer = NSEvent.mouseLocation
        let delta = NSPoint(x: pointer.x - startPointer.x, y: pointer.y - startPointer.y)
        guard hypot(delta.x, delta.y) > 3 else { return }
        if !pointerDidDrag { fputs("interaction: drag\n", stderr) }
        pointerDidDrag = true
        cancelPendingSingleClick()
        window.setFrameOrigin(NSPoint(x: startOrigin.x + delta.x, y: startOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        let target = pointerTarget
        let dragged = pointerDidDrag
        dragStartPointer = nil
        dragStartWindowOrigin = nil
        pointerTarget = nil
        pointerDidDrag = false
        if !dragged, let target {
            switch target {
            case .mascot:
                performSingleClick(.mascot)
            case .bubble where event.clickCount < 2:
                scheduleSingleClick(.bubble)
            case .bubble:
                break
            }
        }
        super.mouseUp(with: event)
    }

    private func scheduleSingleClick(_ target: PointerTarget) {
        cancelPendingSingleClick()
        let work = DispatchWorkItem { [weak self] in self?.performSingleClick(target) }
        pendingSingleClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.25, NSEvent.doubleClickInterval + 0.03), execute: work)
    }

    private func cancelPendingSingleClick() {
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
    }

    private func performSingleClick(_ target: PointerTarget) {
        pendingSingleClick = nil
        switch target {
        case .bubble:
            if clipboardExpanded, !clipboardHistory.isEmpty {
                let value = clipboardHistory[clipboardSelection]
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                setClipboardExpanded(false)
                showMessage(title: "剪贴板历史", body: "已重新复制", detail: String(value.prefix(22)), duration: 4)
                fputs("interaction: single bubble clipboard-copy\n", stderr)
            } else if let threadID = taskAlertThreadID {
                onTaskAlertClicked?(threadID)
                fputs("interaction: task alert opened \(threadID)\n", stderr)
            } else {
                // The former DeepSeek-on-click behavior is intentionally gone.
                // A plain bubble click remains inert so it never starts network work.
                fputs("interaction: single bubble no-op\n", stderr)
            }
        case .mascot:
            fputs("interaction: single mascot\n", stderr)
            layeredRig?.tap(normalizedX: rigTapX)
            playTapSound()
            onMascotTap?()
            startJelly()
            registerTap()
            onInteraction?()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layeredRig?.onFrame = { [weak self] in guard let self, self.window?.isVisible == true else { return }; self.needsDisplay = true }
        layeredRig?.start()
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastInteractionAt) >= 15 else { return }
            self.lastInteractionAt = Date(); self.trigger(.idleFifteenSeconds)
        }
        hourlyTimer?.invalidate()
        hourlyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date(); let calendar = Calendar.current; let hour = calendar.component(.hour, from: now)
            guard calendar.component(.minute, from: now) == 0, self.lastHourlyGreetingHour != hour else { return }
            self.lastHourlyGreetingHour = hour; self.trigger(.hourlyGreeting)
            self.showMessage(title: "爱弥斯报时", body: "\(hour):00", detail: "整点也要记得喝口水呀")
        }
        scheduleAmbientVoice()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !chatExpanded else { super.rightMouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        showSettingsMenu(at: point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let mascotHeight: CGFloat = 154 * mascotSize
        emoticonView.isHidden = !emoticonShowing || chatExpanded || clipboardExpanded
        if !chatExpanded {
        let bubbleBase = mascotHeight - 1
        let rawBubbleRect = NSRect(x: mascotCenterX - 121 * bubbleSize, y: bubbleBase, width: 242 * bubbleSize, height: (clipboardExpanded ? 226 : 111) * bubbleSize)
        let bubbleRect = NSRect(x: rawBubbleRect.midX - rawBubbleRect.width * bubbleScaleX / 2,
                                y: rawBubbleRect.midY - rawBubbleRect.height * bubbleScaleY / 2 + bubbleYOffset,
                                width: rawBubbleRect.width * bubbleScaleX, height: rawBubbleRect.height * bubbleScaleY)
        let fill = themeColor.withAlphaComponent(bubbleOpacity)
        let outline = characterProfile.accent.withAlphaComponent(0.68)
        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 22, yRadius: 22)
        fill.setFill(); bubble.fill(); outline.setStroke(); bubble.lineWidth = 2.5; bubble.stroke()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: bubbleRect.midX - 16, y: bubbleRect.minY + 1)); tail.line(to: NSPoint(x: bubbleRect.midX, y: bubbleBase - 9)); tail.line(to: NSPoint(x: bubbleRect.midX + 13, y: bubbleRect.minY + 1)); tail.close(); fill.setFill(); tail.fill(); outline.setStroke(); tail.lineWidth = 2.5; tail.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let showingApp: Bool
        switch displayMode {
        case .automatic: showingApp = frontmostContext.map { !$0.isCodex } ?? false
        case .tokenOnly: showingApp = false
        case .appOnly: showingApp = frontmostContext != nil
        }
        if clipboardExpanded, !clipboardHistory.isEmpty {
            let selected = clipboardHistory[clipboardSelection]
            let header = "剪贴板历史  \(clipboardSelection + 1)/\(clipboardHistory.count)"
            let headerStyle = NSMutableParagraphStyle(); headerStyle.alignment = .center
            header.draw(in: NSRect(x: bubbleRect.minX + 14, y: bubbleRect.maxY - 34 * bubbleSize, width: bubbleRect.width - 28, height: 22 * bubbleSize), withAttributes: [.font: NSFont.systemFont(ofSize: 13 * bubbleSize, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.69, green: 0.26, blue: 0.43, alpha: 1), .paragraphStyle: headerStyle])
            let bodyStyle = NSMutableParagraphStyle(); bodyStyle.alignment = .left; bodyStyle.lineBreakMode = .byWordWrapping
            selected.draw(in: NSRect(x: bubbleRect.minX + 20, y: bubbleRect.minY + 43 * bubbleSize, width: bubbleRect.width - 40, height: bubbleRect.height - 86 * bubbleSize), withAttributes: [.font: NSFont.systemFont(ofSize: 13 * bubbleSize, weight: .medium), .foregroundColor: NSColor(calibratedRed: 0.34, green: 0.17, blue: 0.27, alpha: 1), .paragraphStyle: bodyStyle])
            "滚轮切换 · 点击重新复制".draw(in: NSRect(x: bubbleRect.minX + 14, y: bubbleRect.minY + 15 * bubbleSize, width: bubbleRect.width - 28, height: 18 * bubbleSize), withAttributes: [.font: NSFont.systemFont(ofSize: 10.5 * bubbleSize, weight: .medium), .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.66, blue: 0.73, alpha: 1), .paragraphStyle: headerStyle])
        } else if emoticonShowing {
            "让我想想".draw(in: NSRect(x: bubbleRect.minX + 13, y: bubbleRect.maxY - 25 * bubbleSize, width: bubbleRect.width - 26, height: 17 * bubbleSize), withAttributes: [.font: NSFont.systemFont(ofSize: 11 * bubbleSize, weight: .medium), .foregroundColor: characterProfile.accent, .paragraphStyle: paragraph])
            emoticonView.frame = NSRect(x: bubbleRect.minX + 16, y: bubbleRect.minY + 8 * bubbleSize, width: bubbleRect.width - 32, height: max(1,bubbleRect.height - 37 * bubbleSize))
        } else {
        let title: String
        let total: String
        let detail: String
        if let messageTitle, let messageBody, let messageDetail {
            title = messageTitle
            total = messageBody
            detail = messageDetail
        } else if showingNoMorePatMessage {
            title = "\(characterProfile.name)的请求"
            total = patMessage
            detail = String(format: "连点速度 %.1f 次/秒 · 5 秒后恢复", currentTapSpeed)
        } else if showingApp, let context = frontmostContext {
            let isBrowser = context.pageURL != nil || context.activity != "正在使用"
            title = isBrowser ? "\(context.activity) · \(context.appName)" : "正在使用"
            total = isBrowser ? context.activity : context.appName
            detail = showingTapSpeed ? String(format: "连点速度 %.1f 次/秒", currentTapSpeed) : (context.sourceLabel ?? "自动识别当前前台应用")
        } else {
            title = snapshot.map { "\($0.projectName) · Token" } ?? "Codex Token"
            total = snapshot.map { format($0.projectTokens) } ?? "读取中…"
            detail = showingTapSpeed ? String(format: "连点速度 %.1f 次/秒", currentTapSpeed) : (snapshot.map { "项目总消耗 · 当前任务 \(format($0.lastTokens))" } ?? "等待 Codex 项目记录")
        }
        let titleY = bubbleY(rawBubbleRect.maxY - 29 * bubbleSize, center: rawBubbleRect.midY)
        let visibleAccent = messageTitle == nil ? characterProfile.accent : (messageAccentColorOverride ?? characterProfile.accent)
        let visibleDetail = messageTitle == nil ? characterProfile.detail : (messageDetailColorOverride ?? characterProfile.detail)
        title.draw(in: NSRect(x: bubbleRect.minX + 13, y: titleY, width: bubbleRect.width - 26, height: 17 * bubbleSize * bubbleScaleY), withAttributes: [.font: NSFont.systemFont(ofSize: 13 * bubbleSize, weight: .semibold), .foregroundColor: visibleAccent, .paragraphStyle: paragraph])
        // AI 台词必须保持单行完整显示。中文、英文与标点的实际宽度并不
        // 等同于字符数，因此用 AppKit 真实测量文本，而不是用字符数猜字号。
        let isTemporaryMessage = messageBody != nil
        let textWidth = max(40, bubbleRect.width - 30)
        let totalFontSize: CGFloat = isTemporaryMessage
            ? fittedSingleLineFontSize(for: total, width: textWidth, maximum: 18 * bubbleSize, minimum: 8.5 * bubbleSize)
            : (showingApp ? 27 : 31) * bubbleSize
        total.draw(in: NSRect(x: bubbleRect.minX + 15, y: bubbleY(rawBubbleRect.minY + 40 * bubbleSize, center: rawBubbleRect.midY), width: textWidth, height: 39 * bubbleSize * bubbleScaleY), withAttributes: [.font: NSFont.systemFont(ofSize: totalFontSize, weight: .bold), .foregroundColor: visibleAccent, .paragraphStyle: paragraph])
        detail.draw(in: NSRect(x: bubbleRect.minX + 13, y: bubbleY(rawBubbleRect.minY + 17 * bubbleSize, center: rawBubbleRect.midY), width: bubbleRect.width - 26, height: 16 * bubbleSize * bubbleScaleY), withAttributes: [.font: NSFont.systemFont(ofSize: 11 * bubbleSize, weight: .medium), .foregroundColor: visibleDetail, .paragraphStyle: paragraph])
        }
        } else {
            // The expanded surface replaces the compact bubble. Only one shared
            // speech tail remains between that surface and the mascot.
            let fill = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.96, alpha: 0.985)
            let outline = NSColor(calibratedRed: 0.45, green: 0.86, blue: 0.90, alpha: 0.82)
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: mascotCenterX - 19, y: mascotHeight + 8))
            tail.line(to: NSPoint(x: mascotCenterX, y: mascotHeight - 8))
            tail.line(to: NSPoint(x: mascotCenterX + 19, y: mascotHeight + 8))
            tail.close(); fill.setFill(); tail.fill(); outline.setStroke(); tail.lineWidth = 1.5; tail.stroke()
        }
        // The selected round-head image is the single visual source of truth.
        // Interactions, AI replies and audio must never replace it temporarily.
        if selectedBuiltInMascotID == "aemis", UserDefaults.standard.string(forKey: "mascotPath") == nil, let rig = layeredRig {
            let h = 154 * mascotSize * mascotScaleY
            let w = 154 * mascotSize * 1214 / 960 * mascotScaleX
            rig.draw(in: NSRect(x: mascotCenterX-w/2, y: mascotYOffset, width: w, height: h))
        } else if let sourceMascot = mascot {
            let mascot = visibleMascotImage(from: sourceMascot)
            let h: CGFloat = 154 * mascotSize
            // 高度统一，宽图仅在固定舞台内收纳，避免偶发的横向大图显得更大。
            let naturalWidth = h * mascot.size.width / max(1, mascot.size.height)
            let fit = min(1, mascotStageWidth / max(1, naturalWidth))
            let w = naturalWidth * fit; let fittedHeight = h * fit
            let scaledW = w * mascotScaleX; let scaledH = fittedHeight * mascotScaleY
            mascot.draw(in: NSRect(x: mascotCenterX - scaledW / 2, y: mascotYOffset, width: scaledW, height: scaledH), from: .zero, operation: .sourceOver, fraction: 1)
        }
        let now = Date()
        if let startedAt = startupPulseStartedAt {
            let progress = min(1, max(0, now.timeIntervalSince(startedAt) / 0.85))
            if progress < 1 {
                let center = NSPoint(x: mascotCenterX, y: mascotAreaHeight * 0.48)
                let radius = (30 + 62 * CGFloat(progress)) * mascotSize
                let ringRect = NSRect(x: center.x - radius, y: center.y - radius * 0.62, width: radius * 2, height: radius * 1.24)
                let ring = NSBezierPath(ovalIn: ringRect)
                NSColor(calibratedRed: 1, green: 0.55, blue: 0.72, alpha: 0.78 * (1 - progress)).setStroke()
                ring.lineWidth = max(1.2, 3.2 * (1 - progress)); ring.stroke()
                let innerRadius = max(10, radius - 7 * mascotSize)
                let inner = NSBezierPath(ovalIn: NSRect(x: center.x - innerRadius, y: center.y - innerRadius * 0.62, width: innerRadius * 2, height: innerRadius * 1.24))
                NSColor.white.withAlphaComponent(0.58 * (1 - progress)).setStroke()
                inner.lineWidth = 1.2; inner.stroke()
            }
        }
        for particle in sparkleParticles {
            let progress = min(1, max(0, now.timeIntervalSince(particle.bornAt) / 1.15))
            guard progress < 1 else { continue }
            let x = particle.origin.x + particle.drift * CGFloat(sin(progress * .pi))
            let y = particle.origin.y + CGFloat(progress) * 64
            let scale = 1 - CGFloat(progress) * 0.35
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13 * scale, weight: .bold),
                .foregroundColor: particle.color.withAlphaComponent(1 - CGFloat(progress))
            ]
            particle.glyph.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
    }

    private func visibleMascotImage(from image: NSImage) -> NSImage {
        let key = ObjectIdentifier(image)
        if let cached = visibleMascotCache[key] { return cached }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = cgImage.width; let height = cgImage.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return image }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width; var maxX = -1; var minY = height; var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 10 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { visibleMascotCache[key] = image; return image }
        let inset = max(2, min(width, height) / 100)
        let originX = max(0, minX - inset); let originY = max(0, minY - inset)
        let endX = min(width, maxX + inset + 1); let endY = min(height, maxY + inset + 1)
        let rect = CGRect(x: originX, y: originY, width: endX - originX, height: endY - originY)
        guard let cropped = cgImage.cropping(to: rect) else { visibleMascotCache[key] = image; return image }
        let result = NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        visibleMascotCache[key] = result
        return result
    }
    private func showSettingsMenu(at point: NSPoint) {
        let menu = NSMenu(title: "爱弥斯")
        menu.autoenablesItems = false

        menu.addItem(withTitle: "AI 随机台词设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "立即让爱弥斯说一句", action: #selector(requestAIQuote), keyEquivalent: "")
        menu.addItem(menuItem(title: "实验功能", submenu: experimentalMenu()))
        menu.addItem(menuItem(title: "台词小工具", submenu: quoteToolsMenu()))
        menu.addItem(.separator())

        menu.addItem(menuItem(title: "角色与预设", submenu: characterMenu()))
        menu.addItem(menuItem(title: "随机表情", submenu: randomEmoticonMenu()))
        menu.addItem(menuItem(title: "互动与素材", submenu: interactionMenu()))
        menu.addItem(menuItem(title: "声音", submenu: audioMenu()))
        menu.addItem(menuItem(title: "显示与位置", submenu: appearanceMenu()))
        menu.addItem(menuItem(title: focusEndsAt == nil ? "专注与统计" : "专注中 · \(focusRemainingText)", submenu: focusAndStatsMenu()))
        menu.addItem(.separator())
        let positionItem = NSMenuItem(title: positionMemoryEnabled ? "✓ 位置记忆：已开启" : "位置记忆：已关闭", action: #selector(rememberPosition), keyEquivalent: "")
        positionItem.state = positionMemoryEnabled ? .on : .off; menu.addItem(positionItem)
        let savePositionItem = NSMenuItem(title: "将当前位置设为记忆点", action: #selector(saveCurrentPosition), keyEquivalent: "")
        savePositionItem.isEnabled = !chatExpanded; menu.addItem(savePositionItem)
        let positionHint = NSMenuItem(title: positionMemoryEnabled ? "拖动后停留 2 秒会缓动回到记忆点" : "开启后会记住当前点位", action: nil, keyEquivalent: ""); positionHint.isEnabled = false; menu.addItem(positionHint)
        menu.addItem(withTitle: "恢复默认外观", action: #selector(requestReset), keyEquivalent: "")
        prepareMenuItems(menu)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    private func menuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func characterMenu() -> NSMenu {
        let menu = NSMenu(title: "角色与预设")
        let mascotMenu = NSMenu(title: "选择人物")
        for (id, name) in [("aemis", "爱弥斯")] {
            let item = NSMenuItem(title: name, action: #selector(selectBuiltInMascot(_:)), keyEquivalent: "")
            item.representedObject = id
            item.state = selectedBuiltInMascotID == id ? .on : .off
            mascotMenu.addItem(item)
        }
        menu.addItem(menuItem(title: "选择人物", submenu: mascotMenu))
        menu.addItem(.separator())
        let presetMenu = NSMenu(title: "选择人物预设")
        for preset in presets {
            let item = NSMenuItem(title: preset.name, action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.representedObject = preset.id; presetMenu.addItem(item)
        }
        presetMenu.addItem(.separator())
        presetMenu.addItem(withTitle: "添加自定义人物预设…", action: #selector(savePreset), keyEquivalent: "")
        menu.addItem(menuItem(title: "选择人物预设", submenu: presetMenu))
        menu.addItem(withTitle: "将当前爱弥斯保存为预设…", action: #selector(savePreset), keyEquivalent: "")
        menu.addItem(withTitle: "导入人物预设包…", action: #selector(importPresetPack), keyEquivalent: "")
        menu.addItem(withTitle: "导出当前人物预设包…", action: #selector(exportPresetPack), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "更换透明 PNG 人物…", action: #selector(requestMascot), keyEquivalent: "")
        menu.addItem(withTitle: "聊天框颜色…", action: #selector(requestColor), keyEquivalent: "")
        return menu
    }

    private func interactionMenu() -> NSMenu {
        let menu = NSMenu(title: "互动与素材")
        menu.addItem(withTitle: "连点台词…", action: #selector(requestPatMessage), keyEquivalent: "")
        let fixedMascot = NSMenuItem(title: "✓ 固定圆脑袋图片", action: nil, keyEquivalent: "")
        fixedMascot.isEnabled = false; menu.addItem(fixedMascot)
        menu.addItem(menuItem(title: "点击特效", submenu: particleStyleMenu()))
        let ambient = NSMenuItem(title: ambientVoiceEnabled ? "AI 偶尔说话：已开启" : "AI 偶尔说话：已关闭", action: #selector(toggleAmbientQuote), keyEquivalent: "")
        ambient.state = ambientVoiceEnabled ? .on : .off; menu.addItem(ambient)
        menu.addItem(menuItem(title: "偶尔说话间隔", submenu: ambientIntervalMenu()))
        menu.addItem(.separator())
        let interactionItem = NSMenuItem(title: "今日已互动 \(todayInteractions) 次", action: nil, keyEquivalent: ""); interactionItem.isEnabled = false
        let bestSpeed = NSMenuItem(title: String(format: "本次运行最高连点 %.1f 次/秒", lastTapSpeed), action: nil, keyEquivalent: ""); bestSpeed.isEnabled = false
        menu.addItem(interactionItem)
        menu.addItem(bestSpeed)
        return menu
    }

    private func quoteToolsMenu() -> NSMenu {
        let menu = NSMenu(title: "台词小工具")
        let repeatLast = NSMenuItem(title: "重新显示上一句", action: #selector(showLastQuote), keyEquivalent: "")
        let copy = NSMenuItem(title: "复制当前台词", action: #selector(copyCurrentQuote), keyEquivalent: "")
        let favorite = NSMenuItem(title: "收藏当前台词", action: #selector(favoriteCurrentQuote), keyEquivalent: "")
        repeatLast.isEnabled = lastAIQuote != nil; copy.isEnabled = lastAIQuote != nil; favorite.isEnabled = lastAIQuote != nil
        menu.addItem(repeatLast); menu.addItem(copy); menu.addItem(favorite)
        let random = NSMenuItem(title: "从收藏中随机一句（\(favoriteQuotes.count)）", action: #selector(showFavoriteQuote), keyEquivalent: "")
        random.isEnabled = !favoriteQuotes.isEmpty; menu.addItem(random)
        let clear = NSMenuItem(title: "清空收藏台词", action: #selector(clearFavoriteQuotes), keyEquivalent: "")
        clear.isEnabled = !favoriteQuotes.isEmpty; menu.addItem(clear)
        menu.addItem(.separator())
        let copyContext = NSMenuItem(title: "复制当前软件信息", action: #selector(copyCurrentContext), keyEquivalent: "")
        copyContext.isEnabled = frontmostContext != nil; menu.addItem(copyContext)
        menu.addItem(.separator())
        let paused = quotePauseUntil.map { $0 > Date() } ?? false
        menu.addItem(withTitle: paused ? "恢复偶尔说话" : "安静一小时", action: #selector(toggleQuotePause), keyEquivalent: "")
        return menu
    }

    private func experimentalMenu() -> NSMenu {
        let menu = NSMenu(title: "实验功能")
        let vision = NSMenuItem(title: visualContextEnabled ? "读取当前窗口：已开启" : "读取当前窗口：已关闭", action: #selector(toggleVisualContext), keyEquivalent: "")
        vision.state = visualContextEnabled ? .on : .off; menu.addItem(vision)
        let tts = NSMenuItem(title: experimentalTTSEnabled ? "Pinokio 千问 TTS：已开启" : "Pinokio 千问 TTS：已关闭", action: #selector(toggleExperimentalTTS), keyEquivalent: "")
        tts.state = experimentalTTSEnabled ? .on : .off; menu.addItem(tts)
        let reliability = NSMenuItem(title: "本次窗口读取 \(visualSuccessCount) 次 · 自动降级 \(visualFallbackCount) 次", action: nil, keyEquivalent: "")
        reliability.isEnabled = false; menu.addItem(reliability)
        let hint = NSMenuItem(title: "气泡内滚动：查看剪贴板历史", action: nil, keyEquivalent: ""); hint.isEnabled = false; menu.addItem(hint)
        return menu
    }

    private func particleStyleMenu() -> NSMenu {
        let menu = NSMenu(title: "点击特效")
        for style in ParticleStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(setParticleStyle(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue; item.state = particleStyle == style ? .on : .off; menu.addItem(item)
        }
        return menu
    }

    private func ambientIntervalMenu() -> NSMenu {
        let menu = NSMenu(title: "偶尔说话间隔")
        for minutes in [5, 10, 15, 30, 60] {
            let item = NSMenuItem(title: "约 (minutes) 分钟", action: #selector(setAmbientInterval(_:)), keyEquivalent: "")
            item.representedObject = minutes; item.state = ambientVoiceIntervalMinutes == minutes ? .on : .off; menu.addItem(item)
        }
        return menu
    }

    private func audioMenu() -> NSMenu {
        let menu = NSMenu(title: "声音")
        let soundItem = NSMenuItem(title: clickSoundEnabled ? "点击音效：已开启" : "点击音效：已关闭", action: #selector(toggleClickSound), keyEquivalent: "")
        soundItem.state = clickSoundEnabled ? .on : .off; menu.addItem(soundItem)
        menu.addItem(menuItem(title: "点击音效类型", submenu: tapSoundMenu()))
        let volumeTitle = NSMenuItem(title: "音量 \(Int(soundVolume * 100))%", action: nil, keyEquivalent: ""); volumeTitle.isEnabled = false; soundVolumeLabel = volumeTitle; menu.addItem(volumeTitle)
        let slider = NSSlider(value: Double(soundVolume), minValue: 0, maxValue: 1, target: self, action: #selector(soundVolumeChanged(_:)))
        slider.isContinuous = true; slider.frame = NSRect(x: 12, y: 0, width: 170, height: 22)
        let sliderItem = NSMenuItem(); sliderItem.view = slider; menu.addItem(sliderItem)
        menu.addItem(.separator())
        let taskSettings = CodexTaskAlertSettings.load()
        let alertTitle = NSMenuItem(title: "语音音量 \(Int((taskSettings.volume * 100).rounded()))%（0–200%）", action: nil, keyEquivalent: "")
        alertTitle.isEnabled = false; taskAlertVolumeLabel = alertTitle; menu.addItem(alertTitle)
        let alertSlider = NSSlider(value: Double(taskSettings.volume), minValue: 0, maxValue: 2, target: self, action: #selector(taskAlertVolumeChanged(_:)))
        alertSlider.isContinuous = true; alertSlider.frame = NSRect(x: 12, y: 0, width: 170, height: 22)
        let alertSliderItem = NSMenuItem(); alertSliderItem.view = alertSlider; menu.addItem(alertSliderItem)
        menu.addItem(withTitle: "试听完成播报", action: #selector(previewTaskComplete), keyEquivalent: "")
        menu.addItem(withTitle: "试听问题播报", action: #selector(previewTaskProblem), keyEquivalent: "")
        return menu
    }

    private func tapSoundMenu() -> NSMenu {
        let menu = NSMenu(title: "点击音效类型")
        for sound in TapSound.allCases {
            let item = NSMenuItem(title: sound.title, action: #selector(setTapSound(_:)), keyEquivalent: "")
            item.representedObject = sound.rawValue; item.state = tapSound == sound ? .on : .off; menu.addItem(item)
        }
        menu.addItem(.separator()); menu.addItem(withTitle: "导入 15 秒以内音效…", action: #selector(requestCustomSound), keyEquivalent: "")
        return menu
    }


    private func appearanceMenu() -> NSMenu {
        let menu = NSMenu(title: "显示与位置")
        mascotSizeLabel = addSizeSlider(title: "人物大小 \(Int(mascotSize * 100))%", value: mascotSize, action: #selector(mascotSizeChanged(_:)), to: menu)
        bubbleSizeLabel = addSizeSlider(title: "聊天框大小 \(Int(bubbleSize * 100))%", value: bubbleSize, action: #selector(bubbleSizeChanged(_:)), to: menu)
        bubbleOpacityLabel = addSlider(title: "气泡透明度 \(Int(bubbleOpacity * 100))%", value: bubbleOpacity, min: 0.35, max: 1, action: #selector(bubbleOpacityChanged(_:)), to: menu)
        let modeMenu = NSMenu(title: "显示模式")
        for (title, mode) in [("自动切换", DisplayMode.automatic), ("始终显示 Token", DisplayMode.tokenOnly), ("始终显示前台软件", DisplayMode.appOnly)] {
            let item = NSMenuItem(title: title, action: #selector(setDisplayMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue; item.state = displayMode == mode ? .on : .off; modeMenu.addItem(item)
        }
        menu.addItem(menuItem(title: "显示内容", submenu: modeMenu))
        let dockMenu = NSMenu(title: "位置吸附")
        for position in [DockPosition.bottomRight, .bottomLeft, .topRight, .topLeft] {
            let item = NSMenuItem(title: position.title, action: #selector(dockPosition(_:)), keyEquivalent: ""); item.representedObject = position.rawValue; dockMenu.addItem(item)
        }
        menu.addItem(menuItem(title: "位置吸附", submenu: dockMenu))
        return menu
    }

    private func focusAndStatsMenu() -> NSMenu {
        let menu = NSMenu(title: "专注与统计")
        menu.addItem(withTitle: "开始 25/50 分钟专注…", action: #selector(startFocus), keyEquivalent: "")
        let stop = NSMenuItem(title: "结束本次专注", action: #selector(stopFocus), keyEquivalent: ""); stop.isEnabled = focusEndsAt != nil; menu.addItem(stop)
        menu.addItem(.separator())
        let interactionItem = NSMenuItem(title: "今日已互动 \(todayInteractions) 次", action: nil, keyEquivalent: ""); interactionItem.isEnabled = false; menu.addItem(interactionItem)
        let bestSpeed = NSMenuItem(title: String(format: "本次运行最高连点 %.1f 次/秒", lastTapSpeed), action: nil, keyEquivalent: ""); bestSpeed.isEnabled = false; menu.addItem(bestSpeed)
        return menu
    }

    // This borderless, non-activating panel is deliberately not key. Assigning the
    // menu target explicitly prevents AppKit from disabling every action item.
    private func prepareMenuItems(_ menu: NSMenu) {
        menu.autoenablesItems = false
        for item in menu.items {
            if item.action != nil { item.target = self }
            if item.submenu != nil { item.isEnabled = true; prepareMenuItems(item.submenu!) }
        }
    }
    @objc private func requestMascot() { onChooseMascot?() }
    @objc private func requestColor() { onChooseColor?() }
    @objc private func requestAIQuote() { onAIQuoteRequested?() }
    @objc private func copyCurrentQuote() {
        guard let lastAIQuote else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lastAIQuote, forType: .string)
        showMessage(title: "台词已复制", body: lastAIQuote, detail: "可以粘贴到别处啦", duration: 3)
    }
    @objc private func showLastQuote() {
        guard let lastAIQuote else { return }
        showMessage(title: "\(characterProfile.name)上次说", body: lastAIQuote, detail: "重新给你看一遍 ✦", duration: 8)
    }
    @objc private func favoriteCurrentQuote() {
        guard let lastAIQuote, !favoriteQuotes.contains(lastAIQuote) else { return }
        favoriteQuotes.append(lastAIQuote); UserDefaults.standard.set(favoriteQuotes, forKey: "favoriteAIQuotes")
        showMessage(title: "已收藏", body: lastAIQuote, detail: "收进爱弥斯的小口袋了", duration: 3)
    }
    @objc private func showFavoriteQuote() {
        guard let quote = favoriteQuotes.randomElement() else { return }
        showMessage(title: "收藏的台词", body: quote, detail: "又想起这句话啦", duration: 7)
    }
    @objc private func clearFavoriteQuotes() {
        favoriteQuotes.removeAll(); UserDefaults.standard.removeObject(forKey: "favoriteAIQuotes")
        showMessage(title: "台词收藏", body: "已经清空啦", detail: "之后还可以重新收藏", duration: 3)
    }
    @objc private func copyCurrentContext() {
        guard let context = frontmostContext else { return }
        let value = [context.appName, context.windowTitle, context.pageURL].compactMap { $0 }.joined(separator: " · ")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        showMessage(title: "当前软件信息", body: "已复制", detail: String(value.prefix(26)), duration: 4)
    }
    @objc private func toggleQuotePause() {
        if let until = quotePauseUntil, until > Date() { quotePauseUntil = nil; scheduleAmbientVoice(); showMessage(title: "爱弥斯", body: "我回来陪你啦", detail: "偶尔说话已经恢复", duration: 4) }
        else { quotePauseUntil = Date().addingTimeInterval(3600); ambientVoiceTimer?.invalidate(); showMessage(title: "爱弥斯", body: "那我先安静一会儿", detail: "一小时后自动恢复", duration: 4) }
    }
    @objc private func toggleVisualContext() { visualContextEnabled.toggle(); UserDefaults.standard.set(visualContextEnabled, forKey: "visualContextEnabled"); needsDisplay = true }
    @objc private func toggleExperimentalTTS() { experimentalTTSEnabled.toggle(); UserDefaults.standard.set(experimentalTTSEnabled, forKey: "experimentalTTSEnabled"); needsDisplay = true }
    @objc private func toggleAmbientQuote() { configureAmbientVoice(enabled: !ambientVoiceEnabled, intervalMinutes: ambientVoiceIntervalMinutes); UserDefaults.standard.set(ambientVoiceEnabled, forKey: "ambientVoiceEnabled") }
    @objc private func setAmbientInterval(_ sender: NSMenuItem) { guard let minutes = sender.representedObject as? Int else { return }; ambientVoiceIntervalMinutes = minutes; UserDefaults.standard.set(minutes, forKey: "ambientVoiceIntervalMinutes"); scheduleAmbientVoice() }
    @objc private func setParticleStyle(_ sender: NSMenuItem) { guard let raw = sender.representedObject as? String, let style = ParticleStyle(rawValue: raw) else { return }; particleStyle = style; UserDefaults.standard.set(raw, forKey: "particleStyle") }
    @objc private func toggleClickSound() { onToggleClickSound?() }
    @objc private func setTapSound(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let sound = TapSound(rawValue: raw) { onSetTapSound?(sound) } }
    @objc private func soundVolumeChanged(_ sender: NSSlider) { soundVolumeLabel?.title = "音量 \(Int(sender.floatValue * 100))%"; onSetSoundVolume?(sender.floatValue) }
    @objc private func taskAlertVolumeChanged(_ sender: NSSlider) {
        taskAlertVolumeLabel?.title = "语音音量 \(Int((sender.floatValue * 100).rounded()))%（0–200%）"
        onSetTaskAlertVolume?(sender.floatValue)
    }
    @objc private func previewTaskComplete() { onPreviewTaskAlert?(.complete) }
    @objc private func previewTaskProblem() { onPreviewTaskAlert?(.problem) }
    @objc private func mascotSizeChanged(_ sender: NSSlider) { mascotSizeLabel?.title = "人物大小 \(Int(sender.doubleValue * 100))%"; onSetMascotSize?(CGFloat(sender.doubleValue)) }
    @objc private func bubbleSizeChanged(_ sender: NSSlider) { bubbleSizeLabel?.title = "聊天框大小 \(Int(sender.doubleValue * 100))%"; onSetBubbleSize?(CGFloat(sender.doubleValue)) }
    @objc private func bubbleOpacityChanged(_ sender: NSSlider) { bubbleOpacityLabel?.title = "气泡透明度 \(Int(sender.doubleValue * 100))%"; onSetBubbleOpacity?(CGFloat(sender.doubleValue)) }
    @objc private func requestCustomSound() { onChooseCustomSound?() }
    @objc private func requestPatMessage() { onSetPatMessage?() }
    @objc private func importClickSounds() { onImportClickSounds?() }
    @objc private func importEventSounds() { onImportEventSounds?() }
    @objc private func savePreset() { onSavePreset?() }
    @objc private func importPresetPack() { onImportPresetPack?() }
    @objc private func exportPresetPack() { onExportPresetPack?() }
    @objc private func applyPreset(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onApplyPreset?(id) } }
    @objc private func selectBuiltInMascot(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onSelectBuiltInMascot?(id) } }
    @objc private func rememberPosition() { onRememberPosition?() }
    @objc private func saveCurrentPosition() { onSaveCurrentPosition?() }
    @objc private func dockPosition(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let position = DockPosition(rawValue: raw) { onDockPosition?(position) } }
    @objc private func requestReset() { onResetAppearance?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openChat() { onOpenChat?() }
    @objc private func startFocus() { onStartFocus?() }
    @objc private func stopFocus() { onStopFocus?() }
    @objc private func setMascotSize(_ sender: NSMenuItem) { if let value = sender.representedObject as? CGFloat { onSetMascotSize?(value) } }
    @objc private func setDisplayMode(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) { onSetDisplayMode?(mode) } }
    func setChatExpanded(_ expanded: Bool, store: AemisConversationStore? = nil, presetID: String = "default", onWidthChanged: ((CGFloat) -> Void)? = nil, onHeightGrowthRequested: ((CGFloat) -> Void)? = nil) {
        guard expanded != chatExpanded else { return }
        chatExpanded = expanded
        if expanded, let store {
            let chat = AemisBubbleChatView(store: store, presetID: presetID); chat.alphaValue = 0; chat.translatesAutoresizingMaskIntoConstraints = false
            chat.onDismiss = { [weak self] in self?.onOpenChat?() }
            chat.onWidthChanged = onWidthChanged
            chat.onHeightGrowthRequested = onHeightGrowthRequested
            addSubview(chat); embeddedChat = chat
            NSLayoutConstraint.activate([
                chat.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                chat.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                chat.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                chat.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(mascotAreaHeight + 6))
            ])
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.22; chat.animator().alphaValue = 1 }
        } else if let chat = embeddedChat {
            // Remove the expanded view and its constraints before shrinking the
            // host panel. Leaving it attached during a fade keeps its minimum
            // layout size active and AppKit immediately expands the supposedly
            // compact window again, stranding the mascot below the display.
            chat.removeFromSuperview()
            embeddedChat = nil
        }
        needsDisplay = true
    }
    func focusChatInput() { embeddedChat?.focusInput() }
    private func bubbleY(_ y: CGFloat, center: CGFloat) -> CGFloat { center + (y - center) * bubbleScaleY + bubbleYOffset }
    private func format(_ value: Int) -> String { value >= 1_000_000 ? String(format: "%.2fM", Double(value) / 1_000_000) : value >= 1_000 ? String(format: "%.1fK", Double(value) / 1_000) : "\(value)" }

    private func fittedSingleLineFontSize(for text: String, width: CGFloat, maximum: CGFloat, minimum: CGFloat) -> CGFloat {
        var low = minimum
        var high = maximum
        for _ in 0..<10 {
            let candidate = (low + high) / 2
            let measured = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: candidate, weight: .bold)]).width
            if measured <= width { low = candidate } else { high = candidate }
        }
        return low
    }

    private func playTapSound() {
        guard clickSoundEnabled else { return }
        playSystemSound(path: clickSoundPaths.randomElement() ?? selectedClickSoundPath, volume: soundVolume)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            guard let self, self.clickSoundEnabled else { return }
            self.playSystemSound(path: self.clickSoundPaths.randomElement() ?? self.selectedClickSoundPath, volume: self.soundVolume * 0.72)
        }
    }

    private var selectedClickSoundPath: String? { tapSound == .custom ? customSoundPath : tapSound.filePath }
    @discardableResult private func playSystemSound(path: String?, volume: Float, isVoice: Bool = false) -> Bool {
        guard let path else { return false }
        legacyAudioPlayers.removeAll { !$0.isPlaying }
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.volume = max(0,min(1,volume)); player.prepareToPlay()
            if isVoice { layeredRig?.track(player) }
            legacyAudioPlayers.append(player)
            let started = player.play()
            fputs("pet-audio: file=\(URL(fileURLWithPath:path).lastPathComponent) duration=\(player.duration) started=\(started)\n",stderr)
            return started
        } catch { return false }
    }

    func reactToTaskAlert(playClick: Bool) {
        jellyTimer?.invalidate()
        let startedAt = Date()
        jellyTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, Date().timeIntervalSince(startedAt) / 0.52)
            if progress >= 1 {
                self.mascotYOffset = 0; self.mascotScaleX = 1; self.mascotScaleY = 1
                self.needsDisplay = true; timer.invalidate(); return
            }
            let hop = max(0, sin(progress * .pi))
            self.mascotYOffset = 24 * hop
            self.mascotScaleX = 1 - 0.06 * hop
            self.mascotScaleY = 1 + 0.10 * hop
            self.needsDisplay = true
        }
        let path = clickSoundPaths.randomElement() ?? selectedClickSoundPath
        let volume = min(0.32, soundVolume * 0.4)
        let started = playClick && volume > 0 && playSystemSound(path: path, volume: volume)
        fputs("task-alert: reaction jump=true click=\(started) volume=\(volume)\n", stderr)
    }

    func stopLegacyAudioPlayback() {
        legacyAudioPlayers.forEach { $0.stop() }; legacyAudioPlayers.removeAll()
        for process in legacySoundProcesses where process.isRunning { process.terminate() }
        legacySoundProcesses.removeAll()
    }

    func verifyMascotClick() {
        guard let window else { return }
        let point = convert(NSPoint(x:mascotCenterX,y:mascotAreaHeight*0.5),to:nil)
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            if let event = NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1) {
                if type == .leftMouseDown { mouseDown(with:event) } else { mouseUp(with:event) }
            }
        }
    }

    private func registerTap() {
        guard !showingNoMorePatMessage else { return }
        let now = Date()
        lastInteractionAt = now; recentTapTimes.append(now)
        recentTapTimes.removeAll { now.timeIntervalSince($0) > 3 }
        tapSessionResetTimer?.invalidate()
        tapSessionResetTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.resetTapSession() }
        spawnSparkles(at: now)
        if recentTapTimes.count >= 2 {
            showingTapSpeed = true; tapSpeedDismissTimer?.invalidate()
            tapSpeedDismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.showingTapSpeed = false; self?.needsDisplay = true }
            needsDisplay = true
        }
        if recentTapTimes.count >= 2, firedTapTriggers.insert(.doubleTap).inserted { trigger(.doubleTap) }
        if recentTapTimes.count >= 3, firedTapTriggers.insert(.tripleTaps).inserted { trigger(.tripleTaps) }
        if recentTapTimes.count >= 5, firedTapTriggers.insert(.fiveTaps).inserted { trigger(.fiveTaps) }
        if recentTapTimes.count >= 10, firedTapTriggers.insert(.tenTaps).inserted { trigger(.tenTaps) }
        guard recentTapTimes.count >= 15 else { return }
        if firedTapTriggers.insert(.fifteenTaps).inserted { trigger(.fifteenTaps) }
        lastTapSpeed = max(lastTapSpeed, currentTapSpeed); showingNoMorePatMessage = true; needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }; self.showingNoMorePatMessage = false; self.resetTapSession(); self.needsDisplay = true
        }
    }

    private func resetTapSession() {
        recentTapTimes.removeAll(); firedTapTriggers.removeAll(); tapSessionResetTimer?.invalidate(); tapSessionResetTimer = nil
    }

    private func spawnSparkles(at now: Date) {
        guard !particleStyle.glyphs.isEmpty else { return }
        let colors: [NSColor] = [.systemYellow, .systemPink, .systemTeal, NSColor(calibratedRed: 0.94, green: 0.75, blue: 1, alpha: 1)]
        let glyphs = particleStyle.glyphs
        let centerX = mascotCenterX
        for index in 0..<5 {
            let angle = CGFloat(index) / 5 * .pi * 2
            let radius: CGFloat = index.isMultiple(of: 2) ? 38 : 54
            sparkleParticles.append(SparkleParticle(glyph: glyphs[index % glyphs.count], color: colors[index % colors.count], origin: NSPoint(x: centerX + cos(angle) * radius, y: 58 + sin(angle) * 20), drift: cos(angle) * 22, bornAt: now))
        }
        sparkleParticles.removeAll { now.timeIntervalSince($0.bornAt) > 1.15 }
        startSparkleTimerIfNeeded()
    }

    private func spawnStartupSparkles(at now: Date, count: Int) {
        let colors: [NSColor] = [.systemPink, .white, NSColor(calibratedRed: 1, green: 0.78, blue: 0.84, alpha: 1), .systemYellow]
        let glyphs = ["✦", "✧", "⋆"]
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(max(1, count)) * .pi * 2
            let radius: CGFloat = index.isMultiple(of: 2) ? 40 : 56
            sparkleParticles.append(SparkleParticle(glyph: glyphs[index % glyphs.count], color: colors[index % colors.count], origin: NSPoint(x: mascotCenterX + cos(angle) * radius, y: 62 + sin(angle) * 24), drift: cos(angle) * 24, bornAt: now))
        }
        sparkleParticles.removeAll { now.timeIntervalSince($0.bornAt) > 1.15 }
        startSparkleTimerIfNeeded()
    }

    private func startSparkleTimerIfNeeded() {
        guard sparkleTimer == nil else { return }
        sparkleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.sparkleParticles.removeAll { Date().timeIntervalSince($0.bornAt) > 1.15 }
            self.needsDisplay = true
            if self.sparkleParticles.isEmpty { timer.invalidate(); self.sparkleTimer = nil }
        }
    }

    private func startStartupPulse() {
        startupPulseStartedAt = Date()
        startupPulseTimer?.invalidate()
        startupPulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, let startedAt = self.startupPulseStartedAt else { timer.invalidate(); return }
            if Date().timeIntervalSince(startedAt) >= 0.85 {
                self.startupPulseStartedAt = nil
                self.startupPulseTimer = nil
                self.needsDisplay = true
                timer.invalidate()
            } else {
                self.needsDisplay = true
            }
        }
    }

    func showStartupPhase(_ phase: String) {
        guard ["requested", "visible", "completed", "failed"].contains(phase) else { return }
        startupPhaseQueue.append(phase)
        presentNextStartupPhaseIfNeeded()
    }

    private func presentNextStartupPhaseIfNeeded() {
        guard !isPresentingStartupPhase, !startupPhaseQueue.isEmpty else { return }
        isPresentingStartupPhase = true
        let phase = startupPhaseQueue.removeFirst()
        let profile = characterProfile
        let now = Date()
        switch phase {
        case "requested":
            startJelly(); spawnStartupSparkles(at: now, count: 3)
            showMessage(title: profile.name, body: "共鸣通道准备中…", detail: "正在连接 Codex ✦", duration: 3.2)
        case "visible":
            startJelly(); startStartupPulse(); spawnStartupSparkles(at: now, count: 8)
            showMessage(title: profile.name, body: "启动动画已接入 Codex", detail: "窗口联动成功 ✦", duration: 3.2)
        case "completed":
            startJelly(); spawnStartupSparkles(at: now, count: 7)
            showMessage(title: profile.name, body: "Codex 已就绪 ✦", detail: "可以开始啦", duration: 2.4)
        case "failed":
            showMessage(title: profile.name, body: "连接没有完成", detail: "再双击气泡试试", duration: 3.4)
        default:
            break
        }
        if ["requested", "visible", "completed", "failed"].contains(phase) {
            messageAccentColorOverride = NSColor(calibratedRed: 0.84, green: 0.25, blue: 0.47, alpha: 1)
            messageDetailColorOverride = NSColor(calibratedRed: 0.68, green: 0.31, blue: 0.40, alpha: 1)
            needsDisplay = true
        }
        let minimumHold: TimeInterval
        switch phase {
        case "requested": minimumHold = 1.6
        case "visible": minimumHold = 2.0
        case "completed": minimumHold = 2.4
        default: minimumHold = 3.0
        }
        startupPhasePresentationTimer?.invalidate()
        startupPhasePresentationTimer = Timer.scheduledTimer(withTimeInterval: minimumHold, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.isPresentingStartupPhase = false
            self.presentNextStartupPhaseIfNeeded()
        }
    }

    var focusRemainingText: String {
        guard let end = focusEndsAt else { return "未开始" }
        let seconds = max(0, Int(end.timeIntervalSinceNow)); return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func showMessage(title: String, body: String, detail: String, duration: TimeInterval = 5) {
        clearEmoticon()
        if title.hasSuffix("想说") { lastAIQuote = body }
        taskAlertThreadID = nil
        messageAccentColorOverride = nil; messageDetailColorOverride = nil
        messageTitle = title; messageBody = body; messageDetail = detail; messageTimer?.invalidate(); needsDisplay = true
        messageTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.messageTitle = nil; self?.messageBody = nil; self?.messageDetail = nil
            self?.taskAlertThreadID = nil
            self?.messageAccentColorOverride = nil; self?.messageDetailColorOverride = nil; self?.needsDisplay = true
        }
    }

    func showTaskAlert(_ alert: CodexTaskAlert) {
        let body = alert.kind == .complete ? (alert.reason == "本轮回复已完成" ? "本轮回复完成啦" : "你的任务完成啦") : alert.reason
        showMessage(title: "任务提醒", body: body, detail: "点击查看对应任务", duration: 22)
        taskAlertThreadID = alert.threadID
    }

    /// Used while an asynchronous request is active. A fixed-duration message
    /// can expire before the network reply and make the bubble jump back to its
    /// Token screen even though the pet is still thinking.
    func showPersistentMessage(title: String, body: String, detail: String) {
        clearEmoticon()
        taskAlertThreadID = nil
        messageTimer?.invalidate(); messageTimer = nil
        messageAccentColorOverride = nil; messageDetailColorOverride = nil
        messageTitle = title; messageBody = body; messageDetail = detail; needsDisplay = true
    }

    func configureRandomEmoticons() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = ["Desktop/爱弥斯/图片/桌宠表情包_20260822", "Desktop/爱弥斯/爱弥斯演唱会捏捏-gif"]
        let bundled = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("assets/emoticons")
        let localURLs = (try? FileManager.default.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil)) ?? []
        emoticonURLs = (localURLs + folders.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent(folder), includingPropertiesForKeys: nil)) ?? []
        }).filter { ["png","jpg","jpeg","gif"].contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path }
        emoticonView.imageScaling = .scaleProportionallyUpOrDown
        emoticonView.animates = true; emoticonView.isHidden = true
        addSubview(emoticonView)
        scheduleEmoticon()
    }
    private func scheduleEmoticon() {
        emoticonTimer?.invalidate(); emoticonTimer = nil
        let frequency = UserDefaults.standard.object(forKey: "randomEmoticonMinutes") == nil ? 15 : UserDefaults.standard.integer(forKey: "randomEmoticonMinutes")
        guard frequency > 0, !emoticonURLs.isEmpty else { return }
        let delay = Double(frequency * 60) * Double.random(in: 0.7...1.3)
        emoticonTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.showRandomEmoticon(); self?.scheduleEmoticon()
        }
    }
    @objc func showRandomEmoticon() {
        guard selectedBuiltInMascotID == "aemis", messageTitle == nil, taskAlertThreadID == nil,
              !chatExpanded, !clipboardExpanded, !showingNoMorePatMessage else { return }
        let candidates = emoticonURLs.filter { $0 != lastEmoticonURL }
        guard let url = (candidates.isEmpty ? emoticonURLs : candidates).randomElement(), let image = NSImage(contentsOf: url) else { return }
        lastEmoticonURL = url; emoticonView.image = image; emoticonView.isHidden = false
        emoticonShowing = true; needsDisplay = true
        emoticonDismissTimer?.invalidate()
        emoticonDismissTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in self?.clearEmoticon() }
        fputs("emoticon: shown file=\(url.lastPathComponent)\n", stderr)
    }
    func verifyEmoticonBehavior() {
        guard messageTitle == nil, taskAlertThreadID == nil else { return }
        let d = UserDefaults.standard, saved = d.object(forKey:"randomEmoticonMinutes")
        defer { if let saved { d.set(saved,forKey:"randomEmoticonMinutes") } else { d.removeObject(forKey:"randomEmoticonMinutes") }; d.synchronize(); scheduleEmoticon() }
        clearEmoticon(); showRandomEmoticon(); let first = lastEmoticonURL
        clearEmoticon(); showRandomEmoticon(); let different = first != lastEmoticonURL
        let alert = CodexTaskAlert(key:"local-preview",threadID:UUID().uuidString,kind:.complete,reason:"本轮回复已完成",title:"验证",project:"",timestamp:Date().timeIntervalSince1970)
        showTaskAlert(alert); let preempted = !emoticonShowing && emoticonView.isHidden
        showRandomEmoticon(); let protected = !emoticonShowing && taskAlertThreadID == alert.threadID
        messageTimer?.invalidate(); messageTimer = nil; messageTitle = nil; messageBody = nil; messageDetail = nil; taskAlertThreadID = nil; needsDisplay = true
        d.set(0,forKey:"randomEmoticonMinutes"); scheduleEmoticon(); let disabled = emoticonTimer == nil
        d.set(30,forKey:"randomEmoticonMinutes"); d.synchronize(); scheduleEmoticon()
        let delay = emoticonTimer?.fireDate.timeIntervalSinceNow ?? 0
        let report: [String:Any] = ["differentNextImage":different,"taskPreempts":preempted,"taskProtected":protected,"disabledStopsTimer":disabled,"persistedFrequency":d.integer(forKey:"randomEmoticonMinutes"),"scheduledDelay":delay,"delayInRange":delay >= 1260 && delay <= 2340]
        let folder = URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent()
        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:folder.appendingPathComponent("emoticon-verification.json")) }
    }
    func previewEmoticonAndCapture() {
        showRandomEmoticon()
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for (i, delay) in [0.3,0.8].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now()+delay) { [weak self] in
                guard let self, let bitmap = self.bitmapImageRepForCachingDisplay(in: self.bounds) else { return }
                self.cacheDisplay(in: self.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to:folder.appendingPathComponent("emoticon-preview-\(i).png")) }
                let report: [String:Any] = ["visible":self.emoticonShowing,"title":"让我想想","file":self.lastEmoticonURL?.path ?? "","pool":self.emoticonURLs.count,"frame":[self.emoticonView.frame.width,self.emoticonView.frame.height],"proportional":self.emoticonView.imageScaling == .scaleProportionallyUpOrDown,"animates":self.emoticonView.animates]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]) { try? data.write(to:folder.appendingPathComponent("emoticon-preview.json")) }
            }
        }
    }
    private func clearEmoticon() {
        emoticonShowing = false; emoticonView.isHidden = true; emoticonView.image = nil
        emoticonDismissTimer?.invalidate(); emoticonDismissTimer = nil; needsDisplay = true
    }
    private func randomEmoticonMenu() -> NSMenu {
        let menu = NSMenu(title: "随机表情")
        let current = UserDefaults.standard.object(forKey: "randomEmoticonMinutes") == nil ? 15 : UserDefaults.standard.integer(forKey: "randomEmoticonMinutes")
        for (minutes, title) in [(0,"关闭"),(5,"偶尔 · 随机 3.5–6.5 分钟"),(15,"适中 · 随机 10.5–19.5 分钟"),(30,"安静 · 随机 21–39 分钟"),(60,"稀疏 · 随机 42–78 分钟")] {
            let item = NSMenuItem(title: title, action: #selector(changeEmoticonFrequency(_:)), keyEquivalent: "")
            item.target = self; item.tag = minutes; item.state = current == minutes ? .on : .off; menu.addItem(item)
        }
        menu.addItem(.separator())
        let preview = NSMenuItem(title: "现在随机看一张", action: #selector(showRandomEmoticon), keyEquivalent: "")
        preview.target = self; preview.isEnabled = !emoticonURLs.isEmpty; menu.addItem(preview)
        return menu
    }
    @objc private func changeEmoticonFrequency(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "randomEmoticonMinutes")
        if sender.tag == 0 { clearEmoticon() }
        scheduleEmoticon()
    }

    func configureAmbientVoice(enabled: Bool, intervalMinutes: Int) {
        ambientVoiceEnabled = enabled
        ambientVoiceIntervalMinutes = max(3, min(120, intervalMinutes))
        scheduleAmbientVoice()
    }

    private func scheduleAmbientVoice() {
        ambientVoiceTimer?.invalidate()
        guard ambientVoiceEnabled else { ambientVoiceTimer = nil; return }
        if let until = quotePauseUntil, until > Date() {
            ambientVoiceTimer = Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow, repeats: false) { [weak self] _ in self?.quotePauseUntil = nil; self?.scheduleAmbientVoice() }
            return
        }
        // Each wait is lightly randomized so the companion feels occasional rather
        // than like an alarm. It never interrupts an active tapping session.
        let base = TimeInterval(ambientVoiceIntervalMinutes * 60)
        let wait = base * Double.random(in: 0.72...1.28)
        ambientVoiceTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.showingNoMorePatMessage, Date().timeIntervalSince(self.lastInteractionAt) >= 10 {
                self.onAIQuoteRequested?()
            }
            self.scheduleAmbientVoice()
        }
    }

    func trigger(_ trigger: InteractionTrigger) {
        let key = trigger.rawValue
        if selectedBuiltInMascotID == "aemis", trigger == .tenTaps {
            onTenTapVoiceRequested?()
            needsDisplay = true
            return
        }
        // Imported speaking clips belong to Aemis. Other built-in characters keep
        // their own text/persona and must never inherit Aemis' voice library.
        if selectedBuiltInMascotID == "aemis", let sound = eventSounds.filter({ $0.trigger == key }).randomElement() {
            if shouldPlayLegacyVoice?(trigger) != false {
                playSystemSound(path: sound.path, volume: soundVolume, isVoice: true)
            } else {
                fputs("legacy-voice: suppressed trigger=\(key)\n", stderr)
            }
        }
        needsDisplay = true
    }

    private var currentTapSpeed: Double {
        guard let first = recentTapTimes.first, let last = recentTapTimes.last else { return lastTapSpeed }
        return Double(recentTapTimes.count) / max(0.25, last.timeIntervalSince(first))
    }

    private func addSizeSlider(title: String, value: CGFloat, action: Selector, to menu: NSMenu) -> NSMenuItem {
        addSlider(title: title, value: value, min: 0.6, max: 1.5, action: action, to: menu)
    }
    private func addSlider(title: String, value: CGFloat, min: Double, max: Double, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let label = NSMenuItem(title: title, action: nil, keyEquivalent: ""); label.isEnabled = false; menu.addItem(label)
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true; slider.frame = NSRect(x: 12, y: 0, width: 170, height: 22)
        let item = NSMenuItem(); item.view = slider; menu.addItem(item)
        return label
    }

    private func startJelly() {
        jellyTimer?.invalidate()
        let startedAt = Date()
        jellyTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = Date().timeIntervalSince(startedAt)
            if t >= 0.62 {
                self.mascotScaleX = 1; self.mascotScaleY = 1; self.mascotYOffset = 0
                self.bubbleScaleX = 1; self.bubbleScaleY = 1; self.bubbleYOffset = 0
                self.needsDisplay = true; timer.invalidate(); return
            }
            // A playful two-bounce jelly spring, shared by the character and its speech bubble.
            let pulse = sin(t * .pi * 5.2) * exp(-4.7 * t)
            self.mascotScaleX = 1 + 0.12 * pulse
            self.mascotScaleY = 1 - 0.09 * pulse
            self.mascotYOffset = -13 * pulse
            self.bubbleScaleX = 1 + 0.065 * pulse
            self.bubbleScaleY = 1 - 0.048 * pulse
            self.bubbleYOffset = -5 * pulse
            self.needsDisplay = true
        }
    }
}

private final class AemisInteractivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private enum AemisSpeechEmotion: String, CaseIterable {
    case neutral, smile, happy, wink, surprised, confused, thinking, annoyed
    case sad, tearful, shy, speechless, sleepy, proud, nervous, poked, dislike, expecting
}

private struct AemisQuoteReview {
    let approved: Bool
    let emotion: AemisSpeechEmotion
    let reason: String
}

enum AemisPinokioTTS {
    private static let baseURL = URL(string: "http://127.0.0.1:42003")!
    private static let preferredVoiceName = "芊略"
    private static let apiKey = "your-api-key-1"

    static func synthesize(text: String, completion: @escaping (Result<Data, Error>) -> Void) {
        var promptsRequest = URLRequest(url: baseURL.appendingPathComponent("api/v1/base/prompts"))
        promptsRequest.timeoutInterval = 4
        URLSession.shared.dataTask(with: promptsRequest) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let prompts = root["prompts"] as? [[String: Any]],
                  let promptID = prompts.first(where: { ($0["name"] as? String) == preferredVoiceName })?["prompt_id"] as? String else {
                completion(.failure(NSError(domain: "AemisTTS", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有找到“芊略”音色。"])))
                return
            }
            let endpoint = baseURL.appendingPathComponent("api/v1/base/generate-with-prompt")
            var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt_id": promptID, "text": text, "language": "Chinese", "speed": 1.0, "response_format": "base64"])
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { completion(.failure(error)); return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let data,
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let encoded = root["audio"] as? String,
                      let audio = Data(base64Encoded: encoded), !audio.isEmpty else {
                    completion(.failure(NSError(domain: "AemisTTS", code: status, userInfo: [NSLocalizedDescriptionKey: "千问 TTS 没有返回可播放音频。"])))
                    return
                }
                completion(.success(audio))
            }.resume()
        }.resume()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct CachedMascotVoiceClip { let text: String; let url: URL }
    private let reader = UsageReader(); private let frontmostAppReader = FrontmostAppReader(); private let conversationStore = AemisConversationStore(); private var panel: NSPanel!; private var bubble: BubbleView!; private var timer: Timer?; private var focusTimer: Timer?; private var statusItem: NSStatusItem!; private var visibilityMenuItem: NSMenuItem?; private var petIsHidden = false; private var previousFrontmostApp: String?; private var settingsController: AemisSettingsWindowController?; private var aiQuoteInFlight = false
    private var positionMemoryTimer: Timer?
    private var isReturningToRememberedPosition = false
    private var temporaryFallbackFrame: NSRect?
    private var lastVisibleDisplays: [UInt32: NSRect] = [:]
    private let placementKey = "rememberedDisplayPlacement"
    private var chatFrameTimer: Timer?
    private var compactFrameBeforeChat: NSRect?
    private var isChatTransitioning = false
    private var clipboardTimer: Timer?
    private var pasteboardChangeCount = NSPasteboard.general.changeCount
    private var clipboardHistory: [String] = []
    private var speechVerificationObserver: NSObjectProtocol?
    private var speechVerificationTimer: Timer?
    private var emoticonPreviewObserver: NSObjectProtocol?
    private var emoticonVerificationObserver: NSObjectProtocol?
    private var rigVerificationObserver: NSObjectProtocol?
    private var rigVerificationTimer: Timer?
    private var ttsPlayer: AVAudioPlayer?
    private var visualSuccessCount = 0
    private var visualFallbackCount = 0
    private var lastContextUsedScreenshot = false
    private var lastCodexLaunchRequestAt = Date.distantPast
    private var cachedMascotVoiceClips: [CachedMascotVoiceClip] = []
    private var lastMascotVoiceURL: URL?
    private var mascotVoicePlayer: AVAudioPlayer?
    private var startupVoiceChannelActive = false
    private var startupVoiceUnlockTimer: Timer?
    private var startupPhaseObserver: NSObjectProtocol?
    private var startupPhasePollTimer: Timer?
    private let taskMonitor = CodexTaskMonitor()
    private var taskMonitorTimer: Timer?
    private var taskAlertPlayer: AVAudioPlayer?
    private var taskAlertPreviewObserver: NSObjectProtocol?
    private var pendingTaskAlerts: [CodexTaskAlert] = []
    private var taskAlertQueueTimer: Timer?
    private var taskAlertVoiceTimer: Timer?
    private var taskAlertVisibleUntil = Date.distantPast
    private var lastTaskAlertByThreadAndKind: [String: Date] = [:]
    private var lastStartupPhaseFileData: Data?
    private var processedStartupPhaseKeys = Set<String>()
    private var processedStartupPhaseOrder: [String] = []
    private var activePresetID: String {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "activePresetID"), bubble.presets.contains(where: { $0.id == saved }) { return saved }
        let fallback = bubble.presets.first?.id ?? "default"
        defaults.set(fallback, forKey: "activePresetID")
        return fallback
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory); buildPanel(); buildMenu(); refresh()
        speechVerificationObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.qianlve.codex-token-pet.verify-speech"), object: nil, queue: .main) { [weak self] _ in self?.verifyUnifiedSpeechRuntime() }
        emoticonVerificationObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.qianlve.codex-token-pet.verify-emoticon"), object: nil, queue: .main) { [weak self] _ in self?.bubble.verifyEmoticonBehavior() }
        emoticonPreviewObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.qianlve.codex-token-pet.preview-emoticon"), object: nil, queue: .main) { [weak self] _ in self?.bubble.previewEmoticonAndCapture() }
        rigVerificationObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.qianlve.codex-token-pet.verify-rig"), object: nil, queue: .main) { [weak self] _ in self?.verifyRigRuntime() }
        installStartupPhaseObserver()
        startStartupPhaseFilePolling()
        let alertSettings = CodexTaskAlertSettings.load()
        fputs("task-alert: startup pid=\(ProcessInfo.processInfo.processIdentifier) completion=\(alertSettings.completionEnabled) problem=\(alertSettings.problemEnabled) quietEnabled=\(alertSettings.quietEnabled) volume=\(alertSettings.volume)\n", stderr)
        taskMonitor.onAlert = { [weak self] alert in self?.presentTaskAlert(alert) }
        taskMonitor.poll()
        taskMonitorTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.taskMonitor.poll() }
        taskAlertPreviewObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.qianlve.codex-token-pet.preview-task-alert"), object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?["kind"] as? String,
                  let kind = CodexTaskAlertKind(rawValue: raw) else { return }
            self?.playTaskAlertAudio(kind)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.ensurePanelReachable()
            self?.refresh()
        }
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in self?.captureClipboardTextIfChanged() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Snapshot hooks are inert in normal launches and let the UI be visually
        // regression-tested without synthetic mouse clicks.
        if ProcessInfo.processInfo.environment["AEMIS_OPEN_SETTINGS"] == "1" { openAIConfiguration() }
        if ProcessInfo.processInfo.environment["AEMIS_TEST_CLIPBOARD"] == "1" {
            bubble.showClipboardHistoryForTesting(["第一条复制内容：爱弥斯会保留本次运行中的文字历史。", "第二条复制内容：滚动鼠标滚轮可以切换。", "第三条复制内容：点击即可重新复制。"])
        }
        if ProcessInfo.processInfo.environment["AEMIS_TEST_AI_QUOTE"] == "1" {
            generateAIQuote()
        }
        if ProcessInfo.processInfo.environment["AEMIS_TEST_COMPLETE_QUOTE"] == "1" {
            bubble.showMessage(title: "爱弥斯想说", body: "这个项目快收尾了，再仔细检查一下吧。", detail: "完整短句显示测试 ✦", duration: 30)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); focusTimer?.invalidate(); positionMemoryTimer?.invalidate(); chatFrameTimer?.invalidate(); clipboardTimer?.invalidate(); startupPhasePollTimer?.invalidate(); startupVoiceUnlockTimer?.invalidate(); taskMonitorTimer?.invalidate(); taskAlertQueueTimer?.invalidate(); taskAlertVoiceTimer?.invalidate(); mascotVoicePlayer?.stop(); taskAlertPlayer?.stop()
        if let startupPhaseObserver { DistributedNotificationCenter.default().removeObserver(startupPhaseObserver) }
        if let taskAlertPreviewObserver { DistributedNotificationCenter.default().removeObserver(taskAlertPreviewObserver) }
    }
    private func buildPanel() {
        let size = NSSize(width: 252, height: 272); let point = NSEvent.mouseLocation; let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        panel = AemisInteractivePanel(contentRect: NSRect(x: screen.maxX - size.width - 20, y: screen.minY + 112, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2); panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = true
        bubble = BubbleView(frame: NSRect(origin: .zero, size: size)); loadAppearance()
        bubble.configureRandomEmoticons()
        bubble.visualContextEnabled = UserDefaults.standard.object(forKey: "visualContextEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "visualContextEnabled")
        bubble.experimentalTTSEnabled = UserDefaults.standard.bool(forKey: "experimentalTTSEnabled")
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        bubble.mascot = customMascot() ?? builtInMascot(id: bubble.selectedBuiltInMascotID, in: folder) ?? NSImage(contentsOf: folder.appendingPathComponent("艾弥斯透明人物.png"))
        if customMascot() == nil { bubble.themeColor = BuiltInCharacterProfile.profile(for: bubble.selectedBuiltInMascotID).bubbleFill }
        installPreparedVoiceLibraryIfAvailable(in: folder)
        loadCachedMascotClickVoices(in: folder)
        createDefaultPresetIfNeeded()
        bubble.onMascotTap = { [weak self] in self?.refresh() }
        bubble.onTaskAlertClicked = { [weak self] in self?.openCodexTask($0) }
        bubble.onSetTaskAlertVolume = { [weak self] in self?.setTaskAlertVolume($0) }
        bubble.onPreviewTaskAlert = { [weak self] in self?.playTaskAlertAudio($0) }
        bubble.onTenTapVoiceRequested = { [weak self] in self?.playCombinedTenTapVoice() }
        bubble.shouldPlayLegacyVoice = { [weak self] in self?.shouldPlayLegacyVoice(for: $0) ?? true }
        bubble.onChooseMascot = { [weak self] in self?.chooseMascot() }; bubble.onChooseColor = { [weak self] in self?.chooseColor() }
        bubble.onResetAppearance = { [weak self] in self?.resetAppearance() }; bubble.onSetMascotSize = { [weak self] in self?.setMascotSize($0) }; bubble.onSetBubbleSize = { [weak self] in self?.setBubbleSize($0) }; bubble.onSetDisplayMode = { [weak self] in self?.setDisplayMode($0) }; bubble.onToggleClickSound = { [weak self] in self?.toggleClickSound() }; bubble.onSetTapSound = { [weak self] in self?.setTapSound($0) }; bubble.onSetSoundVolume = { [weak self] in self?.setSoundVolume($0) }
        bubble.onChooseCustomSound = { [weak self] in self?.chooseCustomSound() }; bubble.onSetPatMessage = { [weak self] in self?.choosePatMessage() }; bubble.onSavePreset = { [weak self] in self?.savePreset() }; bubble.onImportPresetPack = { [weak self] in self?.importPresetPack() }; bubble.onExportPresetPack = { [weak self] in self?.exportPresetPack() }; bubble.onImportClickSounds = { [weak self] in self?.importClickSounds() }; bubble.onImportEventSounds = { [weak self] in self?.importEventSounds() }; bubble.onApplyPreset = { [weak self] in self?.applyPreset(id: $0) }; bubble.onSelectBuiltInMascot = { [weak self] in self?.selectBuiltInMascot(id: $0) }; bubble.onRememberPosition = { [weak self] in self?.rememberPosition() }; bubble.onSaveCurrentPosition = { [weak self] in self?.saveCurrentPositionAsMemory() }; bubble.onSetBubbleOpacity = { [weak self] in self?.setBubbleOpacity($0) }; bubble.onDockPosition = { [weak self] in self?.dock($0) }; bubble.onInteraction = { [weak self] in self?.recordInteraction() }; bubble.onStartFocus = { [weak self] in self?.startFocus() }; bubble.onStopFocus = { [weak self] in self?.stopFocus() }; bubble.onOpenSettings = { [weak self] in self?.openAIConfiguration() }; bubble.onAIQuoteRequested = { [weak self] in self?.generateAIQuote() }; bubble.onCodexLaunchRequested = { [weak self] in self?.launchCodexWithAemis() }; bubble.onClipboardPanelHeightChanged = { [weak self] in self?.resizeForClipboard(height: $0) }
        panel.contentView = bubble; resizePanelToMascot(); restorePositionIfAvailable(); ensurePanelReachable(forceFront: true)
        fputs("position: startup enabled=\(bubble.positionMemoryEnabled) savedDisplay=\(rememberedPlacement()?.displayID.description ?? "none") frame=\(panel.frame)\n", stderr)
        NotificationCenter.default.addObserver(self, selector: #selector(panelDidMove(_:)), name: NSWindow.didMoveNotification, object: panel)
    }

    private func presentTaskAlert(_ alert: CodexTaskAlert) {
        // Event identity, not a per-thread cooldown: two separate completed
        // turns within a minute must both be delivered.
        guard lastTaskAlertByThreadAndKind[alert.key] == nil,
              !pendingTaskAlerts.contains(where: { $0.key == alert.key }) else { return }
        lastTaskAlertByThreadAndKind[alert.key] = Date()
        pendingTaskAlerts.append(alert)
        showNextTaskAlertIfReady()
    }

    private func showNextTaskAlertIfReady() {
        if startupVoiceChannelActive {
            taskAlertQueueTimer?.invalidate()
            taskAlertQueueTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.showNextTaskAlertIfReady() }
            return
        }
        guard Date() >= taskAlertVisibleUntil, !pendingTaskAlerts.isEmpty else { return }
        let alert = pendingTaskAlerts.removeFirst()
        guard taskMonitor.isActionable(alert) else {
            showNextTaskAlertIfReady()
            return
        }
        fputs("task-alert: present key=\(alert.key) kind=\(alert.kind.rawValue) thread=\(alert.threadID) reason=\(alert.reason)\n", stderr)
        taskAlertVisibleUntil = Date().addingTimeInterval(22)
        taskAlertQueueTimer?.invalidate()
        taskAlertQueueTimer = Timer.scheduledTimer(withTimeInterval: 22.1, repeats: false) { [weak self] _ in self?.showNextTaskAlertIfReady() }
        guard !petIsHidden else { return }
        bubble.showTaskAlert(alert)
        let settings = CodexTaskAlertSettings.load()
        let audible = !settings.isQuiet() && settings.volume > 0
        bubble.reactToTaskAlert(playClick: audible)
        guard audible else { fputs("task-alert: muted quiet=\(settings.isQuiet()) quietEnabled=\(settings.quietEnabled) hours=\(settings.quietStartHour)-\(settings.quietEndHour) volume=\(settings.volume)\n", stderr); return }
        taskAlertVoiceTimer?.invalidate()
        taskAlertVoiceTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: false) { [weak self] _ in
            guard let self, self.taskMonitor.isActionable(alert) else { return }
            self.playTaskAlertAudio(alert.kind, settings: settings)
        }
    }

    private func verifyUnifiedSpeechRuntime() {
        guard speechVerificationTimer == nil, let rig = bubble.layeredRig else { return }
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let frames = folder.appendingPathComponent("speech-preview-frames")
        try? FileManager.default.removeItem(at: frames)
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        var frameIndex = 0
        var frameMetadata: [[String:Any]] = []
        var ticks = 0
        var csv = "stage,time,playing,volume,db,mouth\n"
        var stage = -1
        var started = Date.distantPast
        var duration = 0.0
        let names = ["complete", "problem", "ten-tap"]
        let timer = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if Date().timeIntervalSince(started) >= duration {
                stage += 1
                if stage == names.count {
                    timer.invalidate(); self.speechVerificationTimer = nil
                    try? csv.write(to: folder.appendingPathComponent("unified-speech-verification.csv"), atomically: true, encoding: .utf8)
                    if let data = try? JSONSerialization.data(withJSONObject:frameMetadata,options:[.prettyPrinted]) { try? data.write(to:folder.appendingPathComponent("speech-preview-frames.json")) }
                    fputs("speech: three playback paths verification complete\n", stderr)
                    return
                }
                if stage == 0 { self.playTaskAlertAudio(.complete) }
                else if stage == 1 { self.playTaskAlertAudio(.problem) }
                else { self.playCombinedTenTapVoice() }
                let player = stage < 2 ? self.taskAlertPlayer : self.mascotVoicePlayer
                duration = (player?.duration ?? 1) + 1.0; started = Date()
            }
            ticks += 1
            if let bitmap = self.bubble.bitmapImageRepForCachingDisplay(in:self.bubble.bounds) {
                self.bubble.cacheDisplay(in:self.bubble.bounds,to:bitmap)
                if let data=bitmap.representation(using:.png,properties:[:]) { try? data.write(to:frames.appendingPathComponent(String(format:"frame-%05d.png",frameIndex))) }
                frameMetadata.append(["file":String(format:"frame-%05d.png",frameIndex),"stage":names[stage],"time":Date().timeIntervalSince(started),"mouth":rig.mouth,"db":rig.audioDB])
                frameIndex += 1
            }
            let player = stage < 2 ? self.taskAlertPlayer : self.mascotVoicePlayer
            csv += "\(names[stage]),\(Date().timeIntervalSince(started)),\(player?.isPlaying ?? false),\(player?.volume ?? 0),\(rig.audioDB),\(rig.mouth)\n"
        }
        RunLoop.main.add(timer, forMode: .common); speechVerificationTimer = timer
    }

    private func verifyRigRuntime() {
        guard rigVerificationTimer == nil, let rig = bubble.layeredRig else { return }
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("rig-verification")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var telemetry = "time,db,mouth,eye,hair,back\n"
        let start = ProcessInfo.processInfo.systemUptime
        let initialFrame = panel.frame
        let initialBlinks = rig.blinkCount
        rig.onTelemetry = { t,db,mouth,eye in
            let front = rig.model.layers.first { $0.id == "H05" }!
            let back = rig.model.layers.first { $0.id == "H08" }!
            telemetry += "\(t),\(db),\(mouth),\(eye),\(rig.angle(front)),\(rig.angle(back))\n"
        }
        var frame = 0
        let capture = Timer(timeInterval: 1.0/15, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = ProcessInfo.processInfo.systemUptime-start
            if elapsed >= 18 {
                timer.invalidate(); self.rigVerificationTimer = nil; rig.onTelemetry = nil
                try? telemetry.write(to: folder.appendingPathComponent("telemetry.csv"), atomically: true, encoding: .utf8)
                let report: [String:Any] = ["frames":frame,"modelFormat":rig.model.format,"layers":rig.model.layers.count,"character":self.bubble.selectedBuiltInMascotID,"randomBlinks":rig.blinkCount-initialBlinks,"positionUnchanged":self.panel.frame == initialFrame,"rightEarHidden":true,"alertVolume":CodexTaskAlertSettings.load().volume]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]) { try? data.write(to:folder.appendingPathComponent("report.json")) }
                fputs("rig: verification complete frames=\(frame) folder=\(folder.path)\n",stderr)
                return
            }
            if let bitmap = self.bubble.bitmapImageRepForCachingDisplay(in:self.bubble.bounds) {
                self.bubble.cacheDisplay(in:self.bubble.bounds,to:bitmap)
                if let data=bitmap.representation(using:.png,properties:[:]) { try? data.write(to:folder.appendingPathComponent(String(format:"frame-%04d.png",frame))) }
            }
            frame += 1
        }
        RunLoop.main.add(capture,forMode:.common); rigVerificationTimer=capture
        // First 3 seconds prove idle movement; then a sustained 2-second click burst.
        for i in 0..<12 { DispatchQueue.main.asyncAfter(deadline:.now()+3+Double(i)*0.16) { [weak self] in self?.bubble.verifyMascotClick() } }
        DispatchQueue.main.asyncAfter(deadline:.now()+7) { [weak self] in self?.playTaskAlertAudio(.complete) }
        DispatchQueue.main.asyncAfter(deadline:.now()+11) { [weak self] in self?.playTaskAlertAudio(.problem) }
        DispatchQueue.main.asyncAfter(deadline:.now()+15) { [weak self] in
            guard let self else { return }
            // Exercise the same AVAudioPlayer(data:) path used by TTS without a network synthesis request.
            let voiceURL = URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("voice-assets/task-alerts/complete.wav")
            if let data = try? Data(contentsOf:voiceURL), let player = try? AVAudioPlayer(data:data) {
                self.ttsPlayer = player; self.bubble.trackSpeech(player); player.prepareToPlay(); player.play()
                fputs("rig: TTS data-player path exercised with local fixture\n",stderr)
            }
        }
    }

    private func playTaskAlertAudio(_ kind: CodexTaskAlertKind, settings: CodexTaskAlertSettings = .load()) {
        guard settings.volume > 0 else { fputs("task-alert: volume zero\n", stderr); return }
        let baseName = kind == .complete ? "complete" : "problem"
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let original = folder.appendingPathComponent("voice-assets/task-alerts/\(baseName).wav")
        guard let speech = UnifiedSpeech.resolve(original, volume: settings.volume) else { return }
        let url = speech.url
        let name = "\(baseName)-\(speech.percent)"
        do {
            taskAlertPlayer = try AVAudioPlayer(contentsOf: url)
            taskAlertPlayer?.volume = speech.playerVolume
            bubble.trackSpeech(taskAlertPlayer)
            taskAlertPlayer?.prepareToPlay()
            let started = taskAlertPlayer?.play() ?? false
            fputs("task-alert: audio file=\(name) setting=\(settings.volume) playerVolume=\(taskAlertPlayer?.volume ?? 0) started=\(started)\n", stderr)
        } catch {
            fputs("task-alert: audio unavailable \(url.path): \(error)\n", stderr)
        }
    }

    private func openCodexTask(_ threadID: String) {
        guard UUID(uuidString: threadID) != nil,
              let url = URL(string: "codex://threads/\(threadID)") else { return }
        let opened = NSWorkspace.shared.open(url)
        fputs("task-alert: open thread=\(threadID) opened=\(opened)\n", stderr)
    }

    private func setTaskAlertVolume(_ value: Float) {
        var settings = CodexTaskAlertSettings.load()
        settings.volume = max(0, min(2, value))
        settings.save()
        settingsController?.refreshTaskAlertControls(settings)
    }


    @objc private func screenConfigurationChanged(_ notification: Notification) {
        fputs("position: screen configuration changed\n", stderr)
        // NSScreen can report an intermediate layout while a display wakes.
        for delay in [0.2, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.ensurePanelReachable(forceFront: true)
            }
        }
    }

    /// Prevents the floating pet from becoming an invisible, one-pixel sliver.
    /// This deliberately bypasses the remembered-position return animation:
    /// recovery must win even when a previous transition was interrupted.
    private func ensurePanelReachable(forceFront: Bool = false) {
        guard panel != nil, bubble != nil, !bubble.chatExpanded, !petIsHidden else { return }
        let displays = currentPetDisplays()
        let displayFrames = Dictionary(displays.map { ($0.id, $0.visible) }, uniquingKeysWith: { first, _ in first })
        let layoutChanged = displayFrames != lastVisibleDisplays
        lastVisibleDisplays = displayFrames
        if layoutChanged {
            fputs("position: displays=\(displays.map { "\($0.id):\($0.visible)" }.joined(separator: ",")) savedDisplay=\(rememberedPlacement()?.displayID.description ?? "none") enabled=\(bubble.positionMemoryEnabled)\n", stderr)
        }
        let frame = panel.frame
        let minimumVisibleWidth = min(CGFloat(96), frame.width * 0.45)
        let minimumVisibleHeight = min(CGFloat(96), frame.height * 0.35)
        let fullyVisible = NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
        var rememberedDisplayMissing = false

        if bubble.positionMemoryEnabled, let remembered = rememberedPlacement() {
            if let target = remembered.frame(size: compactPanelSize, screens: displays) {
                if temporaryFallbackFrame != nil || layoutChanged {
                    positionMemoryTimer?.invalidate()
                    temporaryFallbackFrame = nil
                    movePanelWithoutRemembering(to: target)
                    fputs("position: restored display=\(remembered.displayID) frame=\(target)\n", stderr)
                }
            } else if temporaryFallbackFrame == nil, fullyVisible {
                temporaryFallbackFrame = frame
            } else {
                rememberedDisplayMissing = true
            }
        } else if bubble.positionMemoryEnabled, let legacy = legacyRememberedFrame(),
                  let migrated = PetDisplayPlacement.capture(frame: legacy, screens: displays) {
            savePlacement(migrated)
            if layoutChanged { movePanelWithoutRemembering(to: migrated.frame(size: compactPanelSize, screens: displays) ?? frame) }
        }

        let current = panel.frame
        let nowVisible = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(current)
            return overlap.width >= minimumVisibleWidth && overlap.height >= minimumVisibleHeight
        }
        if !nowVisible || (rememberedDisplayMissing && !NSScreen.screens.contains(where: { $0.visibleFrame.contains(current) })) {
            let pointer = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })?.visibleFrame
                    ?? NSScreen.main?.visibleFrame
                    ?? NSScreen.screens.first?.visibleFrame else { return }
            let recovered = PetDisplayPlacementGeometry.fallback(size: compactPanelSize, pointer: pointer, screen: screen)
            if bubble.positionMemoryEnabled { temporaryFallbackFrame = recovered }
            positionMemoryTimer?.invalidate()
            movePanelWithoutRemembering(to: recovered)
            fputs("position: temporary fallback frame=\(recovered)\n", stderr)
        }
        if forceFront || !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func currentPetDisplays() -> [PetDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let stableID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)
                .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            return PetDisplay(id: number.uint32Value, visible: screen.visibleFrame, stableID: stableID)
        }
    }

    private func rememberedPlacement() -> PetDisplayPlacement? {
        guard let data = UserDefaults.standard.data(forKey: placementKey) else { return nil }
        guard let placement = try? JSONDecoder().decode(PetDisplayPlacement.self, from: data) else { return nil }
        if placement.stableID == nil,
           let screen = currentPetDisplays().first(where: { $0.id == placement.displayID }),
           let stableID = screen.stableID {
            let upgraded = PetDisplayPlacement(displayID: placement.displayID, stableID: stableID, x: placement.x, y: placement.y)
            savePlacement(upgraded)
            return upgraded
        }
        return placement
    }

    private func savePlacement(_ placement: PetDisplayPlacement) {
        guard let data = try? JSONEncoder().encode(placement) else { return }
        UserDefaults.standard.set(data, forKey: placementKey)
        fputs("position: saved display=\(placement.displayID) x=\(placement.x) y=\(placement.y)\n", stderr)
    }

    private func legacyRememberedFrame() -> NSRect? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "panelX") != nil, defaults.object(forKey: "panelY") != nil else { return nil }
        return NSRect(origin: NSPoint(x: defaults.double(forKey: "panelX"), y: defaults.double(forKey: "panelY")), size: compactPanelSize)
    }

    private func movePanelWithoutRemembering(to frame: NSRect) {
        guard hypot(panel.frame.minX - frame.minX, panel.frame.minY - frame.minY) > 1 || panel.frame.size != frame.size else { return }
        isReturningToRememberedPosition = true
        panel.setFrame(frame, display: true)
        bubble.frame = NSRect(origin: .zero, size: frame.size)
        isReturningToRememberedPosition = false
    }
    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◌ Token"
        let menu = NSMenu()
        let visibility = NSMenuItem(title: "隐藏桌宠", action: #selector(togglePetVisibility), keyEquivalent: "h")
        visibility.target = self
        visibilityMenuItem = visibility
        menu.addItem(visibility)
        menu.addItem(withTitle: "立即刷新", action: #selector(refreshFromMenu), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Token 小气泡", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func togglePetVisibility() {
        petIsHidden.toggle()
        if petIsHidden {
            positionMemoryTimer?.invalidate()
            panel.orderOut(nil)
            visibilityMenuItem?.title = "显示桌宠"
        } else {
            ensurePanelReachable(forceFront: true)
            panel.orderFrontRegardless()
            visibilityMenuItem?.title = "隐藏桌宠"
        }
    }
    @objc private func refreshFromMenu() { refresh() }
    private func openAIConfiguration() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AI 随机台词"
        alert.informativeText = "DeepSeek 只用于偶尔生成一条符合爱弥斯人设的气泡台词，不提供聊天窗口。API Key 仅保存在本机钥匙串。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "保存并测试")
        alert.addButton(withTitle: "取消")
        let key = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 26))
        key.placeholderString = AemisKeychain.load() == nil ? "输入 DeepSeek API Key" : "已保存；留空则保持不变"
        key.focusRingType = .default
        let label = NSTextField(labelWithString: "DeepSeek API Key")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        let stack = NSStackView(views: [label, key]); stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 330, height: 54)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = key
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return }
        let entered = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entered.isEmpty, !AemisKeychain.save(entered) {
            bubble.showMessage(title: "AI 设置", body: "保存失败", detail: "无法写入 macOS 钥匙串", duration: 5)
            return
        }
        guard response == .alertSecondButtonReturn else {
            bubble.showMessage(title: "AI 设置", body: "已保存", detail: "DeepSeek 仅用于随机气泡台词", duration: 4)
            return
        }
        guard let savedKey = AemisKeychain.load(), !savedKey.isEmpty else {
            bubble.showMessage(title: "AI 设置", body: "还没有 API Key", detail: "右键可重新输入", duration: 5)
            return
        }
        bubble.showMessage(title: "AI 设置", body: "正在测试…", detail: "请稍候", duration: 8)
        AemisDeepSeekService.test(configuration: AemisAIConfiguration.load(), key: savedKey) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: self?.bubble.showMessage(title: "AI 设置", body: "连接成功", detail: "爱弥斯可以偶尔说话了", duration: 5)
                case .failure(let error): self?.bubble.showMessage(title: "AI 设置", body: "连接失败", detail: error.localizedDescription, duration: 7)
                }
            }
        }
    }

    private func generateAIQuote() {
        let profile = BuiltInCharacterProfile.profile(for: bubble.selectedBuiltInMascotID)
        guard !aiQuoteInFlight else {
            bubble.showPersistentMessage(title: profile.name, body: "我正在想呢…", detail: "V4 Flash 还在处理，请稍等一下 ✦")
            return
        }
        guard let key = AemisKeychain.load(), !key.isEmpty else {
            bubble.showMessage(title: profile.name, body: "还不能说话", detail: "右键 → AI 随机台词设置", duration: 5)
            return
        }
        var configuration = AemisAIConfiguration.load()
        configuration.model = AemisAIConfiguration.requiredModel
        let configuredPersona = bubble.presets.first(where: { $0.id == activePresetID })?.persona?.trimmingCharacters(in: .whitespacesAndNewlines) ?? configuration.persona.trimmingCharacters(in: .whitespacesAndNewlines)
        // Official character facts remain the non-overridable base. Existing
        // presets may add tone preferences but cannot silently replace the canon.
        configuration.persona = profile.persona
        if bubble.selectedBuiltInMascotID.isEmpty, !configuredPersona.isEmpty, configuredPersona != AemisAIConfiguration.defaultPersona {
            configuration.persona += "\n用户自定义的补充语气要求：" + configuredPersona
        }
        let activity = bubble.frontmostContext.map { context in "用户当前" + context.activity + "：" + context.appName + "。" } ?? "当前软件信息不可用。"
        let timeHint = currentTimeContext()
        let imageURL = bubble.visualContextEnabled ? captureFrontmostWindowImage() : nil
        let visionHint = imageURL == nil ? "" : "请先观察附带的当前窗口截图，理解用户正在做什么，但不要描述截图或泄露敏感文字。"
        aiQuoteInFlight = true
        bubble.showPersistentMessage(title: profile.name, body: "让我看看…", detail: "V4 Flash 正在理解你此刻做的事")
        requestReviewedQuote(profile: profile, configuration: configuration, key: key, activity: activity, timeHint: timeHint, visionHint: visionHint, imageURL: imageURL, attempt: 1, rejection: nil, mayFallbackWithoutImage: imageURL != nil)
    }

    private func launchCodexWithAemis() {
        let now = Date()
        guard now.timeIntervalSince(lastCodexLaunchRequestAt) >= 1.2 else {
            fputs("codex-launch: debounced\n", stderr)
            return
        }
        lastCodexLaunchRequestAt = now
        setStartupVoiceChannelActive(true)
        let profile = BuiltInCharacterProfile.profile(for: bubble.selectedBuiltInMascotID)
        bubble.showMessage(title: profile.name, body: "正在召唤 Codex…", detail: "启动动画准备中 ✦", duration: 2.4)
        guard let url = URL(string: "codex-aemeath://launch?source=pet&refresh=1") else {
            setStartupVoiceChannelActive(false)
            fputs("codex-launch: invalid-url\n", stderr)
            return
        }
        let opened = NSWorkspace.shared.open(url)
        if !opened { setStartupVoiceChannelActive(false) }
        fputs("codex-launch: scheme=codex-aemeath source=pet opened=\(opened)\n", stderr)
    }

    private func installStartupPhaseObserver() {
        if let startupPhaseObserver { DistributedNotificationCenter.default().removeObserver(startupPhaseObserver) }
        startupPhaseObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.qianlve.aemeath-startup.phase"), object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleStartupPhaseNotification(notification)
        }
    }

    private func handleStartupPhaseNotification(_ notification: Notification) {
        let info = notification.userInfo?.reduce(into: [String: Any]()) { result, entry in
            if let key = entry.key as? String { result[key] = entry.value }
        } ?? [:]
        handleStartupPhasePayload(info, channel: "distributed")
    }

    private var startupPhaseStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AemeathStartup/startup-phase.json")
    }

    private func startStartupPhaseFilePolling() {
        startupPhasePollTimer?.invalidate()
        pollStartupPhaseFile()
        let pollTimer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.pollStartupPhaseFile()
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        startupPhasePollTimer = pollTimer
    }

    private func pollStartupPhaseFile() {
        guard let data = try? Data(contentsOf: startupPhaseStateURL),
              !data.isEmpty,
              data != lastStartupPhaseFileData,
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        lastStartupPhaseFileData = data
        handleStartupPhasePayload(info, channel: "file")
    }

    private func handleStartupPhasePayload(_ info: [String: Any], channel: String) {
        if let events = info["events"] as? [[String: Any]] {
            let inheritedToken = info["token"] as? String
            let inheritedSource = info["source"] as? String
            for event in events {
                var normalized = event
                if normalized["token"] == nil { normalized["token"] = inheritedToken }
                if normalized["source"] == nil { normalized["source"] = inheritedSource }
                handleStartupPhaseEvent(normalized, channel: channel)
            }
            return
        }
        handleStartupPhaseEvent(info, channel: channel)
    }

    private func handleStartupPhaseEvent(_ info: [String: Any], channel: String) {
        guard info["source"] as? String == "pet",
              let phase = info["phase"] as? String,
              ["requested", "visible", "completed", "failed"].contains(phase),
              let token = info["token"] as? String, !token.isEmpty else { return }
        let key = token + "|" + phase
        guard processedStartupPhaseKeys.insert(key).inserted else {
            fputs("startup-phase: duplicate token=\(token) phase=\(phase) channel=\(channel)\n", stderr)
            return
        }
        processedStartupPhaseOrder.append(key)
        if processedStartupPhaseOrder.count > 256 {
            processedStartupPhaseKeys.remove(processedStartupPhaseOrder.removeFirst())
        }
        if phase == "requested" || phase == "visible" { setStartupVoiceChannelActive(true) }
        if phase == "completed" || phase == "failed" { setStartupVoiceChannelActive(false) }
        fputs("startup-phase: token=\(token) phase=\(phase) source=pet channel=\(channel)\n", stderr)
        bubble.showStartupPhase(phase)
    }

    private func loadCachedMascotClickVoices(in appFolder: URL) {
        let folder = appFolder.appendingPathComponent("voice-assets/click-clone", isDirectory: true)
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clips = root["clips"] as? [[String: Any]] else { return }
        cachedMascotVoiceClips = clips.compactMap { clip in
            guard let text = clip["text"] as? String, !text.isEmpty,
                  let file = clip["file"] as? String, !file.isEmpty else { return nil }
            let url = folder.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return CachedMascotVoiceClip(text: text, url: url)
        }
        fputs("click-voice: cached=\(cachedMascotVoiceClips.count)\n", stderr)
    }

    private func playCombinedTenTapVoice() {
        guard bubble.selectedBuiltInMascotID == "aemis", bubble.clickSoundEnabled else { return }
        guard !startupVoiceChannelActive else {
            fputs("ten-tap-voice: suppressed startup-active\n", stderr)
            return
        }
        if mascotVoicePlayer?.isPlaying == true {
            fputs("ten-tap-voice: suppressed previous-clip-playing\n", stderr)
            return
        }
        let legacyClips = bubble.eventSounds
            .filter { $0.trigger == InteractionTrigger.tenTaps.rawValue }
            .map {
                let url = URL(fileURLWithPath: $0.path)
                return CachedMascotVoiceClip(text: legacyVoiceDisplayText(for: url), url: url)
            }
        let combined = cachedMascotVoiceClips + legacyClips
        let alternatives = combined.filter { $0.url != lastMascotVoiceURL && FileManager.default.fileExists(atPath: $0.url.path) }
        let available = combined.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard let clip = (alternatives.isEmpty ? available : alternatives).randomElement() else {
            fputs("ten-tap-voice: no-clips\n", stderr)
            return
        }
        do {
            guard let speech = UnifiedSpeech.resolve(clip.url, volume: CodexTaskAlertSettings.load().volume) else { return }
            let player = try AVAudioPlayer(contentsOf: speech.url)
            player.volume = speech.playerVolume
            player.prepareToPlay()
            mascotVoicePlayer = player
            bubble.trackSpeech(player)
            lastMascotVoiceURL = clip.url
            bubble.showMessage(title: "爱弥斯", body: clip.text, detail: "连点 10 次 · 语音回应", duration: max(2.5, player.duration + 0.35))
            // Let the tenth tap's short two-part click finish first, then clear any
            // lingering legacy slice immediately before the combined voice starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self, weak player] in
                guard let self, !self.startupVoiceChannelActive else { return }
                self.bubble.stopLegacyAudioPlayback()
                self.ttsPlayer?.stop()
                player?.play()
            }
            fputs("ten-tap-voice: played file=\(clip.url.lastPathComponent) pool=\(combined.count) bank=\(speech.percent) playerVolume=\(speech.playerVolume)\n", stderr)
        } catch {
            fputs("ten-tap-voice: failed file=\(clip.url.lastPathComponent)\n", stderr)
        }
    }

    private func legacyVoiceDisplayText(for url: URL) -> String {
        switch url.lastPathComponent {
        case "01.mp3": return "没错，还是我。"
        case "02.mp3": return "好久不见，最近怎么样？"
        case "03.mp3": return "学院那边，应该还挺忙吧。"
        case "04.mp3": return "我只是想和你说件小事。"
        case "05.mp3": return "猜猜我在旧数据里发现了什么？"
        case "06.mp3": return "那时候，我总是一头栽在地上。"
        case "07.mp3": return "第一次飞过走廊，我记了很久。"
        case "08.mp3": return "这种小技巧，你还记得吗？"
        case "09.mp3": return "开心快乐地生活更重要。"
        case "10.mp3": return "小艾老师可以再教你哦。"
        case "11.mp3": return "因为那是你教我的事。"
        case "12.mp3": return "别着急，有我在呢。"
        case "13.mp3": return "漂泊者，记得照顾好自己。"
        default: return "哎呀，被你发现啦。"
        }
    }

    private func shouldPlayLegacyVoice(for trigger: InteractionTrigger) -> Bool {
        guard bubble.clickSoundEnabled, !startupVoiceChannelActive, mascotVoicePlayer?.isPlaying != true else { return false }
        let clickTriggers: Set<InteractionTrigger> = [.doubleTap, .tripleTaps, .fiveTaps, .tenTaps, .fifteenTaps]
        return cachedMascotVoiceClips.isEmpty || !clickTriggers.contains(trigger)
    }

    private func setStartupVoiceChannelActive(_ active: Bool) {
        startupVoiceChannelActive = active
        startupVoiceUnlockTimer?.invalidate()
        startupVoiceUnlockTimer = nil
        if active {
            mascotVoicePlayer?.stop()
            ttsPlayer?.stop()
            bubble.stopLegacyAudioPlayback()
            startupVoiceUnlockTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                self?.startupVoiceChannelActive = false
                self?.startupVoiceUnlockTimer = nil
                fputs("click-voice: startup-lock-timeout\n", stderr)
            }
        }
    }

    private func requestReviewedQuote(profile: BuiltInCharacterProfile, configuration: AemisAIConfiguration, key: String, activity: String, timeHint: String, visionHint: String, imageURL: URL?, attempt: Int, rejection: String?, mayFallbackWithoutImage: Bool) {
        let retry = rejection.map { "上一句被审核退回，原因：\($0)。必须换一种说法。" } ?? ""
        let prompt = "\(timeHint)。\(activity)\(visionHint)\(retry)请完全遵循系统中的\(profile.name)人物设定，只输出一句与当前软件或窗口内容直接相关的中文桌宠台词。先在内部检查人设、情境和句子完整性，检查合格后才输出最终一句，不要展示检查过程。要求：10至20个可见字符；必须是一句已经说完、能独立成立的话，并以句号、感叹号或问号结尾；禁止以‘但是、因为、所以、我觉得、如果、虽然、而且、然后’等未完成转折收尾；不换行、不加引号、不解释；不提AI、模型、截图、API；不要泛泛问候；除午餐11:30至13:30、晚餐17:30至19:30外，不得询问吃饭；凌晨不得使用早安、晚饭或吃饭话题。"
        AemisDeepSeekService.request(configuration: configuration, key: key, messages: [("user", prompt)], imageURL: imageURL) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error) where imageURL != nil && mayFallbackWithoutImage:
                if let imageURL { try? FileManager.default.removeItem(at: imageURL) }
                self.visualFallbackCount += 1
                self.bubble.visualFallbackCount = self.visualFallbackCount
                self.lastContextUsedScreenshot = false
                self.requestReviewedQuote(profile: profile, configuration: configuration, key: key, activity: activity, timeHint: timeHint, visionHint: "图片读取失败，改用当前软件名称与窗口标题判断。", imageURL: nil, attempt: attempt, rejection: error.localizedDescription, mayFallbackWithoutImage: false)
            case .failure(let error) where imageURL == nil && attempt < 2:
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.65) {
                    self.requestReviewedQuote(profile: profile, configuration: configuration, key: key, activity: activity, timeHint: timeHint, visionHint: visionHint, imageURL: nil, attempt: attempt + 1, rejection: "上一次网络请求失败：\(error.localizedDescription)", mayFallbackWithoutImage: false)
                }
            case .failure(let error): self.finishQuoteRequest(imageURL: imageURL, result: .failure(error))
            case .success(let text):
                if imageURL != nil { self.visualSuccessCount += 1; self.bubble.visualSuccessCount = self.visualSuccessCount; self.lastContextUsedScreenshot = true }
                guard let line = self.compactAIQuote(text) else {
                    if attempt < 2 {
                        self.requestReviewedQuote(profile: profile, configuration: configuration, key: key, activity: activity, timeHint: timeHint, visionHint: visionHint, imageURL: imageURL, attempt: attempt + 1, rejection: "上一句没有说完或无法完整放入气泡，请改写为完整短句并加句末标点", mayFallbackWithoutImage: mayFallbackWithoutImage)
                    } else {
                        self.finishQuoteRequest(imageURL: imageURL, result: .success((self.safeFallbackQuote(for: activity), .thinking)))
                    }
                    return
                }
                // V4 Flash already performs the persona/context check inside the
                // generation prompt. Keep the deterministic local length and
                // completion gate above, then present immediately instead of
                // paying for a second network round-trip on every click.
                self.finishQuoteRequest(imageURL: imageURL, result: .success((line, self.localEmotion(for: line))))
            }
        }
    }

    private func localEmotion(for line: String) -> AemisSpeechEmotion {
        if line.contains("？") || line.contains("?") { return .confused }
        if line.contains("辛苦") || line.contains("休息") || line.contains("慢慢") { return .smile }
        if line.contains("！") || line.contains("真棒") || line.contains("不错") { return .happy }
        return .neutral
    }

    private func reviewQuote(_ line: String, profile: BuiltInCharacterProfile, configuration: AemisAIConfiguration, key: String, activity: String, timeHint: String, completion: @escaping (Result<AemisQuoteReview, Error>) -> Void) {
        let prompt = "你是严格的\(profile.name)台词审核器。当前时间：\(timeHint)。当前活动：\(activity)候选台词：\(line)。检查它是否符合\(profile.name)人设、是否与当前活动具体相关、是否时段合理、是否为10至20个可见字符、是否已经完整说完并以句末标点结束、是否不泄露截图内容。只返回单行JSON：{\"approved\":true或false,\"emotion\":\"neutral|smile|happy|wink|surprised|confused|thinking|annoyed|sad|tearful|shy|speechless|sleepy|proud|nervous|poked|dislike|expecting\",\"reason\":\"不超过30字\"}。不合格必须approved=false。"
        AemisDeepSeekService.request(configuration: configuration, key: key, messages: [("user", prompt)], imageURL: nil) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let text):
                let cleaned = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let data = cleaned.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let approved = json["approved"] as? Bool else {
                    completion(.failure(NSError(domain: "Aemis", code: 3, userInfo: [NSLocalizedDescriptionKey: "台词审核返回格式无效。"])))
                    return
                }
                let emotion = AemisSpeechEmotion(rawValue: json["emotion"] as? String ?? "neutral") ?? .neutral
                completion(.success(AemisQuoteReview(approved: approved, emotion: emotion, reason: json["reason"] as? String ?? "不符合当前情境")))
            }
        }
    }

    private func finishQuoteRequest(imageURL: URL?, result: Result<(String, AemisSpeechEmotion), Error>) {
        if let imageURL { try? FileManager.default.removeItem(at: imageURL) }
        DispatchQueue.main.async {
            self.aiQuoteInFlight = false
            switch result {
            case .success(let value): self.presentGeneratedQuote(value.0, emotion: value.1)
            case .failure(let error):
                let profile = BuiltInCharacterProfile.profile(for: self.bubble.selectedBuiltInMascotID)
                let code = (error as NSError).code
                if [401, 402, 403].contains(code) {
                    self.bubble.showMessage(title: "\(profile.name)暂时没说话", body: "请检查账户设置", detail: error.localizedDescription, duration: 8)
                } else {
                    // A temporary API or network failure should not turn a pet
                    // interaction into a dead end. Keep the character responsive
                    // with a complete local line and make the downgrade visible.
                    self.bubble.showMessage(title: "\(profile.name)想说", body: "先把眼前这一步做好吧。", detail: "网络暂时不稳 · 已使用本地台词", duration: 8)
                }
            }
        }
    }

    private func currentTimeContext() -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        let now = Date(), hour = Calendar.current.component(.hour, from: now), minute = Calendar.current.component(.minute, from: now)
        let minutes = hour * 60 + minute
        let phase: String
        switch minutes {
        case 0..<360: phase = "深夜"
        case 360..<690: phase = "上午"
        case 690..<810: phase = "午餐时段"
        case 810..<1050: phase = "下午"
        case 1050..<1170: phase = "晚餐时段"
        default: phase = "晚上"
        }
        return "现在是\(formatter.string(from: now))（\(phase)）"
    }

    private func presentGeneratedQuote(_ line: String, emotion: AemisSpeechEmotion) {
        let profile = BuiltInCharacterProfile.profile(for: bubble.selectedBuiltInMascotID)
        let isAemis = profile.id == "aemis"
        let contextDetail = lastContextUsedScreenshot ? "已结合当前窗口 ✦" : "已根据软件与窗口判断 ✦"
        guard bubble.experimentalTTSEnabled else {
            bubble.showMessage(title: "\(profile.name)想说", body: line, detail: contextDetail, duration: 8)
            return
        }
        guard isAemis else {
            bubble.showMessage(title: "\(profile.name)想说", body: line, detail: "该角色未绑定语音", duration: 8)
            return
        }
        bubble.showMessage(title: "爱弥斯想说", body: line, detail: "正在准备声音…", duration: 18)
        AemisPinokioTTS.synthesize(text: line) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let data):
                    do {
                        self.ttsPlayer = try AVAudioPlayer(data: data)
                        self.bubble.trackSpeech(self.ttsPlayer)
                        self.ttsPlayer?.prepareToPlay()
                        let duration = max(2.5, self.ttsPlayer?.duration ?? 5)
                        self.bubble.showMessage(title: "爱弥斯想说", body: line, detail: "实验语音 · 芊略", duration: duration)
                        self.ttsPlayer?.play()
                    } catch {
                        self.bubble.showMessage(title: "爱弥斯想说", body: line, detail: "语音无法播放，已保留文字", duration: 8)
                    }
                case .failure:
                    self.bubble.showMessage(title: "爱弥斯想说", body: line, detail: "千问 TTS 未就绪，已保留文字", duration: 8)
                }
            }
        }
    }

    private func captureClipboardTextIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        let value = String(text.prefix(1200))
        clipboardHistory.removeAll { $0 == value }
        clipboardHistory.insert(value, at: 0)
        if clipboardHistory.count > 12 { clipboardHistory.removeLast(clipboardHistory.count - 12) }
        bubble.clipboardHistory = clipboardHistory
    }

    private func resizeForClipboard(height: CGFloat?) {
        guard !bubble.chatExpanded else { return }
        let old = panel.frame
        let targetHeight = ceil(height ?? compactPanelSize.height)
        let target = NSRect(x: old.minX, y: old.minY, width: old.width, height: targetHeight)
        panel.setFrame(target, display: true)
        bubble.frame = NSRect(origin: .zero, size: target.size)
    }

    private func compactAIQuote(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
        text = text.components(separatedBy: .newlines).first ?? text
        guard let end = text.firstIndex(where: { "。！？!?".contains($0) }) else { return nil }
        text = String(text[...end])
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...20).contains(text.count) else { return nil }
        let stem = text.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        let danglingEndings = ["但是", "可是", "因为", "所以", "我觉", "我觉得", "如果", "虽然", "而且", "然后", "并且", "不过", "只是", "就是", "似乎", "可能"]
        guard !danglingEndings.contains(where: { stem.hasSuffix($0) }) else { return nil }
        return text
    }

    private func safeFallbackQuote(for activity: String) -> String {
        if activity.contains("项目") || activity.contains("Codex") { return "已经快收尾了，再检查一下吧。" }
        if activity.contains("视频") { return "这一段看起来很有意思呢。" }
        if activity.contains("网页") { return "这页内容值得再仔细看看。" }
        return "现在这一步，慢慢做好就行啦。"
    }

    private func captureFrontmostWindowImage() -> URL? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard CGPreflightScreenCaptureAccess() else {
            // A click on the pet must never steal focus by opening System
            // Settings. Permission can temporarily look unavailable after a
            // rebuild even when the switch is on, so silently fall back to the
            // foreground app/window metadata and keep the current bubble flow.
            return nil
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let candidates: [(CGWindowID, CGRect)] = windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsValue = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary), bounds.width > 120, bounds.height > 80 else { return nil }
            return (number, bounds)
        }
        guard let selected = candidates.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else { return nil }
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("aemis-window-source-\(UUID().uuidString).png")
        let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(selected.0), "-t", "png", sourceURL.path]
        do { try capture.run(); capture.waitUntilExit() } catch { return nil }
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        guard capture.terminationStatus == 0, let source = NSImage(contentsOf: sourceURL),
              let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let maxWidth: CGFloat = 960
        let scale = min(1, maxWidth / CGFloat(image.width))
        let width = max(1, Int(CGFloat(image.width) * scale)); let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: resized)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.55]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aemis-front-window-\(UUID().uuidString).jpg")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private func openSettingsWindow() {
        if settingsController == nil || settingsController?.configuredPresetID != activePresetID {
            let presentation = AemisPresentationSettings(mascotSize: bubble.mascotSize, bubbleSize: bubble.bubbleSize, bubbleOpacity: bubble.bubbleOpacity, soundVolume: bubble.soundVolume, themeColor: bubble.themeColor)
            settingsController = AemisSettingsWindowController(
                store: conversationStore,
                presetID: activePresetID,
                presentation: presentation,
                ambientEnabled: bubble.ambientVoiceEnabled,
                ambientIntervalMinutes: bubble.ambientVoiceIntervalMinutes,
                taskAlerts: CodexTaskAlertSettings.load(),
                onPresentationChanged: { [weak self] presentation in self?.applyPresentation(presentation) },
                onAmbientChanged: { [weak self] enabled, interval in self?.setAmbientVoice(enabled: enabled, intervalMinutes: interval) },
                onTaskAlertsChanged: { _ in },
                onTaskAlertPreview: { [weak self] kind in self?.playTaskAlertAudio(kind) },
                onAction: { [weak self] action in self?.runSettingsAction(action) },
                onConfigurationSaved: { [weak self] configuration in self?.savePersona(configuration.persona, forPresetID: self?.activePresetID ?? "default") }
            )
        }
        settingsController?.refreshTaskAlertControls(CodexTaskAlertSettings.load())
        settingsController?.showWindow(nil); settingsController?.window?.makeKeyAndOrderFront(nil); settingsController?.window?.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
    }

    private func runSettingsAction(_ action: AemisSettingsAction) {
        switch action {
        case .chooseMascot: chooseMascot()
        case .savePreset: savePreset()
        case .importPreset: importPresetPack()
        case .exportPreset: exportPresetPack()
        case .editPatMessage: choosePatMessage()
        case .importEventImages: bubble.showMessage(title: "人物图片已固定", body: "不再支持触发换图", detail: "当前圆脑袋会始终保留", duration: 5)
        case .importClickSounds: importClickSounds()
        case .importEventSounds: importEventSounds()
        }
    }
    private func savePersona(_ persona: String, forPresetID presetID: String) {
        guard let index = bubble.presets.firstIndex(where: { $0.id == presetID }) else { return }
        bubble.presets[index].persona = persona
        persistPresets()
    }
    private func toggleBubbleChat() {
        positionMemoryTimer?.invalidate()
        if bubble.chatExpanded {
            collapseBubbleChat()
            return
        }
        let compact = safeCompactFrameForMascot(panel.frame)
        if compact != panel.frame { panel.setFrame(compact, display: true) }
        compactFrameBeforeChat = compact
        bubble.setChatExpanded(true, store: conversationStore, presetID: activePresetID, onWidthChanged: { [weak self] width in self?.resizeBubbleChat(width: width) }, onHeightGrowthRequested: { [weak self] delta in self?.growBubbleChat(by: delta) })
        panel.isMovableByWindowBackground = false
        panel.styleMask.remove(.nonactivatingPanel)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(compact) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let target = expandedChatFrame(width: max(460, min(620, compact.width * 1.9)), height: 560, compact: compact, screen: screen)
        animateChatPanel(from: compact, to: target, mascotScreenX: compact.midX, mascotScreenY: compact.minY, duration: 0.42)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in self?.bubble.focusChatInput() }
    }

    private func collapseBubbleChat() {
        chatFrameTimer?.invalidate()
        let current = panel.frame
        var target = compactFrameBeforeChat ?? NSRect(origin: current.origin, size: compactPanelSize)
        target.size = compactPanelSize
        target = safeCompactFrameForMascot(target)
        bubble.setChatExpanded(false)
        panel.isMovableByWindowBackground = true
        panel.styleMask.insert(.nonactivatingPanel)
        // Expanded panels use an offset local anchor near screen edges. Carrying
        // that anchor into the narrow compact panel places the mascot outside its
        // bounds. Clear it before resizing and restore the exact saved compact
        // frame in one transaction.
        bubble.mascotAnchorX = nil
        compactFrameBeforeChat = nil
        isChatTransitioning = true
        panel.setFrame(target, display: true)
        panel.setContentSize(target.size)
        panel.setFrameOrigin(target.origin)
        bubble.frame = NSRect(origin: .zero, size: target.size)
        bubble.needsLayout = true
        bubble.needsDisplay = true
        DispatchQueue.main.async { [weak self] in
            self?.isChatTransitioning = false
            self?.panel.displayIfNeeded()
        }
    }

    private func resizeBubbleChat(width: CGFloat) {
        guard bubble.chatExpanded else { return }
        let compact = compactFrameBeforeChat ?? panel.frame
        let current = panel.frame
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(current) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let target = expandedChatFrame(width: width, height: current.height, compact: compact, screen: screen)
        animateChatPanel(from: current, to: target, mascotScreenX: bubble.mascotAnchorX.map { current.minX + $0 } ?? compact.midX, mascotScreenY: current.minY, duration: 0.2)
    }

    private func growBubbleChat(by delta: CGFloat) {
        guard bubble.chatExpanded, delta > 0 else { return }
        let current = panel.frame
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(current) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let maximum = max(current.height, screen.maxY - current.minY - 12)
        let height = min(maximum, current.height + delta)
        guard height > current.height + 1 else { return }
        let target = NSRect(x: current.minX, y: current.minY, width: current.width, height: height)
        animateChatPanel(from: current, to: target, mascotScreenX: bubble.mascotAnchorX.map { current.minX + $0 } ?? current.midX, mascotScreenY: current.minY, duration: 0.24)
    }

    private var compactPanelSize: NSSize {
        NSSize(width: max(252 * bubble.bubbleSize, ceil(bubble.mascotStageWidth + 12)), height: ceil(bubble.mascotAreaHeight + 9 + 111 * bubble.bubbleSize + 8))
    }

    private func expandedChatFrame(width requestedWidth: CGFloat, height requestedHeight: CGFloat, compact: NSRect, screen: NSRect) -> NSRect {
        let margin: CGFloat = 12
        let width = min(max(440, requestedWidth), max(440, screen.width - margin * 2))
        let availableHeight = max(compact.height, screen.maxY - compact.minY - margin)
        let height = min(max(560, requestedHeight), availableHeight)
        let centeredX = compact.midX - width / 2
        let x = min(max(centeredX, screen.minX + margin), screen.maxX - width - margin)
        return NSRect(x: x, y: compact.minY, width: width, height: height)
    }

    private func rememberedCompactFrame(fallback: NSRect) -> NSRect {
        var target = fallback
        target.size = compactPanelSize
        if bubble.positionMemoryEnabled {
            if let remembered = rememberedPlacement(),
               let anchored = remembered.frame(size: target.size, screens: currentPetDisplays()) {
                target = anchored
                temporaryFallbackFrame = nil
            } else if let temporaryFallbackFrame {
                target.origin = temporaryFallbackFrame.origin
            } else if rememberedPlacement() == nil, let legacy = legacyRememberedFrame() {
                target.origin = legacy.origin
            }
        }
        return safeCompactFrameForMascot(target)
    }

    /// Saved positions may come from a monitor that is no longer connected.
    /// Always keep the complete pet reachable on one of the current displays.
    private func clampedToVisibleScreen(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens.map(\.visibleFrame)
        if screens.contains(where: { $0.intersects(frame) && $0.intersection(frame).width >= min(80, frame.width) }) { return frame }
        guard let screen = NSScreen.main?.visibleFrame ?? screens.first else { return frame }
        let margin: CGFloat = 12
        var result = frame
        result.origin.x = min(max(result.minX, screen.minX + margin), screen.maxX - result.width - margin)
        result.origin.y = min(max(result.minY, screen.minY + margin), screen.maxY - result.height - margin)
        return result
    }

    /// The complete mascot stays reachable on one display. This compact frame is
    /// also the immutable screen anchor used while the chat grows above it.
    private func safeCompactFrameForMascot(_ frame: NSRect) -> NSRect {
        var result = frame
        result.size = compactPanelSize
        let probe = NSPoint(x: frame.midX, y: frame.minY + min(frame.height, bubble.mascotAreaHeight) / 2)
        let candidate = NSScreen.screens.first(where: { $0.visibleFrame.contains(probe) })?.visibleFrame
            ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let screen = candidate else { return result }
        let margin: CGFloat = 12
        let proposedX = frame.midX - result.width / 2
        result.origin.x = result.width <= screen.width - margin * 2
            ? min(max(proposedX, screen.minX + margin), screen.maxX - margin - result.width)
            : screen.minX
        result.origin.y = min(max(frame.minY, screen.minY + margin), screen.maxY - result.height - margin)
        return result
    }

    private func animateChatPanel(from start: NSRect, to target: NSRect, mascotScreenX: CGFloat, mascotScreenY: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        chatFrameTimer?.invalidate()
        isChatTransitioning = true
        // Interpolating the host window makes AppKit scale its entire backing
        // view for a few frames, visibly compressing and kicking the mascot down.
        // The embedded chat already fades in/out, so place the final host frame
        // once and keep the mascot's screen coordinates pixel-stable.
        var anchoredTarget = target
        anchoredTarget.origin.y = mascotScreenY
        bubble.mascotAnchorX = mascotScreenX - anchoredTarget.minX
        panel.setFrame(anchoredTarget, display: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + min(0.22, max(0.08, duration * 0.5))) { [weak self] in
            self?.isChatTransitioning = false
            completion?()
        }
    }

    private func animatePanel(to frame: NSRect, duration: TimeInterval) {
        isReturningToRememberedPosition = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in self?.isReturningToRememberedPosition = false }
    }
    private func startFocus() {
        let alert = NSAlert(); alert.messageText = "开始和爱弥斯一起专注"; alert.informativeText = "倒计时结束后会在气泡里提醒，并触发“专注计时结束”的专属图片或语音。"
        alert.addButton(withTitle: "25 分钟"); alert.addButton(withTitle: "50 分钟"); alert.addButton(withTitle: "取消")
        let result = alert.runModal(); guard result != .alertThirdButtonReturn else { return }
        let minutes = result == .alertFirstButtonReturn ? 25 : 50
        bubble.focusEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60)); focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateFocus() }
        bubble.showMessage(title: "专注模式开始", body: "\(minutes) 分钟", detail: "爱弥斯会在结束时叫你休息")
    }
    private func stopFocus() { focusTimer?.invalidate(); focusTimer = nil; bubble.focusEndsAt = nil; bubble.showMessage(title: "专注计时已结束", body: "下次再一起努力", detail: "也记得活动一下身体") }
    private func updateFocus() {
        guard let end = bubble.focusEndsAt else { focusTimer?.invalidate(); return }
        guard end <= Date() else { bubble.needsDisplay = true; return }
        focusTimer?.invalidate(); focusTimer = nil; bubble.focusEndsAt = nil; bubble.trigger(.focusComplete)
        bubble.showMessage(title: "专注完成！", body: "辛苦啦", detail: "喝口水，休息一下再继续吧")
    }
    private func loadAppearance() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "displayMode"), let mode = DisplayMode(rawValue: raw) { bubble.displayMode = mode }
        let savedSize = defaults.double(forKey: "mascotSize"); if savedSize > 0 { bubble.mascotSize = savedSize }
        let savedBubbleSize = defaults.double(forKey: "bubbleSize"); if savedBubbleSize > 0 { bubble.bubbleSize = savedBubbleSize }
        let savedOpacity = defaults.double(forKey: "bubbleOpacity"); if savedOpacity > 0 { bubble.bubbleOpacity = savedOpacity }
        if let data = defaults.data(forKey: "bubbleColor"), let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) { bubble.themeColor = color }
        if defaults.object(forKey: "clickSoundEnabled") != nil { bubble.clickSoundEnabled = defaults.bool(forKey: "clickSoundEnabled") }
        if let raw = defaults.string(forKey: "tapSound"), let sound = TapSound(rawValue: raw) { bubble.tapSound = sound }
        bubble.customSoundPath = defaults.string(forKey: "customSoundPath")
        if defaults.object(forKey: "soundVolume") != nil { bubble.soundVolume = defaults.float(forKey: "soundVolume") }
        if defaults.object(forKey: "ambientVoiceEnabled") != nil { bubble.ambientVoiceEnabled = defaults.bool(forKey: "ambientVoiceEnabled") }
        if defaults.object(forKey: "ambientVoiceIntervalMinutes") != nil { bubble.ambientVoiceIntervalMinutes = max(3, min(120, defaults.integer(forKey: "ambientVoiceIntervalMinutes"))) }
        defaults.removeObject(forKey: "automaticSkinEnabled")
        if let raw = defaults.string(forKey: "particleStyle"), let style = ParticleStyle(rawValue: raw) { bubble.particleStyle = style }
        if defaults.object(forKey: "positionMemoryEnabled") != nil { bubble.positionMemoryEnabled = defaults.bool(forKey: "positionMemoryEnabled") }
        if let text = defaults.string(forKey: "patMessage"), !text.isEmpty { bubble.patMessage = text }
        let today = Self.dayKey(); if defaults.string(forKey: "interactionDay") == today { bubble.todayInteractions = defaults.integer(forKey: "todayInteractions") }
        if let data = defaults.data(forKey: "characterPresets"), let presets = try? JSONDecoder().decode([CharacterPreset].self, from: data) { bubble.presets = presets }
        if let data = defaults.data(forKey: "eventImages"), let assets = try? JSONDecoder().decode([TriggeredAsset].self, from: data) { bubble.eventImages = assets }
        if let data = defaults.data(forKey: "eventSounds"), let assets = try? JSONDecoder().decode([TriggeredAsset].self, from: data) { bubble.eventSounds = assets }
        bubble.clickSoundPaths = defaults.stringArray(forKey: "clickSoundPaths") ?? []
        if bubble.selectedBuiltInMascotID == "aemis", defaults.integer(forKey: "aemisBubblePaletteVersion") == 1 {
            let originalPink = BuiltInCharacterProfile.profile(for: "aemis").bubbleFill
            bubble.themeColor = originalPink
            bubble.bubbleOpacity = 0.97
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: originalPink, requiringSecureCoding: false) { defaults.set(data, forKey: "bubbleColor") }
            defaults.set(0.97, forKey: "bubbleOpacity")
            defaults.set(2, forKey: "aemisBubblePaletteVersion")
        }
    }
    private func customMascot() -> NSImage? { UserDefaults.standard.string(forKey: "mascotPath").flatMap { NSImage(contentsOfFile: $0) } }
    private func builtInMascot(id: String, in folder: URL? = nil) -> NSImage? {
        let filenames = ["aemis": "aemis.png"]
        guard let filename = filenames[id] else { return nil }
        let base = folder ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        return NSImage(contentsOf: base.appendingPathComponent("assets/wuthering-dango-selected/\(filename)"))
    }
    private func selectBuiltInMascot(id: String) {
        guard let image = builtInMascot(id: id) else {
            bubble.showMessage(title: "人物资源读取失败", body: "没有找到对应图片", detail: "请重新启动或检查资源文件", duration: 4)
            return
        }
        bubble.mascot = image
        bubble.selectedBuiltInMascotID = id
        let profile = BuiltInCharacterProfile.profile(for: id)
        bubble.themeColor = profile.bubbleFill
        UserDefaults.standard.set(id, forKey: "builtInMascotID")
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: profile.bubbleFill, requiringSecureCoding: false) { UserDefaults.standard.set(data, forKey: "bubbleColor") }
        UserDefaults.standard.removeObject(forKey: "mascotPath")
        resizePanelToMascot()
        bubble.showMessage(title: profile.name, body: "✦ 已切换人物", detail: "主题与人设已同步", duration: 3)
    }
    private func chooseMascot() {
        NSApp.activate(ignoringOtherApps: true)
        let chooser = NSOpenPanel(); chooser.title = "选择已抠图的透明 PNG 人物"; chooser.message = "请选择透明背景 PNG；它会在右键菜单中保存为当前人物。"; chooser.allowedContentTypes = [.png]; chooser.allowsMultipleSelection = false
        chooser.begin { [weak self] response in
            guard response == .OK, let url = chooser.url, let image = NSImage(contentsOf: url) else { return }
            self?.bubble.mascot = image; self?.resizePanelToMascot(); UserDefaults.standard.set(url.path, forKey: "mascotPath"); UserDefaults.standard.removeObject(forKey: "builtInMascotID")
        }
    }
    private func chooseColor() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "聊天框颜色"; alert.informativeText = "选好颜色后按「确定」才会应用；按「取消」会保持当前颜色。"
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 180, height: 32)); colorWell.color = bubble.themeColor
        alert.accessoryView = colorWell
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        bubble.themeColor = colorWell.color
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: colorWell.color, requiringSecureCoding: false) { UserDefaults.standard.set(data, forKey: "bubbleColor") }
    }
    private func choosePatMessage() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "爱弥斯的连点台词"; alert.informativeText = "连续点击 15 次后，爱弥斯会说这句话。"
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 26)); field.stringValue = bubble.patMessage; alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        bubble.patMessage = text; UserDefaults.standard.set(text, forKey: "patMessage")
    }
    private func chooseCustomSound() {
        NSApp.activate(ignoringOtherApps: true)
        let chooser = NSOpenPanel(); chooser.title = "导入爱弥斯的点击音效"; chooser.message = "请选择时长不超过 15 秒的音频。"; chooser.allowedContentTypes = [.audio]; chooser.allowsMultipleSelection = false
        chooser.begin { [weak self] response in
            guard response == .OK, let url = chooser.url else { return }
            let asset = AVURLAsset(url: url)
            Task { @MainActor [weak self] in
                let duration = try? await asset.load(.duration).seconds
                guard let self, let duration, duration.isFinite, duration > 0, duration <= 15 else { self?.showError("音效时长需要在 15 秒以内。"); return }
                self.bubble.customSoundPath = url.path; self.bubble.tapSound = .custom
                UserDefaults.standard.set(url.path, forKey: "customSoundPath"); UserDefaults.standard.set(TapSound.custom.rawValue, forKey: "tapSound")
            }
        }
    }
    private func importClickSounds() {
        let panel = NSOpenPanel(); panel.title = "批量导入爱弥斯点击语音"; panel.message = "支持常见音频格式；每段需在 15 秒以内，会随机播放。"; panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in guard response == .OK, let self else { return }; self.validateAudio(panel.urls) { valid in self.bubble.clickSoundPaths += valid.map(\.path); self.persistInteractionAssets() } }
    }
    private func importEventSounds() { chooseTrigger(title: "为哪种情况绑定触发语音？") { [weak self] trigger in
        let panel = NSOpenPanel(); panel.title = "批量导入触发语音"; panel.message = "支持常见音频格式；每段需在 15 秒以内。"; panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = true
        panel.begin { response in guard response == .OK, let self else { return }; self.validateAudio(panel.urls) { valid in self.bubble.eventSounds += valid.map { TriggeredAsset(id: UUID().uuidString, trigger: trigger.rawValue, path: $0.path) }; self.persistInteractionAssets() } }
    } }
    private func chooseTrigger(title: String, completion: @escaping (InteractionTrigger) -> Void) {
        NSApp.activate(ignoringOtherApps: true); let alert = NSAlert(); alert.messageText = title; alert.informativeText = "导入后，可在同一人物预设中保存并分享。"; alert.addButton(withTitle: "继续"); alert.addButton(withTitle: "取消")
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 28)); InteractionTrigger.allCases.forEach { picker.addItem(withTitle: $0.title); picker.lastItem?.representedObject = $0.rawValue }; alert.accessoryView = picker
        guard alert.runModal() == .alertFirstButtonReturn, let raw = picker.selectedItem?.representedObject as? String, let trigger = InteractionTrigger(rawValue: raw) else { return }; completion(trigger)
    }
    private func validateAudio(_ urls: [URL], completion: @escaping ([URL]) -> Void) {
        Task { @MainActor in
            var valid: [URL] = []
            for url in urls { if let duration = try? await AVURLAsset(url: url).load(.duration).seconds, duration.isFinite, duration > 0, duration <= 15 { valid.append(url) } }
            if valid.count < urls.count { showError("部分音频超过 15 秒或无法读取，未被导入。") }; completion(valid)
        }
    }
    private func installPreparedVoiceLibraryIfAvailable(in appFolder: URL) {
        let completeFolder = appFolder.appendingPathComponent("voice-assets/processed/完整句", isDirectory: true)
        let legacyFolder = appFolder.appendingPathComponent("voice-assets/processed/短句", isDirectory: true)
        let folder = FileManager.default.fileExists(atPath: completeFolder.path) ? completeFolder : legacyFolder
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        let audio = files.filter { ["mp3", "m4a", "wav", "aiff", "aac"].contains($0.pathExtension.lowercased()) }
        guard !audio.isEmpty else { return }
        let preparedPaths = Set(audio.map(\.path))
        bubble.eventSounds.removeAll { preparedPaths.contains($0.path) }
        for file in audio {
            bubble.eventSounds.append(TriggeredAsset(id: UUID().uuidString, trigger: InteractionTrigger.tenTaps.rawValue, path: file.path))
        }
        persistInteractionAssets()
    }
    private func persistInteractionAssets() {
        let defaults = UserDefaults.standard; if let data = try? JSONEncoder().encode(bubble.eventImages) { defaults.set(data, forKey: "eventImages") }; if let data = try? JSONEncoder().encode(bubble.eventSounds) { defaults.set(data, forKey: "eventSounds") }; defaults.set(bubble.clickSoundPaths, forKey: "clickSoundPaths")
    }
    private func showError(_ message: String) { let alert = NSAlert(); alert.messageText = "无法使用这个音效"; alert.informativeText = message; alert.addButton(withTitle: "好"); alert.runModal() }
    private func setMascotSize(_ value: CGFloat) {
        // Keep the speech-bubble/tail junction fixed on screen. The mascot grows
        // downward from that point instead of pushing the bubble around.
        let bubbleJunctionY = panel.frame.minY + bubble.mascotAreaHeight - 1
        let mascotScreenX = panel.frame.minX + (bubble.mascotAnchorX ?? panel.frame.width / 2)
        bubble.mascotSize = value
        resizePanelToMascot(bubbleJunctionY: bubbleJunctionY, mascotScreenX: mascotScreenX)
        UserDefaults.standard.set(Double(value), forKey: "mascotSize")
    }
    private func setBubbleSize(_ value: CGFloat) {
        let bubbleJunctionY = panel.frame.minY + bubble.mascotAreaHeight - 1
        let mascotScreenX = panel.frame.minX + (bubble.mascotAnchorX ?? panel.frame.width / 2)
        bubble.bubbleSize = value
        resizePanelToMascot(bubbleJunctionY: bubbleJunctionY, mascotScreenX: mascotScreenX)
        UserDefaults.standard.set(Double(value), forKey: "bubbleSize")
    }
    private func setBubbleOpacity(_ value: CGFloat) { bubble.bubbleOpacity = value; UserDefaults.standard.set(Double(value), forKey: "bubbleOpacity") }
    private func setDisplayMode(_ mode: DisplayMode) { bubble.displayMode = mode; UserDefaults.standard.set(mode.rawValue, forKey: "displayMode"); refresh() }
    private func toggleClickSound() { bubble.clickSoundEnabled.toggle(); UserDefaults.standard.set(bubble.clickSoundEnabled, forKey: "clickSoundEnabled") }
    private func setTapSound(_ sound: TapSound) { bubble.tapSound = sound; UserDefaults.standard.set(sound.rawValue, forKey: "tapSound") }
    private func setSoundVolume(_ volume: Float) { bubble.soundVolume = volume; UserDefaults.standard.set(volume, forKey: "soundVolume") }
    private func applyPresentation(_ presentation: AemisPresentationSettings) {
        if abs(bubble.mascotSize - presentation.mascotSize) > 0.0001 { setMascotSize(presentation.mascotSize) }
        if abs(bubble.bubbleSize - presentation.bubbleSize) > 0.0001 { setBubbleSize(presentation.bubbleSize) }
        if abs(bubble.bubbleOpacity - presentation.bubbleOpacity) > 0.0001 { setBubbleOpacity(presentation.bubbleOpacity) }
        if abs(bubble.soundVolume - presentation.soundVolume) > 0.0001 { setSoundVolume(presentation.soundVolume) }
        if bubble.themeColor != presentation.themeColor {
            bubble.themeColor = presentation.themeColor
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: presentation.themeColor, requiringSecureCoding: false) { UserDefaults.standard.set(data, forKey: "bubbleColor") }
        }
    }
    private func setAmbientVoice(enabled: Bool, intervalMinutes: Int) {
        bubble.configureAmbientVoice(enabled: enabled, intervalMinutes: intervalMinutes)
        UserDefaults.standard.set(enabled, forKey: "ambientVoiceEnabled")
        UserDefaults.standard.set(bubble.ambientVoiceIntervalMinutes, forKey: "ambientVoiceIntervalMinutes")
    }
    private func savePreset() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "保存爱弥斯人物预设"; alert.informativeText = "会保存当前人物、颜色、连点台词、音效、音量与大小。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 26)); field.stringValue = "爱弥斯预设 \(bubble.presets.count + 1)"; alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }
        bubble.presets.append(currentPreset(named: name))
        persistPresets()
    }
    private func exportPresetPack() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel(); panel.title = "导出爱弥斯人物预设包"; panel.nameFieldStringValue = "爱弥斯人物预设.aemispreset"; panel.allowedContentTypes = [UTType(filenameExtension: "aemispreset") ?? .zip]
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            let fileManager = FileManager.default; let work = fileManager.temporaryDirectory.appendingPathComponent("aemis-pack-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: work) }
            do {
                try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
                var preset = self.currentPreset(named: self.bubble.presets.last?.name ?? "爱弥斯人物预设")
                let defaultAsset = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("艾弥斯透明人物.png")
                let mascotSource = preset.mascotPath.map(URL.init(fileURLWithPath:)) ?? defaultAsset
                guard fileManager.fileExists(atPath: mascotSource.path) else { throw NSError(domain: "Aemis", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到人物 PNG，无法导出。"]) }
                try fileManager.copyItem(at: mascotSource, to: work.appendingPathComponent("mascot.png")); preset.mascotPath = "mascot.png"
                if let soundPath = preset.customSoundPath, fileManager.fileExists(atPath: soundPath) {
                    let ext = URL(fileURLWithPath: soundPath).pathExtension.isEmpty ? "audio" : URL(fileURLWithPath: soundPath).pathExtension
                    let name = "sound.\(ext)"; try fileManager.copyItem(at: URL(fileURLWithPath: soundPath), to: work.appendingPathComponent(name)); preset.customSoundPath = name
                } else { preset.customSoundPath = nil; if preset.tapSound == TapSound.custom.rawValue { preset.tapSound = TapSound.basso.rawValue } }
                preset.eventImages = try self.copyTriggeredAssets(preset.eventImages ?? [], prefix: "event-image", into: work)
                preset.eventSounds = try self.copyTriggeredAssets(preset.eventSounds ?? [], prefix: "event-sound", into: work)
                preset.clickSoundPaths = try self.copyPaths(preset.clickSoundPaths ?? [], prefix: "click-sound", into: work)
                try JSONEncoder().encode(PresetPack(formatVersion: 1, preset: preset)).write(to: work.appendingPathComponent("preset.json"))
                try self.runDitto(arguments: ["-c", "-k", "--keepParent", work.path, destination.path])
            } catch { self.showError(error.localizedDescription) }
        }
    }
    private func importPresetPack() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); panel.title = "导入爱弥斯人物预设包"; panel.message = "请选择 .aemispreset 文件。"; panel.allowedContentTypes = [UTType(filenameExtension: "aemispreset") ?? .zip]; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let source = panel.url, let self else { return }
            let fileManager = FileManager.default; let unpack = fileManager.temporaryDirectory.appendingPathComponent("aemis-unpack-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: unpack) }
            do {
                try fileManager.createDirectory(at: unpack, withIntermediateDirectories: true); try self.runDitto(arguments: ["-x", "-k", source.path, unpack.path])
                guard let manifestURL = self.findFile(named: "preset.json", inside: unpack) else { throw NSError(domain: "Aemis", code: 2, userInfo: [NSLocalizedDescriptionKey: "这不是有效的爱弥斯预设包。"]) }
                var pack = try JSONDecoder().decode(PresetPack.self, from: Data(contentsOf: manifestURL)); guard pack.formatVersion == 1 else { throw NSError(domain: "Aemis", code: 3, userInfo: [NSLocalizedDescriptionKey: "预设包版本暂不支持。"]) }
                let storage = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexTokenPet/ImportedPresets/\(UUID().uuidString)", isDirectory: true)
                try fileManager.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true); try fileManager.copyItem(at: manifestURL.deletingLastPathComponent(), to: storage)
                if let path = pack.preset.mascotPath { pack.preset.mascotPath = storage.appendingPathComponent(path).path }
                if let path = pack.preset.customSoundPath { pack.preset.customSoundPath = storage.appendingPathComponent(path).path }
                pack.preset.eventImages = (pack.preset.eventImages ?? []).map { TriggeredAsset(id: $0.id, trigger: $0.trigger, path: storage.appendingPathComponent(URL(fileURLWithPath: $0.path).lastPathComponent).path) }
                pack.preset.eventSounds = (pack.preset.eventSounds ?? []).map { TriggeredAsset(id: $0.id, trigger: $0.trigger, path: storage.appendingPathComponent(URL(fileURLWithPath: $0.path).lastPathComponent).path) }
                pack.preset.clickSoundPaths = (pack.preset.clickSoundPaths ?? []).map { storage.appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent).path }
                pack.preset.name += "（导入）"; pack.preset = CharacterPreset(id: UUID().uuidString, name: pack.preset.name, mascotPath: pack.preset.mascotPath, color: pack.preset.color, mascotSize: pack.preset.mascotSize, bubbleSize: pack.preset.bubbleSize, patMessage: pack.preset.patMessage, tapSound: pack.preset.tapSound, customSoundPath: pack.preset.customSoundPath, soundVolume: pack.preset.soundVolume, eventImages: pack.preset.eventImages, eventSounds: pack.preset.eventSounds, clickSoundPaths: pack.preset.clickSoundPaths, persona: pack.preset.persona)
                self.bubble.presets.append(pack.preset); self.persistPresets(); self.applyPreset(id: pack.preset.id)
            } catch { self.showError(error.localizedDescription) }
        }
    }
    private func runDitto(arguments: [String]) throws { let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); process.arguments = arguments; try process.run(); process.waitUntilExit(); if process.terminationStatus != 0 { throw NSError(domain: "Aemis", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "预设包压缩或解压失败。"]) } }
    private func findFile(named name: String, inside folder: URL) -> URL? { guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return nil }; for case let url as URL in enumerator where url.lastPathComponent == name { return url }; return nil }
    private func copyTriggeredAssets(_ assets: [TriggeredAsset], prefix: String, into folder: URL) throws -> [TriggeredAsset] {
        let fileManager = FileManager.default
        return try assets.compactMap { asset in
            guard fileManager.fileExists(atPath: asset.path) else { return nil }
            let ext = URL(fileURLWithPath: asset.path).pathExtension; let name = "\(prefix)-\(asset.id).\(ext)"; try fileManager.copyItem(at: URL(fileURLWithPath: asset.path), to: folder.appendingPathComponent(name)); return TriggeredAsset(id: asset.id, trigger: asset.trigger, path: name)
        }
    }
    private func copyPaths(_ paths: [String], prefix: String, into folder: URL) throws -> [String] {
        let fileManager = FileManager.default
        return try paths.compactMap { path in guard fileManager.fileExists(atPath: path) else { return nil }; let ext = URL(fileURLWithPath: path).pathExtension; let name = "\(prefix)-\(UUID().uuidString).\(ext)"; try fileManager.copyItem(at: URL(fileURLWithPath: path), to: folder.appendingPathComponent(name)); return name }
    }
    private func applyPreset(id: String) {
        guard let preset = bubble.presets.first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: "activePresetID")
        bubble.themeColor = NSColor(calibratedRed: preset.color.red, green: preset.color.green, blue: preset.color.blue, alpha: preset.color.alpha)
        bubble.mascotSize = preset.mascotSize; bubble.bubbleSize = preset.bubbleSize; bubble.patMessage = preset.patMessage; bubble.tapSound = TapSound(rawValue: preset.tapSound) ?? .basso; bubble.customSoundPath = preset.customSoundPath; bubble.soundVolume = preset.soundVolume; bubble.eventImages = preset.eventImages ?? []; bubble.eventSounds = preset.eventSounds ?? []; bubble.clickSoundPaths = preset.clickSoundPaths ?? []
        if let path = preset.mascotPath, let image = NSImage(contentsOfFile: path) { bubble.mascot = image; UserDefaults.standard.set(path, forKey: "mascotPath") }
        else { let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(); bubble.mascot = NSImage(contentsOf: folder.appendingPathComponent("艾弥斯透明人物.png")); UserDefaults.standard.removeObject(forKey: "mascotPath") }
        if let persona = preset.persona, !persona.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var configuration = AemisAIConfiguration.load(); configuration.persona = persona; configuration.save()
        }
        saveCurrentAppearance(); resizePanelToMascot()
    }
    private func persistPresets() { if let data = try? JSONEncoder().encode(bubble.presets) { UserDefaults.standard.set(data, forKey: "characterPresets") } }
    private func currentPreset(named name: String) -> CharacterPreset { CharacterPreset(id: UUID().uuidString, name: name, mascotPath: UserDefaults.standard.string(forKey: "mascotPath"), color: rgba(bubble.themeColor), mascotSize: bubble.mascotSize, bubbleSize: bubble.bubbleSize, patMessage: bubble.patMessage, tapSound: bubble.tapSound.rawValue, customSoundPath: bubble.customSoundPath, soundVolume: bubble.soundVolume, eventImages: bubble.eventImages, eventSounds: bubble.eventSounds, clickSoundPaths: bubble.clickSoundPaths, persona: AemisAIConfiguration.load().persona) }
    private func createDefaultPresetIfNeeded() { guard bubble.presets.isEmpty else { return }; bubble.presets = [currentPreset(named: "爱弥斯 · 默认")]; persistPresets() }
    private func rgba(_ color: NSColor) -> SavedColor { let c = color.usingColorSpace(.deviceRGB) ?? color; return SavedColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent) }
    private func saveCurrentAppearance() {
        let defaults = UserDefaults.standard; defaults.set(Double(bubble.mascotSize), forKey: "mascotSize"); defaults.set(Double(bubble.bubbleSize), forKey: "bubbleSize"); defaults.set(Double(bubble.bubbleOpacity), forKey: "bubbleOpacity"); defaults.set(bubble.patMessage, forKey: "patMessage"); defaults.set(bubble.tapSound.rawValue, forKey: "tapSound"); defaults.set(bubble.customSoundPath, forKey: "customSoundPath"); defaults.set(bubble.soundVolume, forKey: "soundVolume")
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: bubble.themeColor, requiringSecureCoding: false) { defaults.set(data, forKey: "bubbleColor") }
    }
    private func rememberPosition() {
        positionMemoryTimer?.invalidate()
        bubble.positionMemoryEnabled.toggle()
        UserDefaults.standard.set(bubble.positionMemoryEnabled, forKey: "positionMemoryEnabled")
        if bubble.positionMemoryEnabled {
            saveRememberedPosition()
            bubble.showMessage(title: "位置记忆已开启", body: "✦ 记住这里啦", detail: "拖动到别处停留 2 秒，就会回来", duration: 3)
        } else {
            bubble.showMessage(title: "位置记忆已关闭", body: "这次不追着你啦", detail: "下次开启时会重新记住当前位置", duration: 3)
        }
    }

    private func saveCurrentPositionAsMemory() {
        guard !bubble.chatExpanded else { return }
        positionMemoryTimer?.invalidate()
        bubble.positionMemoryEnabled = true
        UserDefaults.standard.set(true, forKey: "positionMemoryEnabled")
        saveRememberedPosition()
        bubble.showMessage(title: "已记住当前位置", body: "✦ 就待在这里", detail: "下次开机仍会回到这块屏幕", duration: 3)
    }

    private func saveRememberedPosition() {
        guard let placement = PetDisplayPlacement.capture(frame: panel.frame, screens: currentPetDisplays()) else { return }
        savePlacement(placement)
        temporaryFallbackFrame = nil
        // Keep the old coordinates only as a migration fallback for older builds.
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "panelX")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "panelY")
    }

    private func restorePositionIfAvailable() {
        guard bubble.positionMemoryEnabled else { return }
        let displays = currentPetDisplays()
        if let remembered = rememberedPlacement() {
            if let target = remembered.frame(size: compactPanelSize, screens: displays) {
                movePanelWithoutRemembering(to: target)
            } else {
                temporaryFallbackFrame = panel.frame
            }
        } else if let legacy = legacyRememberedFrame(),
                  let migrated = PetDisplayPlacement.capture(frame: legacy, screens: displays) {
            savePlacement(migrated)
            movePanelWithoutRemembering(to: migrated.frame(size: compactPanelSize, screens: displays) ?? legacy)
        }
    }

    @objc private func panelDidMove(_ notification: Notification) {
        guard bubble.positionMemoryEnabled, !bubble.chatExpanded, !isReturningToRememberedPosition, !isChatTransitioning else { return }
        guard let target = returnTargetFrame()?.origin else { return }
        guard hypot(panel.frame.origin.x - target.x, panel.frame.origin.y - target.y) > 2 else { return }
        positionMemoryTimer?.invalidate()
        positionMemoryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.returnToRememberedPosition() }
    }

    private func returnToRememberedPosition() {
        guard bubble.positionMemoryEnabled, !bubble.chatExpanded else { return }
        guard let target = returnTargetFrame() else { return }
        animatePanel(to: target, duration: 0.58)
        bubble.showMessage(title: "回到记忆点", body: "✦ 我回来啦", detail: "位置记忆正在生效", duration: 2.4)
    }

    private func returnTargetFrame() -> NSRect? {
        if let temporaryFallbackFrame { return safeCompactFrameForMascot(temporaryFallbackFrame) }
        if let remembered = rememberedPlacement() {
            return remembered.frame(size: compactPanelSize, screens: currentPetDisplays())
        }
        if let legacy = legacyRememberedFrame(),
           PetDisplayPlacement.capture(frame: legacy, screens: currentPetDisplays()) != nil {
            return safeCompactFrameForMascot(legacy)
        }
        return nil
    }
    private func dock(_ position: DockPosition) {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 20; var frame = panel.frame
        frame.origin.x = (position == .bottomLeft || position == .topLeft) ? screen.minX + margin : screen.maxX - frame.width - margin
        frame.origin.y = (position == .topLeft || position == .topRight) ? screen.maxY - frame.height - margin : screen.minY + margin
        panel.setFrame(frame, display: true, animate: true)
        if bubble.positionMemoryEnabled { saveRememberedPosition() }
    }
    private func recordInteraction() {
        let defaults = UserDefaults.standard; let today = Self.dayKey()
        if defaults.string(forKey: "interactionDay") != today { bubble.todayInteractions = 0; defaults.set(today, forKey: "interactionDay") }
        bubble.todayInteractions += 1; defaults.set(bubble.todayInteractions, forKey: "todayInteractions")
        guard bubble.todayInteractions.isMultiple(of: 50) else { return }
        bubble.trigger(.dailyFiftyTaps)
        bubble.showMessage(title: "爱弥斯好感度 +1", body: "今日第 \(bubble.todayInteractions) 次", detail: "你们已经是默契搭档啦 ✦")
    }
    private static func dayKey() -> String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: Date()) }
    private func resetAppearance() {
        let defaults = UserDefaults.standard; ["mascotPath", "mascotSize", "bubbleSize", "bubbleOpacity", "bubbleColor", "displayMode", "clickSoundEnabled", "tapSound", "customSoundPath", "soundVolume", "patMessage", "positionMemoryEnabled", "panelX", "panelY", placementKey].forEach { defaults.removeObject(forKey: $0) }
        temporaryFallbackFrame = nil
        bubble.themeColor = NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.96, alpha: 0.97); bubble.mascotSize = 1; bubble.bubbleSize = 1; bubble.bubbleOpacity = 0.97; bubble.displayMode = .automatic; bubble.clickSoundEnabled = true; bubble.tapSound = .basso; bubble.customSoundPath = nil; bubble.soundVolume = 0.55; bubble.patMessage = "不要再拍我了"; bubble.positionMemoryEnabled = false; bubble.particleStyle = .stars
        defaults.set(2, forKey: "aemisBubblePaletteVersion")
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(); bubble.mascot = NSImage(contentsOf: folder.appendingPathComponent("艾弥斯透明人物.png")); resizePanelToMascot(); refresh()
    }
    private func resizePanelToMascot(bubbleJunctionY: CGFloat? = nil, mascotScreenX: CGFloat? = nil) {
        guard !bubble.chatExpanded else { return }
        let size = compactPanelSize
        let old = panel.frame
        let anchorX = mascotScreenX ?? old.midX
        let anchorY = bubbleJunctionY.map { $0 - bubble.mascotAreaHeight + 1 } ?? old.minY
        var frame = NSRect(x: anchorX - size.width / 2, y: anchorY, width: size.width, height: size.height)
        if bubble.positionMemoryEnabled, bubbleJunctionY == nil { frame = rememberedCompactFrame(fallback: frame) }
        panel.setFrame(frame, display: true, animate: true); bubble.frame = NSRect(origin: .zero, size: size); bubble.needsDisplay = true
        if bubble.positionMemoryEnabled, bubbleJunctionY != nil {
            if temporaryFallbackFrame != nil { temporaryFallbackFrame = frame }
            else if let placement = PetDisplayPlacement.capture(frame: frame, screens: currentPetDisplays(), preferredID: rememberedPlacement()?.displayID) { savePlacement(placement) }
        }
    }
    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let context = self?.frontmostAppReader.current()
            let value = self?.reader.latestSnapshot(codexIsFrontmost: context?.isCodex == true)
            DispatchQueue.main.async {
                guard let self else { return }
                if let name = context?.appName, let previous = self.previousFrontmostApp, previous != name { self.bubble.trigger(.appSwitch) }
                self.previousFrontmostApp = context?.appName
                self.bubble.snapshot = value; self.bubble.frontmostContext = context
            }
        }
    }
}
