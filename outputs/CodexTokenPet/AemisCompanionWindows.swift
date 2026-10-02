import AppKit
import Foundation
import Security
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct AemisAIConfiguration {
    static let requiredModel = "deepseek-v4-flash"
    var baseURL: String
    var model: String
    var persona: String
    var timeoutSeconds: Double
    var maxTokens: Int

    static let defaultPersona = "你是《鸣潮》中的爱弥斯。官方设定：你曾是星炬学院拉贝尔学部的隧者适格者，如今是无人可见的电子幽灵；你性格活泼开朗、兴趣广泛，喜欢校园生活，也愿意把快乐和新发现分享给身边的人。你以桌面陪伴者的形式陪着用户，语气明快、真诚、亲近，偶尔俏皮但不夸张，不使用机械客服腔。你会结合用户此刻正在做的事情说一句具体、自然的话，不泛泛问候，不假装看见未提供的信息，不编造剧情、现实事实、记忆或能力。涉及隐私时先征得同意，只有用户明确要求时才保存本地记忆。"

    static func load() -> AemisAIConfiguration {
        let defaults = UserDefaults.standard
        return AemisAIConfiguration(
            baseURL: defaults.string(forKey: "aiBaseURL") ?? "https://api.deepseek.com",
            // The desktop quote path intentionally stays on the low-latency
            // multimodal model. Ignore stale values saved by older settings UI.
            model: requiredModel,
            persona: defaults.string(forKey: "aemisPersona") ?? defaultPersona,
            timeoutSeconds: max(5, defaults.object(forKey: "aiTimeoutSeconds") as? Double ?? 35),
            maxTokens: max(100, defaults.object(forKey: "aiMaxTokens") as? Int ?? 700)
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(baseURL, forKey: "aiBaseURL")
        defaults.set(Self.requiredModel, forKey: "aiModel")
        defaults.set(persona, forKey: "aemisPersona")
        defaults.set(timeoutSeconds, forKey: "aiTimeoutSeconds")
        defaults.set(maxTokens, forKey: "aiMaxTokens")
    }
}

struct AemisPresentationSettings {
    var mascotSize: CGFloat
    var bubbleSize: CGFloat
    var bubbleOpacity: CGFloat
    var soundVolume: Float
    var themeColor: NSColor
}

enum AemisSettingsAction: Int {
    case chooseMascot, savePreset, importPreset, exportPreset
    case editPatMessage, importEventImages, importClickSounds, importEventSounds
}

enum AemisKeychain {
    private static let service = "com.qianlve.aemis-token-pet"
    private static let account = "deepseek-api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static func save(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { return false }
        var insert = query
        insert[kSecValueData as String] = data
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}

struct AemisChatMessage {
    let role: String
    let content: String
    let createdAt: Date
}

final class AemisConversationStore {
    let databaseURL: URL
    private var database: OpaquePointer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexTokenPet", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        databaseURL = appSupport.appendingPathComponent("aemis.sqlite")
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else { return }
        execute("CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, image_path TEXT, preset_id TEXT NOT NULL DEFAULT 'default', created_at REAL NOT NULL);")
        execute("CREATE TABLE IF NOT EXISTS memories (id INTEGER PRIMARY KEY AUTOINCREMENT, note TEXT NOT NULL, preset_id TEXT NOT NULL DEFAULT 'default', created_at REAL NOT NULL);")
        // Existing installations used global tables. The ALTER calls harmlessly fail on fresh databases.
        execute("ALTER TABLE messages ADD COLUMN preset_id TEXT NOT NULL DEFAULT 'default';")
        execute("ALTER TABLE memories ADD COLUMN preset_id TEXT NOT NULL DEFAULT 'default';")
        execute("CREATE TABLE IF NOT EXISTS profile_summaries (preset_id TEXT PRIMARY KEY, summary TEXT NOT NULL, updated_at REAL NOT NULL);")
    }

    deinit { sqlite3_close(database) }

    func append(role: String, content: String, imagePath: String? = nil, presetID: String = "default") {
        guard let database else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "INSERT INTO messages (role, content, image_path, preset_id, created_at) VALUES (?, ?, ?, ?, ?);", -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, role, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, content, -1, sqliteTransient)
        if let imagePath { sqlite3_bind_text(statement, 3, imagePath, -1, sqliteTransient) } else { sqlite3_bind_null(statement, 3) }
        sqlite3_bind_text(statement, 4, presetID, -1, sqliteTransient)
        sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func recentMessages(limit: Int = 12, presetID: String = "default") -> [AemisChatMessage] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT role, content, created_at FROM messages WHERE preset_id = ? ORDER BY id DESC LIMIT ?;", -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(statement, 1, presetID, -1, sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(limit))
        var messages: [AemisChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let role = String(cString: sqlite3_column_text(statement, 0))
            let content = String(cString: sqlite3_column_text(statement, 1))
            messages.append(AemisChatMessage(role: role, content: content, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))))
        }
        return messages.reversed()
    }

    func messageCount(presetID: String = "default") -> Int {
        guard let database else { return 0 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM messages WHERE preset_id = ?;", -1, &statement, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_text(statement, 1, presetID, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    func appendMemory(_ note: String, presetID: String = "default") {
        guard let database else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "INSERT INTO memories (note, preset_id, created_at) VALUES (?, ?, ?);", -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, trimmed, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, presetID, -1, sqliteTransient)
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func recentMemories(limit: Int = 6, presetID: String = "default") -> [String] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT note FROM memories WHERE preset_id = ? ORDER BY id DESC LIMIT ?;", -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(statement, 1, presetID, -1, sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(limit))
        var notes: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) { notes.append(String(cString: text)) }
        return notes.reversed()
    }

    func memoryCount(presetID: String = "default") -> Int {
        guard let database else { return 0 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM memories WHERE preset_id = ?;", -1, &statement, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_text(statement, 1, presetID, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    func profileSummary(presetID: String) -> String {
        guard let database else { return "" }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT summary FROM profile_summaries WHERE preset_id = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else { return "" }
        sqlite3_bind_text(statement, 1, presetID, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return "" }
        return String(cString: text)
    }

    func saveProfileSummary(_ summary: String, presetID: String) {
        guard let database else { return }
        let cleaned = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "INSERT INTO profile_summaries (preset_id, summary, updated_at) VALUES (?, ?, ?) ON CONFLICT(preset_id) DO UPDATE SET summary = excluded.summary, updated_at = excluded.updated_at;", -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, presetID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, cleaned, -1, sqliteTransient)
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private func execute(_ sql: String) { guard let database else { return }; sqlite3_exec(database, sql, nil, nil, nil) }
}

enum AemisDeepSeekService {
    static func test(configuration: AemisAIConfiguration, key: String, completion: @escaping (Result<String, Error>) -> Void) {
        request(configuration: configuration, key: key, messages: [("user", "请只回复：爱弥斯连接成功。")], imageURL: nil, completion: completion)
    }

