import UserNotifications

@MainActor
enum TaskNotificationManager {
  static func requestAuthorization() {
    Task {
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
  }

  static func notifyDownloadCompleted(_ task: Aria2Task) {
    let content = UNMutableNotificationContent()
    content.title = "下载完成"
    content.body = task.isSeeding ? "\(task.name) 已下载完成，正在做种" : task.name
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "motrix-native-complete-\(task.id)",
      content: content,
      trigger: nil
    )

    Task {
      try? await UNUserNotificationCenter.current().add(request)
    }
  }
}
