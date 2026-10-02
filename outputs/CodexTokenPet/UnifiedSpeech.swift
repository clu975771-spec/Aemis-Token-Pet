import Foundation

/// Human speech uses a common measured bank; short interaction sounds stay independent.
enum UnifiedSpeech {
    struct Selection { let url: URL; let playerVolume: Float; let percent: Int }
    private struct Manifest: Decodable { let clips: [Clip] }
    private struct Clip: Decodable { let source: String; let percent: Int; let file: String }
    static let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("voice-assets/unified")
    private static let clips: [Clip] = {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.clips
    }()
    static func resolve(_ original: URL, volume: Float) -> Selection? {
        guard volume.isFinite, volume > 0 else { return nil }
        let gain = min(2, volume)
        let percent = gain > 1 ? min(200, max(105, Int((Double(gain) * 20).rounded()) * 5)) : 100
        guard let clip = clips.first(where: { ($0.source == original.standardizedFileURL.path || $0.source == "voice-assets/" + original.path.components(separatedBy: "/voice-assets/").last!) && $0.percent == percent }) else {
            fputs("speech: normalized bank missing for \(original.lastPathComponent); falling back to original audio\n", stderr)
            return FileManager.default.fileExists(atPath: original.path) ? Selection(url: original, playerVolume: min(1, gain), percent: 100) : nil
        }
        let url = directory.appendingPathComponent(clip.file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fputs("speech: bank file unavailable; using original audio\n", stderr)
            return FileManager.default.fileExists(atPath: original.path) ? Selection(url: original, playerVolume: min(1, gain), percent: 100) : nil
        }
        return Selection(url: url, playerVolume: min(1, gain), percent: percent)
    }
}