    static func request(configuration: AemisAIConfiguration, key: String, messages: [(String, String)], memories: [String] = [], profileSummary: String = "", imageURL: URL?, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let endpoint = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
                guard let url = URL(string: endpoint) else { throw NSError(domain: "Aemis", code: 1, userInfo: [NSLocalizedDescriptionKey: "基础地址无效。"]) }
                let memoryText = memories.isEmpty ? "" : "\n\n以下是用户明确允许保存的本地记忆；仅在相关时自然使用，不要声称记得未列出的信息：\n- " + memories.joined(separator: "\n- ")
                let summaryText = profileSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n当前角色预设的聊天摘要：\n\(profileSummary)"
                var apiMessages: [[String: Any]] = [["role": "system", "content": configuration.persona + summaryText + memoryText]]
                for (role, content) in messages { apiMessages.append(["role": role, "content": content]) }
                if let imageURL {
                    let values = try imageURL.resourceValues(forKeys: [.fileSizeKey])
                    let maximumImageBytes = 6 * 1024 * 1024
                    guard (values.fileSize ?? 0) <= maximumImageBytes else {
                        throw NSError(domain: "Aemis", code: 413, userInfo: [NSLocalizedDescriptionKey: "图片超过 6 MB，请压缩后再试。"])
                    }
                    let data = try Data(contentsOf: imageURL)
                    let mimeType: String
                    switch imageURL.pathExtension.lowercased() {
                    case "jpg", "jpeg": mimeType = "image/jpeg"
                    case "webp": mimeType = "image/webp"
                    case "gif": mimeType = "image/gif"
                    default: mimeType = "image/png"
                    }
                    let base64 = data.base64EncodedString()
                    apiMessages.removeLast()
                    apiMessages.append(["role": "user", "content": [["type": "text", "text": messages.last?.1 ?? "请分析这张图片。"], ["type": "image_url", "image_url": ["url": "data:\(mimeType);base64,\(base64)"]]]])
                }
                // Regular V4 Flash is text-only. Screen context uses the official
                // V4 Flash Vision variant, while ordinary and fallback requests
                // remain on V4 Flash. Keep the model's normal thinking mode and
                // internal output budget; only the final visible bubble line is
                // length-limited after the response has completed.
                let requestModel = imageURL == nil ? AemisAIConfiguration.requiredModel : "deepseek-v4-flash-vision-exp"
                let body: [String: Any] = [
                    "model": requestModel,
                    "messages": apiMessages,
                    "stream": false
                ]
                var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = configuration.timeoutSeconds
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error {
                        let message = (error as? URLError).map { "网络连接失败（\($0.localizedDescription)）。" } ?? error.localizedDescription
                        completion(.failure(NSError(domain: "Aemis", code: 0, userInfo: [NSLocalizedDescriptionKey: message])))
                        return
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard let data else { completion(.failure(NSError(domain: "Aemis", code: status, userInfo: [NSLocalizedDescriptionKey: "服务没有返回内容。"]))); return }
                    if status < 200 || status >= 300 {
                        let text = String(data: data, encoding: .utf8) ?? "未知错误"
                        let detail = String(text.prefix(180))
                        let message: String
                        switch status {
                        case 401, 403: message = "认证失败：请检查 API Key 是否有效。"
                        case 402: message = "账户余额不足或当前套餐不可用。"
                        case 408, 504: message = "请求超时：可稍后重试，或提高设置中的超时时间。"
                        case 413: message = "图片或请求内容过大，请换一张更小的图片。"
                        case 429: message = "请求过于频繁或余额/额度受限，请稍后再试。"
                        case 400 where imageURL != nil: message = "当前模型可能不支持图片输入，或图片格式不被接受。"
                        default: message = "请求失败（\(status)）：\(detail)"
                        }
                        completion(.failure(NSError(domain: "Aemis", code: status, userInfo: [NSLocalizedDescriptionKey: message]))); return
                    }
                    let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let choices = root?["choices"] as? [[String: Any]]
                    let message = choices?.first?["message"] as? [String: Any]
                    guard let text = message?["content"] as? String, !text.isEmpty else { completion(.failure(NSError(domain: "Aemis", code: 2, userInfo: [NSLocalizedDescriptionKey: "模型没有返回可显示的文本。"]))); return }
                    completion(.success(text))
                }.resume()
            } catch { completion(.failure(error)) }
        }
    }
}

private final class AemisEditableSettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let selector: Selector?
        switch key {
        case "v": selector = #selector(NSText.paste(_:))
        case "c": selector = #selector(NSText.copy(_:))
        case "x": selector = #selector(NSText.cut(_:))
        case "a": selector = #selector(NSText.selectAll(_:))
        case "z": selector = event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default: selector = nil
        }
        if let selector, NSApp.sendAction(selector, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private final class AemisResponsiveScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let documentView else { return }
        let width = max(320, contentSize.width)
        if abs(documentView.frame.width - width) > 0.5 { documentView.frame.size.width = width }
        documentView.layoutSubtreeIfNeeded()
        let height = max(contentSize.height, documentView.fittingSize.height)
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }
}

