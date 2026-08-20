import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import AVFoundation

struct UsageSnapshot { let projectName: String; let projectTokens: Int; let lastTokens: Int }
enum DisplayMode: String { case automatic, tokenOnly, appOnly }
enum DockPosition: String { case bottomRight, bottomLeft, topRight, topLeft
    var title: String { switch self { case .bottomRight: return "右下角"; case .bottomLeft: return "左下角"; case .topRight: return "右上角"; case .topLeft: return "左上角" } }
}
enum InteractionTrigger: String, CaseIterable {
    case doubleTap, fiveTaps, fifteenTaps, idleFifteenSeconds, appSwitch
    var title: String { switch self { case .doubleTap: return "连续点击 2 次"; case .fiveTaps: return "连续点击 5 次"; case .fifteenTaps: return "连续点击 15 次"; case .idleFifteenSeconds: return "15 秒未互动"; case .appSwitch: return "切换前台软件" } }
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

    func latestSnapshot() -> UsageSnapshot? {
        guard let project = mostRecentlyFocusedProject() else { return nil }
        return UsageSnapshot(projectName: project.name,
                             projectTokens: project.totalTokens, lastTokens: latestTokenEvent() ?? 0)
    }

    // `tokens_used` is Codex's exact per-thread counter. Grouping it by cwd gives
    // the total of every conversation belonging to the project most recently focused in Codex.
    private func mostRecentlyFocusedProject() -> (cwd: String, name: String, totalTokens: Int)? {
        let query = """
        WITH active_project AS (SELECT cwd, title FROM threads WHERE archived = 0 ORDER BY recency_at_ms DESC LIMIT 1)
        SELECT active_project.cwd, active_project.title, COALESCE(SUM(threads.tokens_used), 0)
        FROM threads, active_project WHERE threads.archived = 0 AND threads.cwd = active_project.cwd
        GROUP BY active_project.cwd, active_project.title;
        """
        guard let result = sqlite(query)?.split(separator: "\t", maxSplits: 2).map(String.init),
              result.count == 3, let tokens = Int(result[2]) else { return nil }
        return (result[0], result[1], tokens)
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

    private func latestTokenEvent() -> Int? {
        let sessions = root.appendingPathComponent("sessions")
        guard let enumerator = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        var newest: (URL, Date)?
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true, let date = values.contentModificationDate else { continue }
            if newest == nil || date > newest!.1 { newest = (url, date) }
        }
        guard let file = newest?.0, let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"type\":\"token_count\""), let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any], let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any], let tokens = last["total_tokens"] as? Int else { continue }
            return tokens
        }
        return nil
    }
}

