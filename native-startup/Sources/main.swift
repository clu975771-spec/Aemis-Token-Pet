import AppKit
import AVFoundation
import QuartzCore

let targetID = "com.openai.codex"
let helperID = "local.qianlve.aemeath-startup"
let requestName = Notification.Name("local.qianlve.aemeath-startup.play")
let phaseName = Notification.Name("local.qianlve.aemeath-startup.phase")
let watchMode = CommandLine.arguments.contains("--watch")
let previewOnly = CommandLine.arguments.contains("--preview")
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AemeathStartup/events.log")
func log(_ text: String) {
    try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let line = "\(ISO8601DateFormatter().string(from: Date())) [\(ProcessInfo.processInfo.processIdentifier)] \(text)\n"
    if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
    if let h = try? FileHandle(forWritingTo: logURL) { defer { try? h.close() }; try? h.seekToEnd(); try? h.write(contentsOf: Data(line.utf8)) }
    print(text)
}
final class SplashWindow: NSWindow {
    var onSkip: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 || event.keyCode == 49 { onSkip?() } else { super.keyDown(with: event) } }
}
final class MovieView: NSView {
    let movie = AVPlayerLayer()
    let hero = CALayer()
    let dim = CALayer()
    override init(frame: NSRect) { super.init(frame:frame); wantsLayer = true; layer?.backgroundColor = NSColor(calibratedRed:0.03,green:0.027,blue:0.055,alpha:1).cgColor; layer?.cornerRadius = 15; layer?.masksToBounds = true; movie.videoGravity = .resizeAspectFill; layer?.addSublayer(movie)
        hero.contentsGravity = .resizeAspectFill;hero.masksToBounds=true;hero.opacity=0
        if let url=Bundle.main.url(forResource:"wallpaper",withExtension:"png"),let image=NSImage(contentsOf:url) {hero.contents=image.cgImage(forProposedRect:nil,context:nil,hints:nil)}
        layer?.addSublayer(hero);dim.backgroundColor=NSColor(calibratedRed:24/255,green:24/255,blue:24/255,alpha:1).cgColor;dim.opacity=0;layer?.addSublayer(dim) }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); movie.frame = bounds;hero.frame=bounds;dim.frame=bounds; CATransaction.commit() }
}
final class AppDelegate: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate {
    var window: SplashWindow?
    var player: AVPlayer?
    var readyObservation: NSKeyValueObservation?
    var timeToken: Any?
    var watchdog: Timer?
    var observers: [NSObjectProtocol] = []
    var lastShow = Date.distantPast
    var closing = false
    var targetApp: NSRunningApplication?
    var didLogFrame = false
    var didLogMiddle = false
    var didLogColor = false
    var followTimer: Timer?
    var voice: AVAudioPlayer?
    var didPlayVoice=false
    var movieView: MovieView?
    var integratedTimer: Timer?
    var integratedToken: String?
    var integratedStartedAt = Date.distantPast
    var integratedCompletionTimer: Timer?
    var nativeToken: String?
    var nativeSource = "direct"
    var nativeVisiblePosted = false
    var urlLaunchReceived = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--self-check") {
            let media = Bundle.main.url(forResource:"startup",withExtension:"mp4")
            log("self-check target=\(resolveTarget()?.path ?? "missing") media=\(media?.path ?? "missing")")
            NSApp.terminate(nil); return
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName:requestName,object:nil,queue:.main) { [weak self] _ in self?.show(launch:true, reason:"launcher-request") })
        if watchMode {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didLaunchApplicationNotification,object:nil,queue:.main) { [weak self] note in
                guard let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, running.bundleIdentifier == targetID else { return }
                self?.targetApp = running
                self?.show(launch:false, reason:"codex-did-launch")
            })
            log("watcher-ready target=\(targetID)")
        } else {
            let other = NSRunningApplication.runningApplications(withBundleIdentifier:helperID).first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if other != nil && !previewOnly {
                DistributedNotificationCenter.default().postNotificationName(requestName,object:nil,userInfo:nil,deliverImmediately:true)
                log("forwarded-to-watcher"); NSApp.terminate(nil)
            } else {
                // A URL launch arrives just after applicationDidFinishLaunching.
                // Give it precedence so a refresh does not also play the plain launcher.
                DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [weak self] in
                    guard let self, !self.urlLaunchReceived else { return }
                    self.show(launch:!previewOnly, reason:previewOnly ? "preview" : "launcher")
                }
            }
        }
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        for url in urls where url.scheme == "codex-aemeath" && url.host == "launch" {
            urlLaunchReceived = true
            let items=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
            let source=items.first(where:{$0.name=="source"})?.value
            let refresh=items.first(where:{$0.name=="refresh"})?.value == "1"
            log("launch-url-received source=\(source ?? "direct") refresh=\(refresh)")
            let reason=source == "pet" ? "url-interface-pet" : "url-interface"
            if refresh { refreshAndShow(reason:reason) }
            else { show(launch:true,reason:reason) }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.0) { [weak self] in self?.urlLaunchReceived = false }
        }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        if !urlLaunchReceived { show(launch:true,reason:"finder-reopen") }
        return true
    }
    func resolveTarget() -> URL? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier:targetID).first, let url = running.bundleURL { return url }
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/ChatGPT.app")
        if Bundle(url:fallback)?.bundleIdentifier == targetID { return fallback }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier:targetID)
    }
    func targetFrame() -> NSRect? {
        guard let app = targetApp ?? NSRunningApplication.runningApplications(withBundleIdentifier:targetID).first else {return nil}
        guard let list=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else {return nil}
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let raw=info[kCGWindowBounds as String] as? [String:CGFloat],
                  let x=raw["X"],let y=raw["Y"],let w=raw["Width"],let h=raw["Height"],w>500,h>350 else {continue}
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let frame=NSRect(x:x,y:top-y-h,width:w,height:h)
            UserDefaults.standard.set(NSStringFromRect(frame),forKey:"lastCodexWindowFrame")
            return frame
        }
        return nil
    }
    func fitFrame() -> NSRect {
        let saved=UserDefaults.standard.string(forKey:"lastCodexWindowFrame").map(NSRectFromString)
        let validSaved=saved.flatMap { frame in NSScreen.screens.contains(where:{$0.frame.intersects(frame)}) && frame.width>500 && frame.height>350 ? frame : nil }
        let area = targetFrame() ?? validSaved ?? NSScreen.main?.visibleFrame ?? NSRect(x:100,y:100,width:1200,height:800)
        // Match the application's window bounds while keeping the animation undistorted.
        return area
    }
    func debugInterfaceAvailable() -> Bool {
        guard let url=URL(string:"http://127.0.0.1:19327/json/version") else{return false}
        let semaphore=DispatchSemaphore(value:0);var available=false
        let task=URLSession.shared.dataTask(with:url) { data,response,_ in
            available = data != nil && (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }
        task.resume();_ = semaphore.wait(timeout:.now()+0.35);task.cancel();return available
    }
    func refreshAndShow(reason:String) {
        let refreshReason=reason + "-refresh"
        guard let running=NSRunningApplication.runningApplications(withBundleIdentifier:targetID).first else {
            show(launch:true,reason:refreshReason);return
        }
        if debugInterfaceAvailable() {
            show(launch:true,reason:refreshReason);return
        }
        // Electron only accepts the debug port at process start. A renderer
        // reload cannot attach the skin to an instance launched without it.
        log("refresh-relaunch-requested pid=\(running.processIdentifier)")
        _=running.terminate()
        let deadline=Date().addingTimeInterval(12)
        func waitForExit() {
            if NSRunningApplication.runningApplications(withBundleIdentifier:targetID).isEmpty {
                log("refresh-relaunch-exited")
                self.show(launch:true,reason:refreshReason + "-restarted")
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:waitForExit)
            } else {
                log("refresh-relaunch-timeout")
                self.postStartupPhase(token:UUID().uuidString,phase:"failed",source:reason.contains("pet") ? "pet" : "direct")
            }
        }
        waitForExit()
    }
    func show(launch:Bool,reason:String) {
        if launch && (integratedToken != nil || nativeToken != nil) {log("duplicate-startup-session-ignored");return}
        guard window == nil, Date().timeIntervalSince(lastShow)>2 else {log("duplicate-show-ignored");return}
        if launch && !previewOnly {
            let running=NSRunningApplication.runningApplications(withBundleIdentifier:targetID).first
            targetApp=running
            let visibleFrame=targetFrame()
            if running != nil && visibleFrame != nil && debugInterfaceAvailable() {
                lastShow=Date();log("startup-route integrated-warm")
                beginIntegratedLaunch(reason:reason)
                return
            }
            nativeToken=UUID().uuidString;nativeSource=reason.contains("pet") ? "pet" : "direct";nativeVisiblePosted=false
            postStartupPhase(token:nativeToken!,phase:"requested",source:nativeSource)
            log("startup-route native-overlay running=\(running != nil) visibleWindow=\(visibleFrame != nil) debug=unavailable-or-cold")
        }
        guard let url=Bundle.main.url(forResource:"startup",withExtension:"mp4") else {log("error: missing movie");if !watchMode {NSApp.terminate(nil)};return}
        lastShow=Date(); closing=false; didLogFrame=false;didLogMiddle=false;didLogColor=false
        didPlayVoice=false
        targetApp=NSRunningApplication.runningApplications(withBundleIdentifier:targetID).first
        let rect=fitFrame()
        let w=SplashWindow(contentRect:rect,styleMask:[.borderless],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false;w.backgroundColor = .clear;w.isOpaque=false;w.hasShadow=true
        // Stay above the Codex document window, while leaving the dedicated
        // always-on-top pet at its higher floating level fully visible.
        w.level = NSWindow.Level(rawValue:NSWindow.Level.normal.rawValue + 1)
        w.collectionBehavior=[.moveToActiveSpace,.fullScreenAuxiliary];w.isMovableByWindowBackground=false
        w.onSkip = { [weak self] in self?.finish(reason:"skipped") }
        let view=MovieView(frame:NSRect(origin:.zero,size:rect.size));w.contentView=view;movieView=view
        let skip=NSButton(title:"跳过  Esc",target:self,action:#selector(skipClicked));skip.bezelStyle = .inline;skip.isBordered=false;skip.contentTintColor=NSColor(calibratedWhite:0.85,alpha:0.65);skip.font=NSFont.systemFont(ofSize:11);skip.frame=NSRect(x:rect.width-110,y:18,width:90,height:26);skip.autoresizingMask=[.minXMargin,.maxYMargin];view.addSubview(skip)
        let item=AVPlayerItem(url:url);let p=AVPlayer(playerItem:item);p.volume=0.16;p.actionAtItemEnd = .pause
        player=p;view.movie.player=p;window=w
        if let voiceURL=Bundle.main.url(forResource:"startup-voice",withExtension:"wav") {voice=try? AVAudioPlayer(contentsOf:voiceURL);voice?.delegate=self;voice?.volume=0.85;voice?.prepareToPlay()}
        log("show reason=\(reason) bounds=\(NSStringFromRect(rect))")
        readyObservation=view.movie.observe(\.isReadyForDisplay,options:[.new]) { [weak self] layer,_ in
            guard layer.isReadyForDisplay else{return}
            DispatchQueue.main.async { self?.logFirstFrame() }
        }
        timeToken=p.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.1,preferredTimescale:600),queue:.main) { [weak self] time in
            guard let self=self else{return};let t=time.seconds
            if t>5.1 && !self.didLogMiddle {self.didLogMiddle=true;log("playback-lines t=\(t)")}
            if t>7.4 && !self.didLogColor {self.didLogColor=true;log("playback-color t=\(t)")}
            if t>=0.95 && !self.didPlayVoice {self.didPlayVoice=true;self.voice?.play();log("cached-voice-played t=\(t)")}
            let heroProgress=min(1,max(0,(t-7.65)/0.55))
            let darkProgress=min(1,max(0,(t-8.35)/1.3))
            CATransaction.begin();CATransaction.setDisableActions(true)
            self.movieView?.hero.opacity=Float(heroProgress*heroProgress*(3-2*heroProgress))
            self.movieView?.dim.opacity=Float(0.68*darkProgress*darkProgress*(3-2*darkProgress))
            CATransaction.commit()
            if t>=9.9 {self.finish(reason:"completed")}
        }
        observers.append(NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main) { [weak self] _ in self?.finish(reason:"completed-end") })
        w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);p.play()
        if launch {
            guard let target=resolveTarget() else {log("error: Codex not found");finish(reason:"target-missing");return}
            let config=NSWorkspace.OpenConfiguration();config.activates=false
            config.arguments=["--remote-debugging-address=127.0.0.1", "--remote-debugging-port=19327"]
            startWallpaperBridge()
            NSWorkspace.shared.openApplication(at:target,configuration:config) { [weak self] app,error in
                DispatchQueue.main.async {
                    self?.targetApp=app
                    if let error {log("codex-open-error \(error)");self?.finish(reason:"target-open-error")}
                    else {log("codex-open-success pid=\(app?.processIdentifier ?? -1) native=true")}
                }
            }
        }
        followTimer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in
            guard let self=self,let w=self.window,!self.closing, let frame=self.targetFrame() else{return}
            if !NSEqualRects(w.frame,frame) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration=0.22;context.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
                    w.animator().setFrame(frame,display:true)
                }
            }
        }
        watchdog=Timer.scheduledTimer(withTimeInterval:14,repeats:false) { [weak self] _ in self?.finish(reason:"watchdog") }
    }
    func beginIntegratedLaunch(reason:String) {
        guard integratedTimer == nil else { log("duplicate-integrated-launch-ignored"); return }
        guard let target=resolveTarget() else {log("error: Codex not found");if !watchMode {NSApp.terminate(nil)};return}
        let coldStart=NSRunningApplication.runningApplications(withBundleIdentifier:targetID).isEmpty
        let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AemeathStartup")
        let requestURL=folder.appendingPathComponent("play-startup.request.json")
        let ackURL=folder.appendingPathComponent("play-startup.ack.json")
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try? FileManager.default.removeItem(at:ackURL)
        let token=UUID().uuidString
        let config=NSWorkspace.OpenConfiguration();config.activates=false
        config.arguments=["--remote-debugging-address=127.0.0.1", "--remote-debugging-port=19327"]
        NSWorkspace.shared.openApplication(at:target,configuration:config) { [weak self] app,error in
            DispatchQueue.main.async {
                self?.targetApp=app
                log(error == nil ? "codex-open-success pid=\(app?.processIdentifier ?? -1) integrated=true" : "codex-open-error \(error!)")
                guard error == nil else { if !watchMode { NSApp.terminate(nil) }; return }
                // Opening an already-running Electron app can still update its route.
                // Arm the in-page animation after that event so React cannot replace it.
                DispatchQueue.main.asyncAfter(deadline:.now()+0.4) {
                    self?.armIntegratedRequest(token:token,reason:reason,coldStart:coldStart,requestURL:requestURL,ackURL:ackURL)
                }
            }
        }
    }
    func armIntegratedRequest(token:String,reason:String,coldStart:Bool,requestURL:URL,ackURL:URL) {
        let source=reason.contains("pet") ? "pet" : "direct"
        let readinessTimeout=coldStart ? 35.0 : 12.0
        let request:[String:Any] = ["token":token,"createdAt":Date().timeIntervalSince1970,"reason":reason,"coldStart":coldStart,"refresh":reason.contains("-refresh") && !reason.contains("-restarted")]
        guard let data=try? JSONSerialization.data(withJSONObject:request), (try? data.write(to:requestURL,options:.atomic)) != nil else {
            log("error: could not create integrated startup request")
            postStartupPhase(token:token,phase:"failed",source:source)
            if !watchMode {NSApp.terminate(nil)}
            return
        }
        integratedToken=token;integratedStartedAt=Date()
        postStartupPhase(token:token,phase:"requested",source:source)
        startWallpaperBridge()
        integratedTimer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] timer in
            guard let self=self else {timer.invalidate();return}
            if let ackData=try? Data(contentsOf:ackURL),
               let ack=try? JSONSerialization.jsonObject(with:ackData) as? [String:Any],
               ack["token"] as? String == token {
                timer.invalidate();self.integratedTimer=nil
                self.targetApp = self.targetApp ?? NSRunningApplication.runningApplications(withBundleIdentifier:targetID).first
                self.targetApp?.activate(options:[.activateIgnoringOtherApps])
                log("integrated-startup-visible token=\(token)")
                self.postStartupPhase(token:token,phase:"visible",source:source)
                self.integratedCompletionTimer?.invalidate()
                // The in-page bridge starts its 1.05 s fade at 9.9 s. Keep the
                // pet's ordinary click voice suppressed until the overlay and
                // cached startup voice have both fully yielded to Codex.
                self.integratedCompletionTimer=Timer.scheduledTimer(withTimeInterval:11.1,repeats:false) { [weak self] _ in
                    guard let self=self,self.integratedToken==token else{return}
                    self.postStartupPhase(token:token,phase:"completed",source:source)
                    self.integratedToken=nil;self.integratedCompletionTimer=nil
                    log("integrated-startup-completed token=\(token)")
                    if !watchMode {NSApp.terminate(nil)}
                }
                return
            }
            if Date().timeIntervalSince(self.integratedStartedAt)>readinessTimeout {
                timer.invalidate();self.integratedTimer=nil
                self.targetApp = self.targetApp ?? NSRunningApplication.runningApplications(withBundleIdentifier:targetID).first
                self.targetApp?.activate(options:[.activateIgnoringOtherApps])
                log("integrated-startup-timeout; Codex activated without window swap")
                self.postStartupPhase(token:token,phase:"failed",source:source)
                self.integratedToken=nil
                if !watchMode {NSApp.terminate(nil)}
            }
        }
        log("integrated-startup-requested reason=\(reason) coldStart=\(coldStart) token=\(token)")
    }
    func postStartupPhase(token:String,phase:String,source:String) {
        let timestamp=Date().timeIntervalSince1970
        let event:[String:Any] = ["token":token,"phase":phase,"source":source,"timestamp":timestamp]
        let stateURL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AemeathStartup/startup-phase.json")
        var events:[[String:Any]]=[]
        if let previousData=try? Data(contentsOf:stateURL),
           let previous=try? JSONSerialization.jsonObject(with:previousData) as? [String:Any],
           previous["token"] as? String == token {
            events=previous["events"] as? [[String:Any]] ?? []
        }
        if !(events.contains { ($0["phase"] as? String) == phase }) {events.append(event)}
        let snapshot:[String:Any] = ["token":token,"phase":phase,"source":source,"timestamp":timestamp,"events":events]
        if let data=try? JSONSerialization.data(withJSONObject:snapshot) {try? data.write(to:stateURL,options:.atomic)}
        DistributedNotificationCenter.default().postNotificationName(phaseName,object:helperID,userInfo:event,deliverImmediately:true)
        log("startup-phase phase=\(phase) source=\(source) token=\(token)")
    }
    func startWallpaperBridge() {
        guard !previewOnly, let script=Bundle.main.url(forResource:"wallpaper-bridge",withExtension:"mjs") else {return}
        let task=Process()
        task.executableURL=Bundle.main.url(forResource:"node",withExtension:nil)
        task.arguments=[script.path]
        task.standardOutput=FileHandle.nullDevice;task.standardError=FileHandle.nullDevice
        do {try task.run();log("wallpaper-bridge-started")} catch {log("wallpaper-bridge-error \(error)")}
    }
    func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool) {log("cached-voice-finished success=\(flag)")}
    func logFirstFrame() {
        if !didLogFrame {
            didLogFrame=true;log("first-frame-ready")
            if let token=nativeToken,!nativeVisiblePosted {
                nativeVisiblePosted=true;postStartupPhase(token:token,phase:"visible",source:nativeSource)
            }
        }
    }
    @objc func skipClicked() {finish(reason:"skipped")}
    func finish(reason:String) {
        guard let w=window,!closing else{return};closing=true;watchdog?.invalidate();followTimer?.invalidate()
        let finishingNativeToken=nativeToken
        let finishingNativeSource=nativeSource
        let nativeFailed=reason=="watchdog" || reason.contains("target") || reason.contains("error")
        if !previewOnly {targetApp?.activate(options:[.activateIgnoringOtherApps])}
        NSAnimationContext.runAnimationGroup({ctx in ctx.duration=1.05;ctx.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut);w.animator().alphaValue=0},completionHandler:{ [weak self] in
            guard let self=self else{return}
            self.player?.pause();if let token=self.timeToken {self.player?.removeTimeObserver(token)};self.timeToken=nil;self.readyObservation=nil
            w.orderOut(nil);w.close();self.window=nil;self.player=nil;self.movieView=nil;self.voice?.stop();self.voice=nil
            if let token=finishingNativeToken {
                self.postStartupPhase(token:token,phase:nativeFailed ? "failed" : "completed",source:finishingNativeSource)
                self.nativeToken=nil;self.nativeVisiblePosted=false
            }
            log("dismissed reason=\(reason) firstFrame=\(self.didLogFrame) lines=\(self.didLogMiddle) color=\(self.didLogColor)")
            if !watchMode {NSApp.terminate(nil)}
        })
    }
}
let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
app.run()