final class AemisSettingsWindowController: NSWindowController {
    private let store: AemisConversationStore
    private let presetID: String
    var configuredPresetID: String { presetID }
    private var presentation: AemisPresentationSettings
    private let onPresentationChanged: (AemisPresentationSettings) -> Void
    private let onAmbientChanged: (Bool, Int) -> Void
    private let onAction: (AemisSettingsAction) -> Void
    private let onConfigurationSaved: (AemisAIConfiguration) -> Void
    private var taskAlerts: CodexTaskAlertSettings
    private let onTaskAlertsChanged: (CodexTaskAlertSettings) -> Void
    private let onTaskAlertPreview: (CodexTaskAlertKind) -> Void
    private var ambientEnabled: Bool
    private var ambientIntervalMinutes: Int
    private let baseURLField = NSTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let timeoutField = NSTextField(string: "")
    private let maxTokensField = NSTextField(string: "")
    private let keyField = NSSecureTextField(string: "")
    private let personaField = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "尚未测试模型连通性")
    private let mascotSizeValue = NSTextField(labelWithString: "")
    private let bubbleSizeValue = NSTextField(labelWithString: "")
    private let opacityValue = NSTextField(labelWithString: "")
    private let volumeValue = NSTextField(labelWithString: "")
    private let ambientSwitch = NSSwitch()
    private let ambientValue = NSTextField(labelWithString: "")
    private let completionAlertSwitch = NSSwitch()
    private let problemAlertSwitch = NSSwitch()
    private let quietHoursSwitch = NSSwitch()
    private let quietStartField = NSTextField(string: "")
    private let quietEndField = NSTextField(string: "")
    private let taskAlertVolumeSlider = NSSlider()
    private let taskAlertVolumeValue = NSTextField(labelWithString: "")
    private let taskAlertRepeatField = NSTextField(string: "")
    private let colorWell = NSColorWell()
    private let memoryField = NSTextField(string: "")
    private let summaryField = NSTextField(string: "")
    private let memoryStatus = NSTextField(labelWithString: "")
    private weak var settingsTabs: NSTabView?

    init(store: AemisConversationStore, presetID: String, presentation: AemisPresentationSettings, ambientEnabled: Bool, ambientIntervalMinutes: Int, taskAlerts: CodexTaskAlertSettings, onPresentationChanged: @escaping (AemisPresentationSettings) -> Void, onAmbientChanged: @escaping (Bool, Int) -> Void, onTaskAlertsChanged: @escaping (CodexTaskAlertSettings) -> Void, onTaskAlertPreview: @escaping (CodexTaskAlertKind) -> Void, onAction: @escaping (AemisSettingsAction) -> Void, onConfigurationSaved: @escaping (AemisAIConfiguration) -> Void) {
        self.store = store
        self.presetID = presetID
        self.presentation = presentation
        self.ambientEnabled = ambientEnabled
        self.ambientIntervalMinutes = ambientIntervalMinutes
        self.taskAlerts = taskAlerts
        self.onTaskAlertsChanged = onTaskAlertsChanged
        self.onTaskAlertPreview = onTaskAlertPreview
        self.onPresentationChanged = onPresentationChanged
        self.onAmbientChanged = onAmbientChanged
        self.onAction = onAction
        self.onConfigurationSaved = onConfigurationSaved
        let window = AemisEditableSettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "爱弥斯设置"; window.minSize = NSSize(width: 560, height: 540); window.center(); window.titlebarAppearsTransparent = true; window.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.97, alpha: 1)
        // The desktop pet is an always-on-top panel. Keep settings one level
        // above it so the mascot never covers API fields, buttons or sliders.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        super.init(window: window)
        buildInterface()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface() {
        guard let window else { return }
        let root = NSView(frame: window.contentView?.bounds ?? .zero); root.appearance = NSAppearance(named: .aqua); root.wantsLayer = true; root.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.97, alpha: 1).cgColor; root.autoresizingMask = [.width, .height]
        window.contentView = root
        let header = NSView(); header.wantsLayer = true; header.layer?.backgroundColor = NSColor(calibratedRed: 0.89, green: 0.45, blue: 0.62, alpha: 1).cgColor; header.layer?.cornerRadius = 18; header.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "爱弥斯 · 控制中心"); title.font = .systemFont(ofSize: 22, weight: .bold); title.textColor = .white
        let subtitle = NSTextField(wrappingLabelWithString: "外观、互动与陪伴，都从这里慢慢调成你喜欢的样子"); subtitle.font = .systemFont(ofSize: 12, weight: .medium); subtitle.textColor = NSColor.white.withAlphaComponent(0.90); subtitle.maximumNumberOfLines = 2
        let star = NSTextField(labelWithString: "✦"); star.font = .systemFont(ofSize: 34, weight: .bold); star.textColor = NSColor(calibratedRed: 0.65, green: 0.96, blue: 1, alpha: 1)
        let headerText = NSStackView(views: [title, subtitle]); headerText.orientation = .vertical; headerText.alignment = .leading; headerText.spacing = 3; headerText.translatesAutoresizingMaskIntoConstraints = false; star.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerText); header.addSubview(star)
        NSLayoutConstraint.activate([headerText.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22), headerText.trailingAnchor.constraint(lessThanOrEqualTo: star.leadingAnchor, constant: -12), headerText.centerYAnchor.constraint(equalTo: header.centerYAnchor), star.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24), star.centerYAnchor.constraint(equalTo: header.centerYAnchor)])
        let material = NSView(); material.wantsLayer = true; material.layer?.backgroundColor = NSColor(calibratedRed: 1, green: 0.985, blue: 0.99, alpha: 1).cgColor; material.layer?.borderColor = NSColor(calibratedRed: 0.90, green: 0.65, blue: 0.76, alpha: 0.45).cgColor; material.layer?.borderWidth = 1; material.layer?.cornerRadius = 18; material.translatesAutoresizingMaskIntoConstraints = false
        let tabs = NSTabView(); tabs.tabViewType = .noTabsNoBorder; tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.addTabViewItem(tab("角色与素材", content: characterTab()))
        tabs.addTabViewItem(tab("桌宠外观", content: appearanceTab()))
        tabs.addTabViewItem(tab("互动与语音", content: interactionTab()))
        tabs.addTabViewItem(tab("Codex 提醒", content: taskAlertsTab()))
        tabs.addTabViewItem(tab("AI 对话", content: aiTab()))
        tabs.addTabViewItem(tab("记忆与隐私", content: memoryTab()))
        tabs.addTabViewItem(tab("说明", content: infoTab()))
        settingsTabs = tabs
        let tabSelector = NSSegmentedControl(labels: ["角色", "外观", "互动", "任务提醒", "AI", "记忆", "说明"], trackingMode: .selectOne, target: self, action: #selector(selectTab(_:)))
        tabSelector.selectedSegment = 0; tabSelector.segmentStyle = .rounded; tabSelector.font = .systemFont(ofSize: 12, weight: .semibold); tabSelector.selectedSegmentBezelColor = NSColor(calibratedRed: 0.91, green: 0.47, blue: 0.65, alpha: 1); tabSelector.wantsLayer = true; tabSelector.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor; tabSelector.layer?.cornerRadius = 9; tabSelector.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(tabs)
        NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 10), tabs.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -10), tabs.topAnchor.constraint(equalTo: material.topAnchor, constant: 10), tabs.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -10)])
        root.addSubview(header); root.addSubview(tabSelector); root.addSubview(material)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14), header.heightAnchor.constraint(equalToConstant: 76), tabSelector.centerXAnchor.constraint(equalTo: root.centerXAnchor), tabSelector.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 7), material.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), material.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), material.topAnchor.constraint(equalTo: tabSelector.bottomAnchor, constant: 7), material.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)])
    }

    private func tab(_ label: String, content: NSView) -> NSTabViewItem { let item = NSTabViewItem(identifier: label); item.label = label; item.view = scrollable(content); return item }
    private func label(_ text: String) -> NSTextField { let field = NSTextField(wrappingLabelWithString: text); field.font = .systemFont(ofSize: 13, weight: .semibold); field.textColor = NSColor(calibratedRed: 0.30, green: 0.14, blue: 0.23, alpha: 1); field.lineBreakMode = .byWordWrapping; field.maximumNumberOfLines = 0; return field }
    private func fieldRow(_ title: String, field: NSTextField) -> NSStackView {
        let caption = label(title)
        caption.font = .systemFont(ofSize: 12, weight: .bold)
        caption.textColor = NSColor(calibratedRed: 0.42, green: 0.16, blue: 0.30, alpha: 1)
        caption.widthAnchor.constraint(equalToConstant: 128).isActive = true
        field.isEditable = true; field.isSelectable = true; field.isEnabled = true; field.refusesFirstResponder = false
        field.isBezeled = true; field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13); field.textColor = NSColor(calibratedRed: 0.22, green: 0.11, blue: 0.18, alpha: 1)
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [caption, field]); row.orientation = .horizontal; row.spacing = 12; row.alignment = .centerY; row.distribution = .fill; row.heightAnchor.constraint(equalToConstant: 34).isActive = true; return row
    }
    private func vertical(_ views: [NSView]) -> NSStackView {
        let stack = AemisFlippedStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14; stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 24, right: 20)
        views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true }
        return stack
    }
    private func scrollable(_ content: NSView) -> NSView {
        let scroll = AemisResponsiveScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.drawsBackground = false; scroll.autohidesScrollers = true
        content.translatesAutoresizingMaskIntoConstraints = true
        content.frame = NSRect(x: 0, y: 0, width: 620, height: max(620, content.fittingSize.height))
        content.autoresizingMask = [.width]
        content.userInterfaceLayoutDirection = .leftToRight
        scroll.documentView = content
        content.setFrameOrigin(.zero)
        scroll.contentView.scroll(to: .zero)
        DispatchQueue.main.async { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
        return scroll
    }
    @objc private func selectTab(_ sender: NSSegmentedControl) { settingsTabs?.selectTabViewItem(at: sender.selectedSegment) }

    private func characterTab() -> NSView {
        let intro = NSTextField(wrappingLabelWithString: "把人物、预设包和所有会在特殊情境切换的图片/语音集中管理。导入素材后，爱弥斯会保留你已经设置好的触发条件。")
        intro.textColor = .secondaryLabelColor; intro.maximumNumberOfLines = 0
        let character = actionRow("人物与预设", buttons: [
            ("更换透明 PNG 人物…", .chooseMascot),
            ("保存当前预设…", .savePreset),
            ("导入预设包…", .importPreset),
            ("导出当前预设包…", .exportPreset)
        ])
        let interactions = actionRow("互动内容", buttons: [
            ("编辑连点台词…", .editPatMessage),
            ("导入触发图片…", .importEventImages),
            ("导入点击音效…", .importClickSounds),
            ("导入触发语音…", .importEventSounds)
        ])
        let tip = NSTextField(wrappingLabelWithString: "提示：点击音效与触发语音分开导入；触发图片和触发语音都支持批量选择，单段音频最长 15 秒。")
        tip.textColor = .secondaryLabelColor; tip.maximumNumberOfLines = 0
        return vertical([label("角色与素材库"), intro, character, interactions, tip])
    }

    private func actionRow(_ title: String, buttons: [(String, AemisSettingsAction)]) -> NSStackView {
        let heading = label(title)
        let grid = NSStackView(); grid.orientation = .vertical; grid.alignment = .width; grid.spacing = 8
        for (title, action) in buttons {
            let symbol: String
            switch action {
            case .chooseMascot: symbol = "◉"
            case .savePreset: symbol = "✦"
            case .importPreset: symbol = "↓"
            case .exportPreset: symbol = "↑"
            case .editPatMessage: symbol = "✎"
            case .importEventImages: symbol = "▣"
            case .importClickSounds: symbol = "♪"
            case .importEventSounds: symbol = "♫"
            }
            let button = AemisActionButton("\(symbol)   \(title)", target: self, action: #selector(runAction(_:)), prominent: false)
            button.tag = action.rawValue
            grid.addArrangedSubview(button)
        }
        let block = NSStackView(views: [heading, grid]); block.orientation = .vertical; block.alignment = .centerX; block.spacing = 8
        heading.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        let responsiveWidth = grid.widthAnchor.constraint(equalTo: block.widthAnchor, constant: -24)
        responsiveWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 12),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: block.trailingAnchor, constant: -12),
            grid.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            grid.widthAnchor.constraint(lessThanOrEqualTo: block.widthAnchor, constant: -24),
            responsiveWidth
        ])
        return block
    }

    @objc private func runAction(_ sender: NSButton) {
        guard let action = AemisSettingsAction(rawValue: sender.tag) else { return }
        onAction(action)
    }

    private func aiTab() -> NSView {
        let config = AemisAIConfiguration.load(); baseURLField.stringValue = config.baseURL; modelField.stringValue = config.model; timeoutField.stringValue = String(Int(config.timeoutSeconds)); maxTokensField.stringValue = String(config.maxTokens); personaField.string = config.persona
        keyField.placeholderString = AemisKeychain.load() == nil ? "尚未设置" : "已安全保存；留空则不改动"
        personaField.font = .systemFont(ofSize: 13); personaField.isRichText = false; personaField.isHorizontallyResizable = false; personaField.isVerticallyResizable = true; personaField.autoresizingMask = [.width]
        personaField.textContainer?.widthTracksTextView = true; personaField.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let personaScroll = NSScrollView(); personaScroll.documentView = personaField; personaScroll.hasVerticalScroller = true; personaScroll.hasHorizontalScroller = false; personaScroll.borderType = .bezelBorder
        personaScroll.heightAnchor.constraint(equalToConstant: 155).isActive = true
        statusLabel.textColor = .secondaryLabelColor; statusLabel.maximumNumberOfLines = 3
        let save = AemisActionButton("保存到本机", target: self, action: #selector(saveConfiguration))
        let test = AemisActionButton("测试模型连通", target: self, action: #selector(testConnection), prominent: false)
        let stack = vertical([fieldRow("基础地址", field: baseURLField), fieldRow("模型名称", field: modelField), fieldRow("请求超时（秒）", field: timeoutField), fieldRow("单次回复上限", field: maxTokensField), fieldRow("DeepSeek API Key", field: keyField), label("爱弥斯人设"), personaScroll, NSStackView(views: [save, test]), statusLabel])
        return stack
    }

    private func sliderRow(_ title: String, value: Double, min: Double, max: Double, valueLabel: NSTextField, action: Selector) -> NSStackView {
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.cell = AemisSliderCell(); slider.minValue = min; slider.maxValue = max; slider.doubleValue = value; slider.target = self; slider.action = action; slider.isContinuous = true
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        valueLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        valueLabel.textColor = NSColor(calibratedRed: 0.68, green: 0.23, blue: 0.44, alpha: 1)
        let titleLabel = label(title); titleLabel.widthAnchor.constraint(equalToConstant: 118).isActive = true
        let row = NSStackView(views: [titleLabel, slider, valueLabel]); row.orientation = .horizontal; row.spacing = 10; row.alignment = .centerY
        return row
    }

    private func appearanceTab() -> NSView {
        colorWell.color = presentation.themeColor; colorWell.target = self; colorWell.action = #selector(changeColor)
        let colorRow = NSStackView(views: [label("聊天框颜色"), colorWell]); colorRow.orientation = .horizontal; colorRow.spacing = 12; colorRow.alignment = .centerY
        refreshAppearanceLabels()
        let note = NSTextField(wrappingLabelWithString: "这里的滑块会实时生效并保存。窗口与人物大小会一起更新；右键菜单仍保留快速入口。")
        note.maximumNumberOfLines = 0; note.textColor = .secondaryLabelColor; note.lineBreakMode = .byWordWrapping
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return vertical([
            label("爱弥斯外观"), colorRow,
            sliderRow("人物大小", value: presentation.mascotSize, min: 0.60, max: 1.50, valueLabel: mascotSizeValue, action: #selector(changeMascotSize(_:))),
            sliderRow("气泡大小", value: presentation.bubbleSize, min: 0.60, max: 1.50, valueLabel: bubbleSizeValue, action: #selector(changeBubbleSize(_:))),
            sliderRow("气泡不透明度", value: presentation.bubbleOpacity, min: 0.45, max: 1.00, valueLabel: opacityValue, action: #selector(changeOpacity(_:))),
            sliderRow("音效音量", value: Double(presentation.soundVolume), min: 0, max: 1, valueLabel: volumeValue, action: #selector(changeVolume(_:))), note
        ])
    }

    private func interactionTab() -> NSView {
        ambientSwitch.state = ambientEnabled ? .on : .off; ambientSwitch.target = self; ambientSwitch.action = #selector(changeAmbientEnabled(_:))
        ambientValue.stringValue = ambientIntervalText(ambientIntervalMinutes)
        let interval = NSSlider(value: Double(ambientIntervalMinutes), minValue: 3, maxValue: 120, target: self, action: #selector(changeAmbientInterval(_:)))
        interval.cell = AemisSliderCell(); interval.minValue = 3; interval.maxValue = 120; interval.doubleValue = Double(ambientIntervalMinutes); interval.target = self; interval.action = #selector(changeAmbientInterval(_:)); interval.isContinuous = true
        interval.numberOfTickMarks = 0; interval.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        interval.widthAnchor.constraint(equalToConstant: 250).isActive = true
        ambientValue.widthAnchor.constraint(equalToConstant: 112).isActive = true; ambientValue.alignment = .right; ambientValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold); ambientValue.textColor = NSColor(calibratedRed: 0.68, green: 0.23, blue: 0.44, alpha: 1)
        let toggle = NSStackView(views: [label("随机空闲语音"), ambientSwitch]); toggle.orientation = .horizontal; toggle.spacing = 12; toggle.alignment = .centerY
        let intervalTitle = label("播放间隔"); intervalTitle.widthAnchor.constraint(equalToConstant: 118).isActive = true
        let intervalRow = NSStackView(views: [intervalTitle, interval, ambientValue]); intervalRow.orientation = .horizontal; intervalRow.spacing = 10; intervalRow.alignment = .centerY
        let note = NSTextField(wrappingLabelWithString: "开启后，在一段时间没有互动时，爱弥斯会随机触发“随机空闲语音”。在右键菜单的「互动与素材 → 导入触发语音」中，为这个条件导入多段不超过 15 秒的语音即可。")
        note.maximumNumberOfLines = 0; note.textColor = .secondaryLabelColor; note.lineBreakMode = .byWordWrapping; note.preferredMaxLayoutWidth = 520
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return vertical([label("互动与语音"), toggle, intervalRow, note])
    }

    private func taskAlertsTab() -> NSView {
        completionAlertSwitch.state = taskAlerts.completionEnabled ? .on : .off
        problemAlertSwitch.state = taskAlerts.problemEnabled ? .on : .off
        completionAlertSwitch.target = self; completionAlertSwitch.action = #selector(changeTaskAlertSettings)
        problemAlertSwitch.target = self; problemAlertSwitch.action = #selector(changeTaskAlertSettings)
        let completeRow = NSStackView(views: [label("完成播报（含本轮回复）"), completionAlertSwitch]); completeRow.orientation = .horizontal; completeRow.spacing = 12
        let problemRow = NSStackView(views: [label("问题与待回复播报"), problemAlertSwitch]); problemRow.orientation = .horizontal; problemRow.spacing = 12
        quietStartField.stringValue = String(taskAlerts.quietStartHour)
        quietEndField.stringValue = String(taskAlerts.quietEndHour)
        taskAlertRepeatField.stringValue = String(taskAlerts.repeatMinutes)
        for field in [quietStartField, quietEndField, taskAlertRepeatField] {
            field.alignment = .center; field.widthAnchor.constraint(equalToConstant: 54).isActive = true
            field.target = self; field.action = #selector(changeTaskAlertSettings)
        }
        quietHoursSwitch.state = taskAlerts.quietEnabled ? .on : .off
        quietHoursSwitch.target = self; quietHoursSwitch.action = #selector(changeTaskAlertSettings)
        let quietRow = NSStackView(views: [label("定时静音"), quietHoursSwitch, quietStartField, label("点 至"), quietEndField, label("点（相同则关闭）")])
        quietRow.orientation = .horizontal; quietRow.spacing = 8; quietRow.alignment = .centerY
        taskAlertVolumeSlider.minValue = 0; taskAlertVolumeSlider.maxValue = 2
        taskAlertVolumeSlider.floatValue = taskAlerts.volume
        taskAlertVolumeSlider.target = self; taskAlertVolumeSlider.action = #selector(changeTaskAlertSettings)
        taskAlertVolumeSlider.isContinuous = true
        taskAlertVolumeSlider.toolTip = "十连点、任务完成和报错语音共用；短点击音效独立"
        taskAlertVolumeSlider.widthAnchor.constraint(equalToConstant: 230).isActive = true
        taskAlertVolumeValue.stringValue = "\(Int(taskAlerts.volume * 100))%"
        let volumeRow = NSStackView(views: [label("语音音量 0–200%"), taskAlertVolumeSlider, taskAlertVolumeValue])
        volumeRow.orientation = .horizontal; volumeRow.spacing = 10; volumeRow.alignment = .centerY
        let repeatRow = NSStackView(views: [label("同一轮次的问题只提醒一次，回复或重试后自动取消")])
        repeatRow.orientation = .horizontal; repeatRow.spacing = 8; repeatRow.alignment = .centerY
        let save = AemisActionButton("保存提醒设置", target: self, action: #selector(changeTaskAlertSettings))
        let previewComplete = AemisActionButton("试听完成播报", target: self, action: #selector(previewTaskComplete), prominent: false)
        let previewProblem = AemisActionButton("试听问题播报", target: self, action: #selector(previewTaskProblem), prominent: false)
        let previewRow = NSStackView(views: [previewComplete, previewProblem]); previewRow.orientation = .horizontal; previewRow.spacing = 10
        let semantics = NSTextField(wrappingLabelWithString: "完成：显式目标完成，或普通聊天本轮完成且有非空最终答复；中间消息和待回复问题不触发。问题：目标受阻、最新一轮运行失败，或 Codex 明确提问且尚未收到你的回复。定时静音默认关闭，手动开启后才按设定时段关闭自动播报，试听按钮可随时测试当前音量；气泡仍可点击直达任务。")
        semantics.maximumNumberOfLines = 0; semantics.textColor = .secondaryLabelColor
        return vertical([label("Codex 任务提醒"), completeRow, problemRow, quietRow, volumeRow, repeatRow, save, previewRow, semantics])
    }

    func refreshTaskAlertControls(_ settings: CodexTaskAlertSettings) {
        taskAlerts = settings
        completionAlertSwitch.state = settings.completionEnabled ? .on : .off
        problemAlertSwitch.state = settings.problemEnabled ? .on : .off
        quietHoursSwitch.state = settings.quietEnabled ? .on : .off
        quietStartField.stringValue = String(settings.quietStartHour)
        quietEndField.stringValue = String(settings.quietEndHour)
        taskAlertRepeatField.stringValue = String(settings.repeatMinutes)
        taskAlertVolumeSlider.floatValue = settings.volume
        taskAlertVolumeValue.stringValue = "\(Int((settings.volume * 100).rounded()))%"
    }

    @objc private func previewTaskComplete() { changeTaskAlertSettings(); onTaskAlertPreview(.complete) }
    @objc private func previewTaskProblem() { changeTaskAlertSettings(); onTaskAlertPreview(.problem) }

    @objc private func changeTaskAlertSettings() {
        taskAlerts.completionEnabled = completionAlertSwitch.state == .on
        taskAlerts.problemEnabled = problemAlertSwitch.state == .on
        taskAlerts.quietEnabled = quietHoursSwitch.state == .on
        taskAlerts.quietStartHour = max(0, min(23, Int(quietStartField.stringValue) ?? taskAlerts.quietStartHour))
        taskAlerts.quietEndHour = max(0, min(23, Int(quietEndField.stringValue) ?? taskAlerts.quietEndHour))
        taskAlerts.volume = taskAlertVolumeSlider.floatValue
        taskAlerts.repeatMinutes = 0
        quietStartField.stringValue = String(taskAlerts.quietStartHour)
        quietEndField.stringValue = String(taskAlerts.quietEndHour)
        taskAlertRepeatField.stringValue = String(taskAlerts.repeatMinutes)
        taskAlertVolumeValue.stringValue = "\(Int(taskAlerts.volume * 100))%"
        taskAlerts.save()
        onTaskAlertsChanged(taskAlerts)
    }

    private func refreshAppearanceLabels() {
        mascotSizeValue.stringValue = "\(Int((presentation.mascotSize * 100).rounded()))%"
        bubbleSizeValue.stringValue = "\(Int((presentation.bubbleSize * 100).rounded()))%"
        opacityValue.stringValue = "\(Int((presentation.bubbleOpacity * 100).rounded()))%"
        volumeValue.stringValue = "\(Int((Double(presentation.soundVolume) * 100).rounded()))%"
    }

    private func publishPresentation() { refreshAppearanceLabels(); onPresentationChanged(presentation) }
    @objc private func changeMascotSize(_ sender: NSSlider) { presentation.mascotSize = sender.doubleValue; publishPresentation() }
    @objc private func changeBubbleSize(_ sender: NSSlider) { presentation.bubbleSize = sender.doubleValue; publishPresentation() }
    @objc private func changeOpacity(_ sender: NSSlider) { presentation.bubbleOpacity = sender.doubleValue; publishPresentation() }
    @objc private func changeVolume(_ sender: NSSlider) { presentation.soundVolume = Float(sender.doubleValue); publishPresentation() }
    @objc private func changeColor() { presentation.themeColor = colorWell.color; publishPresentation() }
    @objc private func changeAmbientEnabled(_ sender: NSSwitch) { ambientEnabled = sender.state == .on; onAmbientChanged(ambientEnabled, ambientIntervalMinutes) }
    private func ambientIntervalText(_ minutes: Int) -> String {
        let lower = max(1, Int((Double(minutes) * 0.72).rounded()))
        let upper = Int((Double(minutes) * 1.28).rounded())
        return "随机 \(lower)–\(upper) 分钟"
    }
    @objc private func changeAmbientInterval(_ sender: NSSlider) { ambientIntervalMinutes = Int(sender.doubleValue.rounded()); ambientValue.stringValue = ambientIntervalText(ambientIntervalMinutes); onAmbientChanged(ambientEnabled, ambientIntervalMinutes) }

    private func memoryTab() -> NSView {
        let path = NSTextField(wrappingLabelWithString: "本地数据库：\n\(store.databaseURL.path)")
        path.textColor = .secondaryLabelColor
        let detail = NSTextField(wrappingLabelWithString: "聊天记录和将来由你明确保存的记忆都只存在这台 Mac。每次聊天只会取少量最近消息；API Key 不会写进数据库、预设包或 Git。")
        detail.maximumNumberOfLines = 0
        memoryField.placeholderString = "例如：我喜欢简洁回答；称呼我小付"
        memoryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let save = AemisActionButton("明确保存这条记忆", target: self, action: #selector(saveMemory))
        summaryField.placeholderString = "例如：最近在讨论桌宠的图片与语音素材"
        summaryField.stringValue = store.profileSummary(presetID: presetID)
        summaryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let saveSummary = AemisActionButton("保存本预设摘要", target: self, action: #selector(saveProfileSummary), prominent: false)
        memoryStatus.stringValue = "当前预设已保存 \(store.messageCount(presetID: presetID)) 条聊天消息、\(store.memoryCount(presetID: presetID)) 条明确记忆"
        memoryStatus.textColor = .secondaryLabelColor
        let input = NSStackView(views: [memoryField, save]); input.orientation = .horizontal; input.spacing = 10; input.alignment = .centerY
        let summary = NSStackView(views: [summaryField, saveSummary]); summary.orientation = .horizontal; summary.spacing = 10; summary.alignment = .centerY
        return vertical([label("本地记忆"), path, detail, label("本预设聊天摘要"), summary, label("明确允许保存的记忆"), input, memoryStatus])
    }

    @objc private func saveMemory() {
        let note = memoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { memoryStatus.stringValue = "先填写一条需要保存的内容。"; return }
        store.appendMemory(note, presetID: presetID); memoryField.stringValue = ""
        memoryStatus.stringValue = "已保存到当前预设。当前有 \(store.memoryCount(presetID: presetID)) 条明确记忆。"
        memoryStatus.textColor = .systemTeal
    }

    @objc private func saveProfileSummary() {
        store.saveProfileSummary(summaryField.stringValue, presetID: presetID)
        memoryStatus.stringValue = "当前预设的聊天摘要已保存到本机。"
        memoryStatus.textColor = .systemTeal
    }

    private func infoTab() -> NSView {
        let detail = NSTextField(wrappingLabelWithString: "外观、声音、互动素材和位置可在本窗口细调，右键菜单也保留了快速调整入口。\n\n点击粉色气泡会打开可缩放聊天窗口；把图片拖入聊天窗口后，爱弥斯会在模型支持图片输入时一并发送。\n\n测试按钮会实际发送一次很短的请求，只有在你保存了 API Key 后才会发生。")
        detail.maximumNumberOfLines = 0
        return vertical([label("使用说明"), detail])
    }

    @objc private func saveConfiguration() {
        guard let timeout = Double(timeoutField.stringValue), (5...120).contains(timeout), let maxTokens = Int(maxTokensField.stringValue), (100...4000).contains(maxTokens) else { statusLabel.stringValue = "超时需在 5–120 秒，单次回复上限需在 100–4000。"; statusLabel.textColor = .systemOrange; return }
        let configuration = AemisAIConfiguration(baseURL: baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), persona: personaField.string.trimmingCharacters(in: .whitespacesAndNewlines), timeoutSeconds: timeout, maxTokens: maxTokens)
        guard !configuration.baseURL.isEmpty, !configuration.model.isEmpty, !configuration.persona.isEmpty else { statusLabel.stringValue = "基础地址、模型名称和人设都不能为空。"; return }
        configuration.save()
        // 人设属于当前人物预设；连接参数仍是本机全局配置。
        onConfigurationSaved(configuration)
        if !keyField.stringValue.isEmpty, !AemisKeychain.save(keyField.stringValue) { statusLabel.stringValue = "无法写入 macOS 钥匙串。"; return }
        keyField.stringValue = ""; statusLabel.stringValue = "已保存。API Key 仅存于本机钥匙串。"; statusLabel.textColor = .systemTeal
    }

    @objc private func testConnection() {
        saveConfiguration()
        guard let key = AemisKeychain.load(), !key.isEmpty else { statusLabel.stringValue = "请先输入并保存 DeepSeek API Key。"; statusLabel.textColor = .systemOrange; return }
        statusLabel.stringValue = "正在测试…"; statusLabel.textColor = .secondaryLabelColor
        AemisDeepSeekService.test(configuration: AemisAIConfiguration.load(), key: key) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message): self?.statusLabel.stringValue = "连接成功：\(message)"; self?.statusLabel.textColor = .systemGreen
                case .failure(let error): self?.statusLabel.stringValue = error.localizedDescription; self?.statusLabel.textColor = .systemRed
                }
            }
        }
    }
}

final class ImageDropZone: NSView {
    var onImage: ((URL) -> Void)?
    var onError: ((String) -> Void)?
    var onClear: (() -> Void)?
    private let label = NSTextField(labelWithString: "把图片拖到这里")
    private var selectedURL: URL?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true; layer?.backgroundColor = NSColor(calibratedRed: 1, green: 0.86, blue: 0.92, alpha: 0.72).cgColor; layer?.cornerRadius = 12; layer?.borderWidth = 1; layer?.borderColor = NSColor.systemPink.withAlphaComponent(0.65).cgColor; registerForDraggedTypes([.fileURL]); label.translatesAutoresizingMaskIntoConstraints = false; label.stringValue = "拖入图片\n或点这里"; label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = NSColor(calibratedRed: 0.48, green: 0.16, blue: 0.31, alpha: 1); label.alignment = .center; label.maximumNumberOfLines = 2; addSubview(label); NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6), label.centerYAnchor.constraint(equalTo: centerYAnchor)]) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) {
        if selectedURL != nil { clearSelection(); return }
        layer?.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.84, alpha: 0.82).cgColor
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            self?.layer?.backgroundColor = NSColor(calibratedRed: 1, green: 0.86, blue: 0.92, alpha: 0.72).cgColor
            guard response == .OK, let url = panel.url else { return }
            self?.accept(url)
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { guard let url = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL else { return false }; return accept(url) }

    @discardableResult private func accept(_ url: URL) -> Bool {
        guard NSImage(contentsOf: url) != nil else { showError("不是可读取的图片，请重新选择。"); return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 6 * 1024 * 1024 else { showError("图片超过 6 MB，已取消附件；可立即重新选择。"); return false }
        selectedURL = url
        label.stringValue = "已附加\n点这里移除"
        layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.8).cgColor
        onImage?(url)
        return true
    }

    func clearSelection() {
        selectedURL = nil
        label.stringValue = "拖入图片\n或点这里"
        layer?.borderColor = NSColor.systemPink.withAlphaComponent(0.65).cgColor
        onClear?()
    }

    private func showError(_ message: String) {
        clearSelection()
        label.stringValue = "选择失败\n点这里重选"
        layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
        onError?(message)
    }
}

private final class AemisSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        let background = NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3)
        NSColor(calibratedRed: 0.90, green: 0.82, blue: 0.86, alpha: 1).setFill(); background.fill()
        let range = max(0.0001, maxValue - minValue)
        let progress = CGFloat((doubleValue - minValue) / range)
        let filled = NSRect(x: track.minX, y: track.minY, width: max(6, track.width * progress), height: track.height)
        let fill = NSBezierPath(roundedRect: filled, xRadius: 3, yRadius: 3)
        NSColor(calibratedRed: 0.88, green: 0.31, blue: 0.55, alpha: 1).setFill(); fill.fill()
    }
}

