import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private var controller: StatusController?
  private var terminationInProgress = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    let config = MotrixConfig.load()
    try? LoginItemManager.apply(config.openAtLoginEnabled)
    if config.taskNotificationsEnabled {
      TaskNotificationManager.requestAuthorization()
    }
    UNUserNotificationCenter.current().delegate = self

    let engine = Aria2Engine(config: config)
    let client = Aria2RPCClient(config: config)
    controller = StatusController(config: config, engine: engine, client: client)
    controller?.start()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationInProgress, let controller else {
      return .terminateNow
    }

    terminationInProgress = true
    Task {
      await controller.stop()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    controller?.showMainWindow()
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
