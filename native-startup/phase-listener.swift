import AppKit

final class PhaseObserver: NSObject {
    var seen: [String] = []
    @objc func receive(_ note: Notification) {
        guard let info = note.userInfo,
              info["source"] as? String == "pet",
              let phase = info["phase"] as? String else { return }
        seen.append(phase)
        print("phase=\(phase) token=\(info["token"] as? String ?? "missing")")
        fflush(stdout)
        if phase == "completed" || phase == "failed" { exit(phase == "completed" ? 0 : 1) }
    }
}

let observer = PhaseObserver()
DistributedNotificationCenter.default().addObserver(
    observer,
    selector:#selector(PhaseObserver.receive(_:)),
    name:Notification.Name("local.qianlve.aemeath-startup.phase"),
    object:nil,
    suspensionBehavior:.deliverImmediately
)
DispatchQueue.main.asyncAfter(deadline:.now()+15) {
    print("timeout phases=\(observer.seen.joined(separator:","))")
    fflush(stdout)
    exit(2)
}
RunLoop.main.run()