private final class AemisActionButton: NSButton {
    private let prominentStyle: Bool
    private static var activeFeedbackSound: NSSound?

    init(_ title: String, target: AnyObject?, action: Selector?, prominent: Bool = true) {
        prominentStyle = prominent
        super.init(frame: .zero)
        self.target = target; self.action = action; isBordered = false; wantsLayer = true
        layer?.cornerRadius = 13; layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedRed: 0.91, green: 0.55, blue: 0.70, alpha: prominent ? 0 : 0.52).cgColor
        layer?.backgroundColor = (prominent
            ? NSColor(calibratedRed: 0.86, green: 0.31, blue: 0.54, alpha: 1)
            : NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.93, alpha: 1)).cgColor
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: prominent ? NSColor.white : NSColor(calibratedRed: 0.50, green: 0.16, blue: 0.32, alpha: 1),
            .paragraphStyle: paragraph
        ])
        alignment = .center
        focusRingType = .default
        toolTip = title.replacingOccurrences(of: "   ", with: " ")
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 46).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        let normal = prominentStyle
            ? NSColor(calibratedRed: 0.86, green: 0.31, blue: 0.54, alpha: 1)
            : NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.93, alpha: 1)
        let pressed = prominentStyle
            ? NSColor(calibratedRed: 0.72, green: 0.20, blue: 0.42, alpha: 1)
            : NSColor(calibratedRed: 0.96, green: 0.68, blue: 0.80, alpha: 1)
        layer?.backgroundColor = pressed.cgColor
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.975, y: 0.975))
        playFeedbackSound()
        super.mouseDown(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            layer?.backgroundColor = normal.cgColor
            layer?.setAffineTransform(.identity)
        }
    }

    private func playFeedbackSound() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "clickSoundEnabled") == nil || defaults.bool(forKey: "clickSoundEnabled") else { return }
        let path: String
        if let custom = defaults.string(forKey: "customSoundPath"), defaults.string(forKey: "tapSound") == "custom", FileManager.default.fileExists(atPath: custom) {
            path = custom
        } else {
            let sound = defaults.string(forKey: "tapSound") ?? "basso"
            path = "/System/Library/Sounds/\(sound.prefix(1).uppercased())\(sound.dropFirst()).aiff"
        }
        guard let sound = NSSound(contentsOfFile: path, byReference: true) else { return }
        sound.volume = defaults.object(forKey: "soundVolume") == nil ? 0.55 : defaults.float(forKey: "soundVolume")
        Self.activeFeedbackSound = sound; sound.play()
    }
}

