import AppKit

@MainActor
enum TaskRemovalConfirmation {
  static func confirm(_ task: Aria2Task) -> Bool {
    let alert = NSAlert()
    alert.messageText = "移除“\(task.name)”？"
    alert.informativeText = "任务会从 Motrix Native 中移除，已经下载的文件不会被删除。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "移除")
    alert.addButton(withTitle: "取消")
    alert.buttons.first?.hasDestructiveAction = true
    return alert.runModal() == .alertFirstButtonReturn
  }
}
