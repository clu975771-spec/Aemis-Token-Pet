import AppKit
import AVFoundation
import CoreImage

/// Native, editable PNG + JSON rig. Uses the exact approved v03 textures.
final class AemisLayeredRig {
    struct Layer: Decodable {
        let id: String; let file: String; let name: String; let enabled: Bool
        let pivot: [Double]; let amplitude: Double; let phase: Double
    }
    struct Model: Decodable { let format: String; let version: Int; let layers: [Layer] }
    private final class Meter { weak var player: AVAudioPlayer?; init(_ p: AVAudioPlayer) { player = p } }
    let model: Model
    private let images: [String: NSImage]
    private let rearImage: CIImage?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    // Spatially weighted inverse warp: crown and left hair stay fixed; right ponytail tips lag.
    private let rearWarp = CIWarpKernel(source: """
    kernel vec2 ponytail(float t, float strength) {
        vec2 p = destCoord() * 2.0;
        float u = clamp((p.x - 740.0) / 400.0, 0.0, 1.0);
        float v = clamp((900.0 - p.y) / 760.0, 0.0, 1.0);
        float w = u*u*(3.0-2.0*u)*v*v;
        return (p - vec2(strength*sin(t*1.25-v*1.1)*w,
                        strength*0.18*sin(t*1.25-v+0.5)*w)) * 0.5;
    }
    """)
    private var meters: [Meter] = []
    private var speechLevels: [Double] = []
    private var quietFrames = 0
    private var timer: Timer?
    private let epoch = ProcessInfo.processInfo.systemUptime
    private var previous = ProcessInfo.processInfo.systemUptime
    private var nextBlink = Double.random(in: 2.0...4.0)
    private var blinkStart = -100.0
    private var clickEyeHoldUntil = -100.0
    private var tapTime = -100.0
    private var tapSide = 0.0
    private(set) var time = 0.0
    private(set) var mouth = 0.0
    private(set) var eyeState = 0
    private(set) var audioDB = -160.0
    private(set) var blinkCount = 0
    var onFrame: (() -> Void)?
    var onTelemetry: ((Double, Double, Double, Int) -> Void)?
    init?(directory: URL) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("rig.json")),
              let model = try? JSONDecoder().decode(Model.self, from: data), model.format == "aemis-native-rig" else { return nil }
        var loaded: [String:NSImage] = [:]
        for layer in model.layers {
            guard let image = NSImage(contentsOf: directory.appendingPathComponent(layer.file)) else { return nil }
            loaded[layer.id] = image
        }
        self.model = model; images = loaded
        rearImage = CIImage(contentsOf:directory.appendingPathComponent("textures/H08.png"))?.transformed(by:CGAffineTransform(scaleX:0.5,y:0.5))
    }
    deinit { timer?.invalidate() }
    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    func track(_ player: AVAudioPlayer) {
        player.isMeteringEnabled = true
        if !meters.contains(where: { $0.player === player }) { meters.append(Meter(player)); speechLevels.removeAll(); quietFrames = 0 }
    }
    func tap(normalizedX: Double = 0.5) {
        tapTime = time; tapSide = normalizedX < 0.5 ? -1 : 1
        clickEyeHoldUntil = time + 0.55
        nextBlink = clickEyeHoldUntil + Double.random(in: 2.8...6.5)
        fputs("rig: tap spring side=\(tapSide)\n", stderr)
    }
    func step() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0.001, now-previous)); previous = now; time = now-epoch
        if time >= nextBlink { blinkStart = time; nextBlink = time + Double.random(in: 2.8...6.5); blinkCount += 1 }
        let b = time-blinkStart
        if time < clickEyeHoldUntil { eyeState = 2 }
        else if time < clickEyeHoldUntil + 0.09 { eyeState = 1 }
        else { eyeState = b >= 0 && b < 0.26 ? (b < 0.065 || b > 0.18 ? 1 : 2) : 0 }
        meters.removeAll { $0.player == nil }
        audioDB = -160
        for meter in meters {
            guard let p = meter.player, p.isPlaying, p.volume > 0 else { continue }
            p.updateMeters()
            for channel in 0..<p.numberOfChannels { audioDB = max(audioDB, Double(p.averagePower(forChannel: channel))) }
        }
        // Relative envelope follows phonemes even after speech loudness normalization.
        // Calibrate from the current player's upper energy range, not a fixed -46 dB floor.
        if audioDB > -60 { speechLevels.append(audioDB) }
        if speechLevels.count > 45 { speechLevels.removeFirst(speechLevels.count - 45) }
        let sorted = speechLevels.sorted()
        let high = sorted.count >= 5 ? sorted[Int(Double(sorted.count - 1) * 0.85)] : max(-16, audioDB)
        let gate = max(-48, high - 3.5)
        let normalized = max(0, min(1, (audioDB - gate) / 3.5))
        let target = audioDB > gate ? 0.96 * pow(normalized, 1.25) : 0
        quietFrames = target == 0 ? quietFrames + 1 : 0
        mouth += (target-mouth) * (1-exp(-dt/(target > mouth ? 0.028 : 0.035)))
        if quietFrames >= 1 || mouth < 0.035 { mouth = 0 }
        onTelemetry?(time,audioDB,mouth,eyeState); onFrame?()
    }
    func angle(_ layer: Layer, at t: Double? = nil) -> Double {
        guard layer.amplitude > 0 else { return 0 }
        let t = t ?? time
        let idle = layer.amplitude * (0.75*sin(t*1.35+layer.phase)+0.25*sin(t*2.1+layer.phase))
        let elapsed = t-tapTime
        let response = elapsed >= 0 && elapsed < 2 ? 2.1*exp(-elapsed*2.8)*sin(elapsed*12+layer.phase*0.15)*tapSide : 0
        let sideWeight = (layer.pivot[0] < 500 ? -1.0 : 1.0) == tapSide ? 1.0 : 0.4
        let limit = layer.id == "H01" ? 8.0 : 3.0
        return max(-limit,min(limit,idle + response*(layer.id == "H08" ? 0.3 : sideWeight)))
    }
    func draw(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        // Stable visible stage: source x20...1234, y180...1140, independent of pose.
        let s = min(rect.width/1214, rect.height/960)
        ctx.translateBy(x: rect.midX-607*s-20*s, y: rect.minY-114*s)
        ctx.scaleBy(x: s, y: s)
        for layer in model.layers {
            guard layer.enabled, layer.id != "F03", let image = images[layer.id] else { continue }
            if ["E01","E02"].contains(layer.id) && eyeState != 0 { continue }
            if layer.id == "E03" && eyeState != 1 { continue }
            if layer.id == "E04" && eyeState != 2 { continue }
            if layer.id == "M01" && mouth > 0.07 { continue }
            if layer.id == "M02" && mouth <= 0.07 { continue }
            ctx.saveGState()
            let px = layer.pivot[0], py = 1254-layer.pivot[1]
            let rotation = angle(layer) * .pi/180
            ctx.translateBy(x:px,y:py);ctx.rotate(by:rotation);ctx.translateBy(x:-px,y:-py)
            if layer.id == "M02" {
                // Opening is centered on the mouth, never stretches the whole head.
                let y = 1254.0-988.0
                ctx.translateBy(x:487,y:y);ctx.scaleBy(x:1,y:0.12+0.88*mouth);ctx.translateBy(x:-487,y:-y)
            }
            if layer.id == "H08", let original = rearImage, let warp = rearWarp,
               let bent = warp.apply(extent:original.extent, roiCallback:{ _,rect in rect.insetBy(dx:-65,dy:-20) }, image:original, arguments:[time,48.0]),
               let cg = ciContext.createCGImage(bent,from:original.extent) {
                NSImage(cgImage:cg,size:NSSize(width:1254,height:1254)).draw(in:NSRect(x:0,y:0,width:1254,height:1254),from:.zero,operation:.sourceOver,fraction:1)
            } else {
                image.draw(in:NSRect(x:0,y:0,width:1254,height:1254),from:.zero,operation:.sourceOver,fraction:1)
            }
            ctx.restoreGState()
        }
    }
}