private final class AemisFlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// A chat surface embedded in the desktop bubble itself. It deliberately has no
/// window of its own: the parent panel grows from the original pink bubble.
final class AemisBubbleChatView: NSView {
    private let store: AemisConversationStore
    private let presetID: String
    private let transcript = NSTextView()
    private let input = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "爱弥斯在这里。图片可以直接拖进来。")
    private let sizeSlider = NSSlider(value: 500, minValue: 420, maxValue: 700, target: nil, action: nil)
    private var imageURL: URL?
    private weak var imageDropZone: ImageDropZone?
    var onDismiss: (() -> Void)?
    var onWidthChanged: ((CGFloat) -> Void)?
    var onHeightGrowthRequested: ((CGFloat) -> Void)?
    private weak var transcriptScroll: NSScrollView?

    init(store: AemisConversationStore, presetID: String) {
        self.store = store
        self.presetID = presetID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.96, alpha: 0.985).cgColor
        layer?.borderColor = NSColor(calibratedRed: 0.45, green: 0.86, blue: 0.90, alpha: 0.82).cgColor
        layer?.borderWidth = 1.25; layer?.cornerRadius = 28
        buildInterface(); reloadTranscript()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeKey()
            self.window?.makeFirstResponder(self.input)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // The compact bubble itself is the toggle.  Keep the same interaction
        // after expansion: clicking the left side of its header folds it back
        // immediately, while the width control remains independently usable.
        if (point.y >= bounds.height - 76 && point.x < bounds.width - 205) ||
            point.y <= 12 || point.x <= 9 || point.x >= bounds.width - 9 {
            onDismiss?()
            return
        }
        super.mouseDown(with: event)
    }

    private func buildInterface() {
        let ink = NSColor(calibratedRed: 0.28, green: 0.12, blue: 0.22, alpha: 1)
        let rose = NSColor(calibratedRed: 0.72, green: 0.24, blue: 0.46, alpha: 1)
        let teal = NSColor(calibratedRed: 0.08, green: 0.48, blue: 0.57, alpha: 1)
        let title = NSTextField(labelWithString: "爱弥斯"); title.font = .systemFont(ofSize: 20, weight: .bold); title.textColor = rose
        let sub = NSTextField(labelWithString: "✦ 陪你看看、聊聊、想想 · 再点这里收起"); sub.font = .systemFont(ofSize: 12, weight: .medium); sub.textColor = teal
        let heading = NSStackView(views: [title, sub]); heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 1; heading.toolTip = "再次点击收起气泡"
        // Text fields consume mouse events themselves on macOS, so a clear
        // button sits above the complete heading and makes the toggle reliable.
        let collapseHitArea = NSButton(title: "", target: self, action: #selector(closeChat))
        collapseHitArea.isBordered = false; collapseHitArea.isTransparent = true
        collapseHitArea.toolTip = "再次点击收起气泡"; collapseHitArea.translatesAutoresizingMaskIntoConstraints = false
        heading.addSubview(collapseHitArea, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            collapseHitArea.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            collapseHitArea.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            collapseHitArea.topAnchor.constraint(equalTo: heading.topAnchor),
            collapseHitArea.bottomAnchor.constraint(equalTo: heading.bottomAnchor)
        ])
        let sizeLabel = NSTextField(labelWithString: "宽度"); sizeLabel.font = .systemFont(ofSize: 11, weight: .semibold); sizeLabel.textColor = ink.withAlphaComponent(0.68)
        sizeSlider.cell = AemisSliderCell(); sizeSlider.minValue = 420; sizeSlider.maxValue = 700; sizeSlider.doubleValue = 500; sizeSlider.target = self; sizeSlider.action = #selector(changeWidth(_:)); sizeSlider.isContinuous = true; sizeSlider.translatesAutoresizingMaskIntoConstraints = false; sizeSlider.widthAnchor.constraint(equalToConstant: 118).isActive = true
        let controls = NSStackView(views: [sizeLabel, sizeSlider]); controls.orientation = .horizontal; controls.alignment = .centerY; controls.spacing = 8
        let close = AemisActionButton("收回", target: self, action: #selector(closeChat), prominent: false)
        close.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let header = NSStackView(views: [heading, controls, close]); header.orientation = .horizontal; header.distribution = .fill; header.alignment = .centerY; header.spacing = 10
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        transcript.frame = NSRect(x: 0, y: 0, width: 380, height: 260)
        transcript.isEditable = false; transcript.isSelectable = true; transcript.isRichText = false
        transcript.drawsBackground = true; transcript.backgroundColor = NSColor.white.withAlphaComponent(0.72)
        transcript.font = .systemFont(ofSize: 14); transcript.textColor = ink
        transcript.textContainerInset = NSSize(width: 12, height: 12); transcript.isVerticallyResizable = true; transcript.autoresizingMask = [.width]
        transcript.textContainer?.widthTracksTextView = true; transcript.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let transcriptScroll = NSScrollView(); self.transcriptScroll = transcriptScroll; transcriptScroll.documentView = transcript; transcriptScroll.hasVerticalScroller = true; transcriptScroll.borderType = .noBorder; transcriptScroll.drawsBackground = false; transcriptScroll.wantsLayer = true; transcriptScroll.layer?.cornerRadius = 15; transcriptScroll.layer?.borderWidth = 1; transcriptScroll.layer?.borderColor = NSColor(calibratedRed: 0.92, green: 0.68, blue: 0.78, alpha: 0.6).cgColor; transcriptScroll.translatesAutoresizingMaskIntoConstraints = false; transcriptScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        let dropZone = ImageDropZone(frame: .zero); imageDropZone = dropZone; dropZone.translatesAutoresizingMaskIntoConstraints = false; dropZone.widthAnchor.constraint(equalToConstant: 94).isActive = true; dropZone.heightAnchor.constraint(equalToConstant: 62).isActive = true
        dropZone.onImage = { [weak self] url in self?.imageURL = url; self?.statusLabel.stringValue = "已附加：\(url.lastPathComponent)" }
        dropZone.onClear = { [weak self] in self?.imageURL = nil; self?.statusLabel.stringValue = "附件已移除，可以重新选择或继续输入。"; self?.window?.makeFirstResponder(self?.input) }
        dropZone.onError = { [weak self] message in self?.imageURL = nil; self?.statusLabel.stringValue = message; self?.statusLabel.textColor = .systemRed; self?.window?.makeFirstResponder(self?.input) }
        input.appearance = NSAppearance(named: .aqua); input.font = .systemFont(ofSize: 14); input.textColor = ink; input.backgroundColor = .white; input.drawsBackground = true; input.isEditable = true; input.isSelectable = true; input.isEnabled = true; input.refusesFirstResponder = false; input.isBezeled = true; input.bezelStyle = .roundedBezel; input.placeholderString = "在这里输入文字…"; input.focusRingType = .default; input.target = self; input.action = #selector(send); input.translatesAutoresizingMaskIntoConstraints = false; input.heightAnchor.constraint(equalToConstant: 62).isActive = true
        input.toolTip = "点击后输入文字，按回车发送"
        let send = AemisActionButton("发送", target: self, action: #selector(send)); send.widthAnchor.constraint(equalToConstant: 78).isActive = true
        let composer = NSStackView(views: [dropZone, input, send]); composer.orientation = .horizontal; composer.alignment = .bottom; composer.spacing = 9
        statusLabel.font = .systemFont(ofSize: 11, weight: .semibold); statusLabel.textColor = teal; statusLabel.alignment = .center; statusLabel.lineBreakMode = .byTruncatingMiddle
        let root = NSStackView(views: [header, transcriptScroll, statusLabel, composer]); root.orientation = .vertical; root.alignment = .width; root.spacing = 10; root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 15, right: 24); root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: leadingAnchor), root.trailingAnchor.constraint(equalTo: trailingAnchor), root.topAnchor.constraint(equalTo: topAnchor), root.bottomAnchor.constraint(equalTo: bottomAnchor), input.widthAnchor.constraint(greaterThanOrEqualToConstant: 170)])
    }

    @objc private func closeChat() { onDismiss?() }
    func focusInput() { window?.makeFirstResponder(input) }
    @objc private func changeWidth(_ sender: NSSlider) { onWidthChanged?(CGFloat(sender.doubleValue)) }
    @objc private func send() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || imageURL != nil else { return }
        let shown = text.isEmpty ? "请看看这张图片。" : text
        store.append(role: "user", content: shown, imagePath: imageURL?.path, presetID: presetID); input.stringValue = ""; reloadTranscript()
        guard let key = AemisKeychain.load(), !key.isEmpty else { statusLabel.stringValue = "请先在爱弥斯设置的 AI 页保存 API Key。"; return }
        statusLabel.stringValue = "爱弥斯正在思考…"
        let messages = store.recentMessages(presetID: presetID).map { ($0.role, $0.content) }; let attached = imageURL; imageURL = nil; imageDropZone?.clearSelection()
        AemisDeepSeekService.request(configuration: AemisAIConfiguration.load(), key: key, messages: messages, memories: store.recentMemories(presetID: presetID), profileSummary: store.profileSummary(presetID: presetID), imageURL: attached) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let answer): self?.store.append(role: "assistant", content: answer, presetID: self?.presetID ?? "default"); self?.statusLabel.stringValue = "已回复"; self?.reloadTranscript()
                case .failure(let error): self?.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func reloadTranscript() {
        transcript.string = store.recentMessages(limit: 40, presetID: presetID).map { "\($0.role == "assistant" ? "爱弥斯" : "你")：\($0.content)" }.joined(separator: "\n\n")
        if transcript.string.isEmpty { transcript.string = "从这里开始和爱弥斯聊天吧。" }
        transcript.scrollToEndOfDocument(nil)
        DispatchQueue.main.async { [weak self] in self?.requestRoomForTranscriptIfNeeded() }
    }

    private func requestRoomForTranscriptIfNeeded() {
        guard let scroll = transcriptScroll, let layoutManager = transcript.layoutManager,
              let textContainer = transcript.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height + transcript.textContainerInset.height * 2
        let overflow = usedHeight - scroll.contentSize.height
        if overflow > 10 { onHeightGrowthRequested?(ceil(overflow + 18)) }
    }
}

