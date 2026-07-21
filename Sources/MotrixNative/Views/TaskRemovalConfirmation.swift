import AppKit

@MainActor
enum TaskRemovalConfirmation {
  static func confirm(_ task: Aria2Task) -> Bool {
    confirm([task], deletingFiles: false)
  }

  static func confirm(_ tasks: [Aria2Task], deletingFiles: Bool) -> Bool {
    let alert = NSAlert()
    if tasks.count == 1, let task = tasks.first {
      alert.messageText = deletingFiles ? "移除“\(task.name)”并删除文件？" : "移除“\(task.name)”？"
    } else {
      alert.messageText = deletingFiles ? "移除 \(tasks.count) 个任务并删除文件？" : "移除 \(tasks.count) 个任务？"
    }
    alert.informativeText = deletingFiles
      ? "任务会从 Motrix Native 中移除，已下载和未完成的文件会移到废纸篓。"
      : "任务会从 Motrix Native 中移除，已经下载的文件不会被删除。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: deletingFiles ? "移除并放入废纸篓" : "移除")
    alert.addButton(withTitle: "取消")
    alert.buttons.first?.hasDestructiveAction = true
    return alert.runModal() == .alertFirstButtonReturn
  }

  static func confirmClearingCompleted(count: Int) -> Bool {
    let alert = NSAlert()
    alert.messageText = "清理 \(count) 个已完成任务？"
    alert.informativeText = "只会清理任务记录，不会删除已经下载的文件。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "清理")
    alert.addButton(withTitle: "取消")
    return alert.runModal() == .alertFirstButtonReturn
  }
}