final class BubbleView: NSView {
    var snapshot: UsageSnapshot? { didSet { needsDisplay = true } }; var mascot: NSImage?
    var frontmostContext: FrontmostContext? { didSet { needsDisplay = true } }
    var onMascotTap: (() -> Void)?
    var onChooseMascot: (() -> Void)?; var onChooseColor: (() -> Void)?; var onResetAppearance: (() -> Void)?
    var onSetDisplayMode: ((DisplayMode) -> Void)?; var onSetMascotSize: ((CGFloat) -> Void)?; var onToggleClickSound: (() -> Void)?
    var onSetBubbleSize: ((CGFloat) -> Void)?; var onSetTapSound: ((TapSound) -> Void)?; var onSetSoundVolume: ((Float) -> Void)?
    var onSetBubbleOpacity: ((CGFloat) -> Void)?; var onChooseCustomSound: (() -> Void)?; var onSetPatMessage: (() -> Void)?; var onSavePreset: (() -> Void)?; var onImportPresetPack: (() -> Void)?; var onExportPresetPack: (() -> Void)?; var onImportEventImages: (() -> Void)?; var onImportClickSounds: (() -> Void)?; var onImportEventSounds: (() -> Void)?; var onApplyPreset: ((String) -> Void)?; var onRememberPosition: (() -> Void)?; var onDockPosition: ((DockPosition) -> Void)?; var onInteraction: (() -> Void)?
    var themeColor = NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.96, alpha: 0.97) { didSet { needsDisplay = true } }
    var mascotSize: CGFloat = 1 { didSet { needsDisplay = true } }
    var bubbleSize: CGFloat = 1 { didSet { needsDisplay = true } }
    var bubbleOpacity: CGFloat = 0.97 { didSet { needsDisplay = true } }
    var displayMode: DisplayMode = .automatic { didSet { needsDisplay = true } }
    var clickSoundEnabled = true
    var tapSound: TapSound = .basso
    var customSoundPath: String?
    var soundVolume: Float = 0.55
    var patMessage = "不要再拍我了"
    var presets: [CharacterPreset] = []
    var todayInteractions = 0
    var eventImages: [TriggeredAsset] = []
    var eventSounds: [TriggeredAsset] = []
    var clickSoundPaths: [String] = []
    private var mascotScaleX: CGFloat = 1
    private var mascotScaleY: CGFloat = 1
    private var mascotYOffset: CGFloat = 0
    private var bubbleScaleX: CGFloat = 1
    private var bubbleScaleY: CGFloat = 1
    private var bubbleYOffset: CGFloat = 0
    private var jellyTimer: Timer?
    private var recentTapTimes: [Date] = []
    private var showingNoMorePatMessage = false
    private var showingTapSpeed = false
    private var tapSpeedDismissTimer: Timer?
    private var temporaryMascot: NSImage?
    private var temporaryMascotTimer: Timer?
    private var lastInteractionAt = Date()
    private var firedTapTriggers = Set<InteractionTrigger>()
    private var idleTimer: Timer?
    private weak var soundVolumeLabel: NSMenuItem?
    private weak var mascotSizeLabel: NSMenuItem?
    private weak var bubbleSizeLabel: NSMenuItem?
    private weak var bubbleOpacityLabel: NSMenuItem?
    private var lastTapSpeed: Double = 0

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.control), point.y < 158 { showSettingsMenu(at: point); return }
        // The lower section is the mascot. Let the metric bubble remain draggable.
        if point.y < 158 {
            playTapSound()
            onMascotTap?()
            startJelly()
            registerTap()
            onInteraction?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastInteractionAt) >= 15 else { return }
            self.lastInteractionAt = Date(); self.trigger(.idleFifteenSeconds)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y < 158 { showSettingsMenu(at: point) } else { super.rightMouseDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 5, dy: 4)
        let mascotHeight: CGFloat = 154 * mascotSize
        let bubbleBase = mascotHeight - 1
        let rawBubbleRect = NSRect(x: bounds.midX - 121 * bubbleSize, y: bubbleBase, width: 242 * bubbleSize, height: 111 * bubbleSize)
        let bubbleRect = NSRect(x: rawBubbleRect.midX - rawBubbleRect.width * bubbleScaleX / 2,
                                y: rawBubbleRect.midY - rawBubbleRect.height * bubbleScaleY / 2 + bubbleYOffset,
                                width: rawBubbleRect.width * bubbleScaleX, height: rawBubbleRect.height * bubbleScaleY)
        let fill = themeColor.withAlphaComponent(bubbleOpacity)
        let outline = themeColor.blended(withFraction: 0.34, of: .systemPink) ?? .systemPink
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
        let title: String
        let total: String
        let detail: String
        if showingNoMorePatMessage {
            title = "爱弥斯的请求"
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
            detail = showingTapSpeed ? String(format: "连点速度 %.1f 次/秒", currentTapSpeed) : (snapshot.map { "项目总消耗 · 最近 +\(format($0.lastTokens))" } ?? "等待 Codex 项目记录")
        }
        let titleY = bubbleY(rawBubbleRect.maxY - 29 * bubbleSize, center: rawBubbleRect.midY)
        title.draw(in: NSRect(x: bubbleRect.minX + 13, y: titleY, width: bubbleRect.width - 26, height: 17 * bubbleSize * bubbleScaleY), withAttributes: [.font: NSFont.systemFont(ofSize: 13 * bubbleSize, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.69, green: 0.26, blue: 0.43, alpha: 1), .paragraphStyle: paragraph])
        let totalFontSize: CGFloat = showingApp ? 27 : 31
        total.draw(in: NSRect(x: bubbleRect.minX + 13, y: bubbleY(rawBubbleRect.minY + 40 * bubbleSize, center: rawBubbleRect.midY), width: bubbleRect.width - 26, height: 39 * bubbleSize * bubbleScaleY), withAttributes: [.font: NSFont.systemFont(ofSize: totalFontSize * bubbleSize, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.82, green: 0.30, blue: 0.49, alpha: 1), .paragraphStyle: paragraph])
        detail.draw(in: NSRect(x: bubbleRect.minX + 13, y: bubbleY(rawBubbleRect.minY + 17 * bubbleSize, center: rawBubbleRect.midY), width: bubbleRect.width - 26, height: 16 * bubbleSize * bubbleScaleY), withAttributes: [.font: NSFont.systemFont(ofSize: 11 * bubbleSize, weight: .medium), .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.66, blue: 0.73, alpha: 1), .paragraphStyle: paragraph])
        if let mascot = temporaryMascot ?? mascot {
            let h: CGFloat = 154 * mascotSize; let w = h * mascot.size.width / mascot.size.height
            let scaledW = w * mascotScaleX; let scaledH = h * mascotScaleY
            mascot.draw(in: NSRect(x: (bounds.width - scaledW) / 2, y: mascotYOffset, width: scaledW, height: scaledH), from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
    private func showSettingsMenu(at point: NSPoint) {
        let menu = NSMenu(title: "爱弥斯")
        menu.autoenablesItems = false
        let workshop = NSMenu(title: "爱弥斯 · 角色工作台")
        let presetMenu = NSMenu(title: "选择人物预设")
        for preset in presets {
            let item = NSMenuItem(title: preset.name, action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.representedObject = preset.id; presetMenu.addItem(item)
        }
        presetMenu.addItem(.separator())
        presetMenu.addItem(withTitle: "添加自定义人物预设…", action: #selector(savePreset), keyEquivalent: "")
        let presetItem = NSMenuItem(title: "选择人物预设", action: nil, keyEquivalent: ""); presetItem.submenu = presetMenu; workshop.addItem(presetItem)
        workshop.addItem(withTitle: "将当前爱弥斯保存为预设…", action: #selector(savePreset), keyEquivalent: "")
        workshop.addItem(withTitle: "导入人物预设包…", action: #selector(importPresetPack), keyEquivalent: "")
        workshop.addItem(withTitle: "导出当前人物预设包…", action: #selector(exportPresetPack), keyEquivalent: "")
        workshop.addItem(.separator())
        workshop.addItem(withTitle: "更换透明 PNG 人物…", action: #selector(requestMascot), keyEquivalent: "")
        workshop.addItem(withTitle: "聊天框颜色…", action: #selector(requestColor), keyEquivalent: "")
        workshop.addItem(withTitle: "连点台词…", action: #selector(requestPatMessage), keyEquivalent: "")
        let interactionItem = NSMenuItem(title: "今日已互动 \(todayInteractions) 次", action: nil, keyEquivalent: ""); interactionItem.isEnabled = false; workshop.addItem(interactionItem)
        let soundItem = NSMenuItem(title: "点击音效 · 咚咚", action: #selector(toggleClickSound), keyEquivalent: "")
        soundItem.state = clickSoundEnabled ? .on : .off; workshop.addItem(soundItem)
        let soundMenu = NSMenu(title: "音效类型")
        for sound in TapSound.allCases {
            let item = NSMenuItem(title: sound.title, action: #selector(setTapSound(_:)), keyEquivalent: "")
            item.representedObject = sound.rawValue; item.state = tapSound == sound ? .on : .off; soundMenu.addItem(item)
        }
        soundMenu.addItem(.separator()); soundMenu.addItem(withTitle: "导入 15 秒以内音效…", action: #selector(requestCustomSound), keyEquivalent: "")
        let soundMenuItem = NSMenuItem(title: "音效类型", action: nil, keyEquivalent: ""); soundMenuItem.submenu = soundMenu; workshop.addItem(soundMenuItem)
        let interactionMenu = NSMenu(title: "互动素材")
        interactionMenu.addItem(withTitle: "批量导入触发图片…", action: #selector(importEventImages), keyEquivalent: "")
        interactionMenu.addItem(withTitle: "批量导入点击语音…", action: #selector(importClickSounds), keyEquivalent: "")
        interactionMenu.addItem(withTitle: "批量导入触发语音…", action: #selector(importEventSounds), keyEquivalent: "")
        interactionMenu.addItem(.separator())
        let imageInfo = NSMenuItem(title: "已绑定触发图片 \(eventImages.count) 张", action: nil, keyEquivalent: ""); imageInfo.isEnabled = false; interactionMenu.addItem(imageInfo)
        let soundInfo = NSMenuItem(title: "点击语音 \(clickSoundPaths.count) 段 · 触发语音 \(eventSounds.count) 段", action: nil, keyEquivalent: ""); soundInfo.isEnabled = false; interactionMenu.addItem(soundInfo)
        let interactionAssetsItem = NSMenuItem(title: "互动素材与触发条件", action: nil, keyEquivalent: ""); interactionAssetsItem.submenu = interactionMenu; workshop.addItem(interactionAssetsItem)
        let volumeTitle = NSMenuItem(title: "音量 \(Int(soundVolume * 100))%", action: nil, keyEquivalent: ""); volumeTitle.isEnabled = false; soundVolumeLabel = volumeTitle; workshop.addItem(volumeTitle)
        let slider = NSSlider(value: Double(soundVolume), minValue: 0, maxValue: 1, target: self, action: #selector(soundVolumeChanged(_:)))
        slider.isContinuous = true; slider.frame = NSRect(x: 12, y: 0, width: 170, height: 22)
        let sliderItem = NSMenuItem(); sliderItem.view = slider; workshop.addItem(sliderItem)
        mascotSizeLabel = addSizeSlider(title: "人物大小 \(Int(mascotSize * 100))%", value: mascotSize, action: #selector(mascotSizeChanged(_:)), to: workshop)
        bubbleSizeLabel = addSizeSlider(title: "聊天框大小 \(Int(bubbleSize * 100))%", value: bubbleSize, action: #selector(bubbleSizeChanged(_:)), to: workshop)
        bubbleOpacityLabel = addSlider(title: "气泡透明度 \(Int(bubbleOpacity * 100))%", value: bubbleOpacity, min: 0.35, max: 1, action: #selector(bubbleOpacityChanged(_:)), to: workshop)
        let modeMenu = NSMenu(title: "显示模式")
        for (title, mode) in [("自动切换", DisplayMode.automatic), ("始终显示 Token", DisplayMode.tokenOnly), ("始终显示前台软件", DisplayMode.appOnly)] {
            let item = NSMenuItem(title: title, action: #selector(setDisplayMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue; item.state = displayMode == mode ? .on : .off; modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "显示模式", action: nil, keyEquivalent: ""); modeItem.submenu = modeMenu; workshop.addItem(modeItem)
        let dockMenu = NSMenu(title: "位置吸附")
        for position in [DockPosition.bottomRight, .bottomLeft, .topRight, .topLeft] {
            let item = NSMenuItem(title: position.title, action: #selector(dockPosition(_:)), keyEquivalent: ""); item.representedObject = position.rawValue; dockMenu.addItem(item)
        }
        let dockItem = NSMenuItem(title: "位置吸附", action: nil, keyEquivalent: ""); dockItem.submenu = dockMenu; workshop.addItem(dockItem)
        workshop.addItem(.separator())
        workshop.addItem(withTitle: "恢复默认外观", action: #selector(requestReset), keyEquivalent: "")
        let workshopItem = NSMenuItem(title: "爱弥斯 · 角色工作台", action: nil, keyEquivalent: ""); workshopItem.submenu = workshop; menu.addItem(workshopItem)
        menu.addItem(withTitle: "记住当前位置", action: #selector(rememberPosition), keyEquivalent: "")
        prepareMenuItems(menu)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    // This borderless, non-activating panel is deliberately not key. Assigning the
    // menu target explicitly prevents AppKit from disabling every action item.
    private func prepareMenuItems(_ menu: NSMenu) {
        menu.autoenablesItems = false
        for item in menu.items {
            if item.action != nil { item.target = self; item.isEnabled = true }
            if item.submenu != nil { item.isEnabled = true; prepareMenuItems(item.submenu!) }
        }
    }
    @objc private func requestMascot() { onChooseMascot?() }
    @objc private func requestColor() { onChooseColor?() }
    @objc private func toggleClickSound() { onToggleClickSound?() }
    @objc private func setTapSound(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let sound = TapSound(rawValue: raw) { onSetTapSound?(sound) } }
    @objc private func soundVolumeChanged(_ sender: NSSlider) { soundVolumeLabel?.title = "音量 \(Int(sender.floatValue * 100))%"; onSetSoundVolume?(sender.floatValue) }
    @objc private func mascotSizeChanged(_ sender: NSSlider) { mascotSizeLabel?.title = "人物大小 \(Int(sender.doubleValue * 100))%"; onSetMascotSize?(CGFloat(sender.doubleValue)) }
    @objc private func bubbleSizeChanged(_ sender: NSSlider) { bubbleSizeLabel?.title = "聊天框大小 \(Int(sender.doubleValue * 100))%"; onSetBubbleSize?(CGFloat(sender.doubleValue)) }
    @objc private func bubbleOpacityChanged(_ sender: NSSlider) { bubbleOpacityLabel?.title = "气泡透明度 \(Int(sender.doubleValue * 100))%"; onSetBubbleOpacity?(CGFloat(sender.doubleValue)) }
    @objc private func requestCustomSound() { onChooseCustomSound?() }
    @objc private func requestPatMessage() { onSetPatMessage?() }
    @objc private func importEventImages() { onImportEventImages?() }
    @objc private func importClickSounds() { onImportClickSounds?() }
    @objc private func importEventSounds() { onImportEventSounds?() }
    @objc private func savePreset() { onSavePreset?() }
    @objc private func importPresetPack() { onImportPresetPack?() }
    @objc private func exportPresetPack() { onExportPresetPack?() }
    @objc private func applyPreset(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onApplyPreset?(id) } }
    @objc private func rememberPosition() { onRememberPosition?() }
    @objc private func dockPosition(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let position = DockPosition(rawValue: raw) { onDockPosition?(position) } }
    @objc private func requestReset() { onResetAppearance?() }
    @objc private func setMascotSize(_ sender: NSMenuItem) { if let value = sender.representedObject as? CGFloat { onSetMascotSize?(value) } }
    @objc private func setDisplayMode(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) { onSetDisplayMode?(mode) } }
    private func bubbleY(_ y: CGFloat, center: CGFloat) -> CGFloat { center + (y - center) * bubbleScaleY + bubbleYOffset }
    private func format(_ value: Int) -> String { value >= 1_000_000 ? String(format: "%.2fM", Double(value) / 1_000_000) : value >= 1_000 ? String(format: "%.1fK", Double(value) / 1_000) : "\(value)" }

    private func playTapSound() {
        guard clickSoundEnabled else { return }
        playSystemSound(path: clickSoundPaths.randomElement() ?? selectedClickSoundPath, volume: soundVolume)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            guard let self, self.clickSoundEnabled else { return }
            self.playSystemSound(path: self.clickSoundPaths.randomElement() ?? self.selectedClickSoundPath, volume: self.soundVolume * 0.72)
        }
    }

    private var selectedClickSoundPath: String? { tapSound == .custom ? customSoundPath : tapSound.filePath }
    private func playSystemSound(path: String?, volume: Float) {
        guard let path else { return }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = ["-v", String(max(0, min(1, volume))), path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func registerTap() {
        guard !showingNoMorePatMessage else { return }
        let now = Date()
        if now.timeIntervalSince(lastInteractionAt) > 3 { firedTapTriggers.removeAll() }
        lastInteractionAt = now; recentTapTimes.append(now)
        recentTapTimes.removeAll { now.timeIntervalSince($0) > 3 }
        if recentTapTimes.count >= 2 {
            showingTapSpeed = true; tapSpeedDismissTimer?.invalidate()
            tapSpeedDismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.showingTapSpeed = false; self?.needsDisplay = true }
            needsDisplay = true
        }
        if recentTapTimes.count >= 2, firedTapTriggers.insert(.doubleTap).inserted { trigger(.doubleTap) }
        if recentTapTimes.count >= 5, firedTapTriggers.insert(.fiveTaps).inserted { trigger(.fiveTaps) }
        guard recentTapTimes.count >= 15 else { return }
        if firedTapTriggers.insert(.fifteenTaps).inserted { trigger(.fifteenTaps) }
        lastTapSpeed = currentTapSpeed; recentTapTimes.removeAll(); showingNoMorePatMessage = true; needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.showingNoMorePatMessage = false; self?.needsDisplay = true
        }
    }

    func trigger(_ trigger: InteractionTrigger) {
        let key = trigger.rawValue
        if let imageAsset = eventImages.filter({ $0.trigger == key }).randomElement(), let image = NSImage(contentsOfFile: imageAsset.path) {
            temporaryMascot = image; temporaryMascotTimer?.invalidate()
            temporaryMascotTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.temporaryMascot = nil; self?.needsDisplay = true }
        }
        if let sound = eventSounds.filter({ $0.trigger == key }).randomElement() { playSystemSound(path: sound.path, volume: soundVolume) }
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reader = UsageReader(); private let frontmostAppReader = FrontmostAppReader(); private var panel: NSPanel!; private var bubble: BubbleView!; private var timer: Timer?; private var statusItem: NSStatusItem!; private var previousFrontmostApp: String?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory); buildPanel(); buildMenu(); refresh(); timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() } }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
    private func buildPanel() {
        let size = NSSize(width: 252, height: 272); let point = NSEvent.mouseLocation; let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        panel = NSPanel(contentRect: NSRect(x: screen.maxX - size.width - 20, y: screen.minY + 112, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = true
        bubble = BubbleView(frame: NSRect(origin: .zero, size: size)); loadAppearance()
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        bubble.mascot = customMascot() ?? NSImage(contentsOf: folder.appendingPathComponent("艾弥斯透明人物.png"))
        createDefaultPresetIfNeeded()
        bubble.onMascotTap = { [weak self] in self?.refresh() }
        bubble.onChooseMascot = { [weak self] in self?.chooseMascot() }; bubble.onChooseColor = { [weak self] in self?.chooseColor() }
        bubble.onResetAppearance = { [weak self] in self?.resetAppearance() }; bubble.onSetMascotSize = { [weak self] in self?.setMascotSize($0) }; bubble.onSetBubbleSize = { [weak self] in self?.setBubbleSize($0) }; bubble.onSetDisplayMode = { [weak self] in self?.setDisplayMode($0) }; bubble.onToggleClickSound = { [weak self] in self?.toggleClickSound() }; bubble.onSetTapSound = { [weak self] in self?.setTapSound($0) }; bubble.onSetSoundVolume = { [weak self] in self?.setSoundVolume($0) }
        bubble.onChooseCustomSound = { [weak self] in self?.chooseCustomSound() }; bubble.onSetPatMessage = { [weak self] in self?.choosePatMessage() }; bubble.onSavePreset = { [weak self] in self?.savePreset() }; bubble.onImportPresetPack = { [weak self] in self?.importPresetPack() }; bubble.onExportPresetPack = { [weak self] in self?.exportPresetPack() }; bubble.onImportEventImages = { [weak self] in self?.importEventImages() }; bubble.onImportClickSounds = { [weak self] in self?.importClickSounds() }; bubble.onImportEventSounds = { [weak self] in self?.importEventSounds() }; bubble.onApplyPreset = { [weak self] in self?.applyPreset(id: $0) }; bubble.onRememberPosition = { [weak self] in self?.rememberPosition() }; bubble.onSetBubbleOpacity = { [weak self] in self?.setBubbleOpacity($0) }; bubble.onDockPosition = { [weak self] in self?.dock($0) }; bubble.onInteraction = { [weak self] in self?.recordInteraction() }
        panel.contentView = bubble; resizePanelToMascot(); restorePositionIfAvailable(); panel.orderFrontRegardless()
    }
    private func buildMenu() { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); statusItem.button?.title = "◌ Token"; let menu = NSMenu(); menu.addItem(withTitle: "立即刷新", action: #selector(refreshFromMenu), keyEquivalent: "r"); menu.addItem(.separator()); menu.addItem(withTitle: "退出 Token 小气泡", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); statusItem.menu = menu }
    @objc private func refreshFromMenu() { refresh() }
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
        if let text = defaults.string(forKey: "patMessage"), !text.isEmpty { bubble.patMessage = text }
        let today = Self.dayKey(); if defaults.string(forKey: "interactionDay") == today { bubble.todayInteractions = defaults.integer(forKey: "todayInteractions") }
        if let data = defaults.data(forKey: "characterPresets"), let presets = try? JSONDecoder().decode([CharacterPreset].self, from: data) { bubble.presets = presets }
        if let data = defaults.data(forKey: "eventImages"), let assets = try? JSONDecoder().decode([TriggeredAsset].self, from: data) { bubble.eventImages = assets }
        if let data = defaults.data(forKey: "eventSounds"), let assets = try? JSONDecoder().decode([TriggeredAsset].self, from: data) { bubble.eventSounds = assets }
        bubble.clickSoundPaths = defaults.stringArray(forKey: "clickSoundPaths") ?? []
    }
    private func customMascot() -> NSImage? { UserDefaults.standard.string(forKey: "mascotPath").flatMap { NSImage(contentsOfFile: $0) } }
    private func chooseMascot() {
        NSApp.activate(ignoringOtherApps: true)
        let chooser = NSOpenPanel(); chooser.title = "选择已抠图的透明 PNG 人物"; chooser.message = "请选择透明背景 PNG；它会在右键菜单中保存为当前人物。"; chooser.allowedContentTypes = [.png]; chooser.allowsMultipleSelection = false
        chooser.begin { [weak self] response in
            guard response == .OK, let url = chooser.url, let image = NSImage(contentsOf: url) else { return }
            self?.bubble.mascot = image; self?.resizePanelToMascot(); UserDefaults.standard.set(url.path, forKey: "mascotPath")
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
    private func importEventImages() { chooseTrigger(title: "为哪种情况绑定人物图片？") { [weak self] trigger in
        let panel = NSOpenPanel(); panel.title = "批量导入触发人物图片"; panel.message = "支持 PNG、JPG、WebP、GIF 等系统可识别图片。"; panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.begin { response in guard response == .OK else { return }; self?.bubble.eventImages += panel.urls.map { TriggeredAsset(id: UUID().uuidString, trigger: trigger.rawValue, path: $0.path) }; self?.persistInteractionAssets() }
    } }
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
    private func persistInteractionAssets() {
        let defaults = UserDefaults.standard; if let data = try? JSONEncoder().encode(bubble.eventImages) { defaults.set(data, forKey: "eventImages") }; if let data = try? JSONEncoder().encode(bubble.eventSounds) { defaults.set(data, forKey: "eventSounds") }; defaults.set(bubble.clickSoundPaths, forKey: "clickSoundPaths")
    }
    private func showError(_ message: String) { let alert = NSAlert(); alert.messageText = "无法使用这个音效"; alert.informativeText = message; alert.addButton(withTitle: "好"); alert.runModal() }
    private func setMascotSize(_ value: CGFloat) { bubble.mascotSize = value; resizePanelToMascot(); UserDefaults.standard.set(Double(value), forKey: "mascotSize") }
    private func setBubbleSize(_ value: CGFloat) { bubble.bubbleSize = value; resizePanelToMascot(); UserDefaults.standard.set(Double(value), forKey: "bubbleSize") }
    private func setBubbleOpacity(_ value: CGFloat) { bubble.bubbleOpacity = value; UserDefaults.standard.set(Double(value), forKey: "bubbleOpacity") }
    private func setDisplayMode(_ mode: DisplayMode) { bubble.displayMode = mode; UserDefaults.standard.set(mode.rawValue, forKey: "displayMode"); refresh() }
    private func toggleClickSound() { bubble.clickSoundEnabled.toggle(); UserDefaults.standard.set(bubble.clickSoundEnabled, forKey: "clickSoundEnabled") }
    private func setTapSound(_ sound: TapSound) { bubble.tapSound = sound; UserDefaults.standard.set(sound.rawValue, forKey: "tapSound") }
    private func setSoundVolume(_ volume: Float) { bubble.soundVolume = volume; UserDefaults.standard.set(volume, forKey: "soundVolume") }
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
                pack.preset.name += "（导入）"; pack.preset = CharacterPreset(id: UUID().uuidString, name: pack.preset.name, mascotPath: pack.preset.mascotPath, color: pack.preset.color, mascotSize: pack.preset.mascotSize, bubbleSize: pack.preset.bubbleSize, patMessage: pack.preset.patMessage, tapSound: pack.preset.tapSound, customSoundPath: pack.preset.customSoundPath, soundVolume: pack.preset.soundVolume, eventImages: pack.preset.eventImages, eventSounds: pack.preset.eventSounds, clickSoundPaths: pack.preset.clickSoundPaths)
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
        bubble.themeColor = NSColor(calibratedRed: preset.color.red, green: preset.color.green, blue: preset.color.blue, alpha: preset.color.alpha)
        bubble.mascotSize = preset.mascotSize; bubble.bubbleSize = preset.bubbleSize; bubble.patMessage = preset.patMessage; bubble.tapSound = TapSound(rawValue: preset.tapSound) ?? .basso; bubble.customSoundPath = preset.customSoundPath; bubble.soundVolume = preset.soundVolume; bubble.eventImages = preset.eventImages ?? []; bubble.eventSounds = preset.eventSounds ?? []; bubble.clickSoundPaths = preset.clickSoundPaths ?? []
        if let path = preset.mascotPath, let image = NSImage(contentsOfFile: path) { bubble.mascot = image; UserDefaults.standard.set(path, forKey: "mascotPath") }
        else { let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(); bubble.mascot = NSImage(contentsOf: folder.appendingPathComponent("艾弥斯透明人物.png")); UserDefaults.standard.removeObject(forKey: "mascotPath") }
        saveCurrentAppearance(); resizePanelToMascot()
    }
    private func persistPresets() { if let data = try? JSONEncoder().encode(bubble.presets) { UserDefaults.standard.set(data, forKey: "characterPresets") } }
    private func currentPreset(named name: String) -> CharacterPreset { CharacterPreset(id: UUID().uuidString, name: name, mascotPath: UserDefaults.standard.string(forKey: "mascotPath"), color: rgba(bubble.themeColor), mascotSize: bubble.mascotSize, bubbleSize: bubble.bubbleSize, patMessage: bubble.patMessage, tapSound: bubble.tapSound.rawValue, customSoundPath: bubble.customSoundPath, soundVolume: bubble.soundVolume, eventImages: bubble.eventImages, eventSounds: bubble.eventSounds, clickSoundPaths: bubble.clickSoundPaths) }
    private func createDefaultPresetIfNeeded() { guard bubble.presets.isEmpty else { return }; bubble.presets = [currentPreset(named: "爱弥斯 · 默认")]; persistPresets() }
    private func rgba(_ color: NSColor) -> SavedColor { let c = color.usingColorSpace(.deviceRGB) ?? color; return SavedColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent) }
    private func saveCurrentAppearance() {
        let defaults = UserDefaults.standard; defaults.set(Double(bubble.mascotSize), forKey: "mascotSize"); defaults.set(Double(bubble.bubbleSize), forKey: "bubbleSize"); defaults.set(Double(bubble.bubbleOpacity), forKey: "bubbleOpacity"); defaults.set(bubble.patMessage, forKey: "patMessage"); defaults.set(bubble.tapSound.rawValue, forKey: "tapSound"); defaults.set(bubble.customSoundPath, forKey: "customSoundPath"); defaults.set(bubble.soundVolume, forKey: "soundVolume")
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: bubble.themeColor, requiringSecureCoding: false) { defaults.set(data, forKey: "bubbleColor") }
    }
    private func rememberPosition() { UserDefaults.standard.set(panel.frame.origin.x, forKey: "panelX"); UserDefaults.standard.set(panel.frame.origin.y, forKey: "panelY") }
    private func restorePositionIfAvailable() { let d = UserDefaults.standard; guard d.object(forKey: "panelX") != nil, d.object(forKey: "panelY") != nil else { return }; var frame = panel.frame; frame.origin = NSPoint(x: d.double(forKey: "panelX"), y: d.double(forKey: "panelY")); panel.setFrame(frame, display: false) }
    private func dock(_ position: DockPosition) {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 20; var frame = panel.frame
        frame.origin.x = (position == .bottomLeft || position == .topLeft) ? screen.minX + margin : screen.maxX - frame.width - margin
        frame.origin.y = (position == .topLeft || position == .topRight) ? screen.maxY - frame.height - margin : screen.minY + margin
        panel.setFrame(frame, display: true, animate: true); rememberPosition()
    }
    private func recordInteraction() { let defaults = UserDefaults.standard; let today = Self.dayKey(); if defaults.string(forKey: "interactionDay") != today { bubble.todayInteractions = 0; defaults.set(today, forKey: "interactionDay") }; bubble.todayInteractions += 1; defaults.set(bubble.todayInteractions, forKey: "todayInteractions") }
    private static func dayKey() -> String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: Date()) }
    private func resetAppearance() {
        let defaults = UserDefaults.standard; ["mascotPath", "mascotSize", "bubbleSize", "bubbleOpacity", "bubbleColor", "displayMode", "clickSoundEnabled", "tapSound", "customSoundPath", "soundVolume", "patMessage"].forEach { defaults.removeObject(forKey: $0) }
        bubble.themeColor = NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.96, alpha: 0.97); bubble.mascotSize = 1; bubble.bubbleSize = 1; bubble.bubbleOpacity = 0.97; bubble.displayMode = .automatic; bubble.clickSoundEnabled = true; bubble.tapSound = .basso; bubble.customSoundPath = nil; bubble.soundVolume = 0.55; bubble.patMessage = "不要再拍我了"
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(); bubble.mascot = NSImage(contentsOf: folder.appendingPathComponent("艾弥斯透明人物.png")); resizePanelToMascot(); refresh()
    }
    private func resizePanelToMascot() {
        let mascotHeight = 154 * bubble.mascotSize
        let imageRatio = (bubble.mascot?.size.height ?? 0) > 0 ? bubble.mascot!.size.width / bubble.mascot!.size.height : 1
        let size = NSSize(width: max(252 * bubble.bubbleSize, ceil(mascotHeight * imageRatio + 12)), height: ceil(mascotHeight + 9 + 111 * bubble.bubbleSize + 8))
        var frame = panel.frame; frame.size = size
        panel.setFrame(frame, display: true, animate: true); bubble.frame = NSRect(origin: .zero, size: size); bubble.needsDisplay = true
    }
    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let context = self?.frontmostAppReader.current()
            let value = self?.reader.latestSnapshot()
            DispatchQueue.main.async {
                guard let self else { return }
                if let name = context?.appName, let previous = self.previousFrontmostApp, previous != name { self.bubble.trigger(.appSwitch) }
                self.previousFrontmostApp = context?.appName
                self.bubble.snapshot = value; self.bubble.frontmostContext = context
            }
        }
    }
}

let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.run()