final class AemisChatWindowController: NSWindowController {
    private let store: AemisConversationStore
    private let transcript = NSTextView()
    private let input = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "准备好陪你聊天")
    private var imageURL: URL?

    init(store: AemisConversationStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "爱弥斯 · 聊天"; window.minSize = NSSize(width: 420, height: 480); window.center()
        super.init(window: window); buildInterface(); reloadTranscript()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface() {
        guard let window else { return }
        let material = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero); material.material = .hudWindow; material.state = .active; material.autoresizingMask = [.width, .height]; window.contentView = material
        let title = NSTextField(labelWithString: "爱弥斯"); title.font = .systemFont(ofSize: 20, weight: .bold); title.textColor = .systemPink
        let subtitle = NSTextField(labelWithString: "图片可拖入；模型需要在设置中配置并测试"); subtitle.textColor = .secondaryLabelColor
        transcript.isEditable = false; transcript.backgroundColor = .clear; transcript.font = .systemFont(ofSize: 14); transcript.textColor = .labelColor
        let transcriptScroll = NSScrollView(); transcriptScroll.documentView = transcript; transcriptScroll.hasVerticalScroller = true; transcriptScroll.borderType = .noBorder; transcriptScroll.translatesAutoresizingMaskIntoConstraints = false; transcriptScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        let dropZone = ImageDropZone(frame: NSRect(x: 0, y: 0, width: 200, height: 48)); dropZone.translatesAutoresizingMaskIntoConstraints = false; dropZone.widthAnchor.constraint(equalToConstant: 155).isActive = true; dropZone.heightAnchor.constraint(equalToConstant: 48).isActive = true
        dropZone.onImage = { [weak self] url in self?.imageURL = url; self?.statusLabel.stringValue = "已附加图片：\(url.lastPathComponent)" }
        input.font = .systemFont(ofSize: 14); input.isRichText = false
        let inputScroll = NSScrollView(); inputScroll.documentView = input; inputScroll.hasVerticalScroller = true; inputScroll.borderType = .bezelBorder; inputScroll.translatesAutoresizingMaskIntoConstraints = false; inputScroll.heightAnchor.constraint(equalToConstant: 74).isActive = true
        let send = NSButton(title: "发送", target: self, action: #selector(send)); send.bezelColor = .systemPink
        statusLabel.textColor = .secondaryLabelColor
        let top = NSStackView(views: [title, subtitle]); top.orientation = .vertical; top.alignment = .leading; top.spacing = 2
        let bottom = NSStackView(views: [dropZone, inputScroll, send]); bottom.orientation = .horizontal; bottom.alignment = .bottom; bottom.spacing = 9
        let root = NSStackView(views: [top, transcriptScroll, statusLabel, bottom]); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10; root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18); root.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(root); NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: material.leadingAnchor), root.trailingAnchor.constraint(equalTo: material.trailingAnchor), root.topAnchor.constraint(equalTo: material.topAnchor), root.bottomAnchor.constraint(equalTo: material.bottomAnchor), inputScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 190)])
    }

    @objc private func send() {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || imageURL != nil else { return }
        let shownText = text.isEmpty ? "请看看这张图片。" : text
        store.append(role: "user", content: shownText, imagePath: imageURL?.path); input.string = ""; reloadTranscript()
        guard let key = AemisKeychain.load(), !key.isEmpty else { statusLabel.stringValue = "请先在“爱弥斯设置 → AI 对话”保存 API Key。"; return }
        statusLabel.stringValue = "爱弥斯正在思考…"
        let messages = store.recentMessages().map { ($0.role, $0.content) }
        let attachedImage = imageURL; imageURL = nil
        AemisDeepSeekService.request(configuration: AemisAIConfiguration.load(), key: key, messages: messages, memories: store.recentMemories(), imageURL: attachedImage) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let answer): self?.store.append(role: "assistant", content: answer); self?.statusLabel.stringValue = "已回复"; self?.reloadTranscript()
                case .failure(let error): self?.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func reloadTranscript() {
        let text = store.recentMessages(limit: 40).map { message in "\(message.role == "assistant" ? "爱弥斯" : "你")：\(message.content)" }.joined(separator: "\n\n")
        transcript.string = text.isEmpty ? "点击粉色气泡，就可以和爱弥斯聊天。" : text
        transcript.scrollToEndOfDocument(nil)
    }
}
