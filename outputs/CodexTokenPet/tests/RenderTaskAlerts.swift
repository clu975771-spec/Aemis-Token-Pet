import AppKit

@main struct RenderTaskAlerts {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("usage: renderer output-dir asset-dir") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let assets = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for role in ["aemis"] {
            for kind in [CodexTaskAlertKind.complete, .problem] {
                for (caseName, taskName) in [
                    ("zh", "这是一个很长的中文任务名称，用于验证完成或问题提醒时气泡不会扩大"),
                    ("en", "A very long English task title used only inside an isolated rendering test")
                ] {
                    let size = NSSize(width: 229, height: 257)
                    let view = BubbleView(frame: NSRect(origin: .zero, size: size))
                    view.bubbleSize = 0.9
                    view.selectedBuiltInMascotID = role
                    view.themeColor = BuiltInCharacterProfile.profile(for: role).bubbleFill
                    view.mascot = NSImage(contentsOf: assets.appendingPathComponent("\(role).png"))
                    view.showTaskAlert(.init(key: "test", threadID: UUID().uuidString, kind: kind, reason: "test", title: taskName, project: "test", timestamp: 0))
                    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    let transform = NSAffineTransform()
                    transform.scaleX(by: 2, yBy: 2)
                    transform.concat()
                    view.draw(view.bounds)
                    NSGraphicsContext.restoreGraphicsState()
                    let data = rep.representation(using: .png, properties: [:])!
                    try data.write(to: destination.appendingPathComponent("\(role)-\(kind.rawValue)-\(caseName).png"))
                }
            }
        }
    }
}
