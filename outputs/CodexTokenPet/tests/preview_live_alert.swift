import Foundation

guard CommandLine.arguments.count == 2, ["complete", "problem"].contains(CommandLine.arguments[1]) else {
    fputs("usage: swift preview_live_alert.swift complete|problem\n", stderr)
    exit(2)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("local.qianlve.codex-token-pet.preview-task-alert"),
    object: nil,
    userInfo: ["kind": CommandLine.arguments[1]],
    deliverImmediately: true
)
