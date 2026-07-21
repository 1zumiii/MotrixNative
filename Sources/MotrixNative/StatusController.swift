import AppKit

@MainActor
final class StatusController: NSObject, NSMenuDelegate {
  private var config: MotrixConfig
  private let engine: Aria2Engine
  private let client: Aria2RPCClient
  private let adaptiveController: AdaptiveConnectionController
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()

  private var timer: Timer?
  private var tasks: [Aria2Task] = []
  private var globalStat = Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 0)
  private var lastError: String?
  private var progressSummary: ProgressSummary?
  private var hasEstablishedTaskBaseline = false
  private var knownCompletedTaskIDs = Set<String>()
  private var unreadCompletedTaskIDs = Set<String>()
  private var hasCreatedMainWindow = false
  private lazy var mainWindowController = MainWindowController(config: config, client: client)

  init(config: MotrixConfig, engine: Aria2Engine, client: Aria2RPCClient) {
    self.config = config
    self.engine = engine
    self.client = client
    self.adaptiveController = AdaptiveConnectionController(config: config, client: client)
    super.init()
  }

  func start() {
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.imageScaling = .scaleNone
    menu.delegate = self
    statusItem.menu = menu

    Task {
      await engine.ensureRunning(client: client)
      await refresh()
    }

    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.refresh()
      }
    }

    renderMenu()
  }

  func stop() async {
    timer?.invalidate()
    await engine.stopGracefully(client: client)
  }

  func showMainWindow() {
    markCompletedTasksRead()
    hasCreatedMainWindow = true
    mainWindowController.showWindow(nil)
  }

  func menuWillOpen(_ menu: NSMenu) {
    markCompletedTasksRead()
  }

  private func refresh() async {
    do {
      let globalStat = try await client.getGlobalStat()
      let tasks = try await client.listTasks()
      CompletedControlFileCleaner.clean(tasks: tasks)
      let newlyCompletedIDs = updateCompletionState(with: tasks)
      if !newlyCompletedIDs.isEmpty, MotrixConfig.load().taskNotificationsEnabled {
        for task in tasks where newlyCompletedIDs.contains(task.id) {
          TaskNotificationManager.notifyDownloadCompleted(task)
        }
      }
      if hasCreatedMainWindow, mainWindowController.window?.isVisible == true {
        markCompletedTasksRead()
      }
      self.globalStat = globalStat.usingActiveTaskSpeeds(tasks)
      self.tasks = tasks
      self.progressSummary = makeProgressSummary(tasks)
      self.lastError = nil
      await adaptiveController.observe(tasks)
      renderMenu()
    } catch {
      self.lastError = String(describing: error)
      self.globalStat = Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 0)
      self.progressSummary = nil
      await engine.ensureRunning(client: client)
      renderMenu()
    }
  }

  private func renderMenu() {
    renderStatusItem()

    menu.removeAllItems()
    menu.addItem(headerItem())
    menu.addItem(NSMenuItem.separator())

    if let lastError {
      menu.addItem(menuItem(title: "重新连接下载引擎", systemImage: "arrow.clockwise", action: #selector(retry), keyEquivalent: "r"))
      let errorItem = NSMenuItem(title: lastError, action: nil, keyEquivalent: "")
      errorItem.isEnabled = false
      menu.addItem(errorItem)
    } else if tasks.isEmpty {
      let empty = menuItem(title: "暂无下载任务", systemImage: "tray", action: nil)
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      menu.addItem(sectionHeader("最近任务"))
      for task in tasks.prefix(6) {
        menu.addItem(taskMenuItem(task))
      }
    }

    menu.addItem(NSMenuItem.separator())
    menu.addItem(sectionHeader("快捷操作"))
    menu.addItem(menuItem(title: "打开 Motrix Native", systemImage: "macwindow", action: #selector(openMainWindow), keyEquivalent: "m"))
    menu.addItem(menuItem(title: "新建下载...", systemImage: "plus.circle", action: #selector(openAddTask), keyEquivalent: "n"))
    menu.addItem(menuItem(title: "打开下载目录", systemImage: "folder", action: #selector(openDownloadDirectory), keyEquivalent: "o"))
    menu.addItem(menuItem(title: "偏好设置...", systemImage: "gearshape", action: #selector(openPreferences), keyEquivalent: ","))
    menu.addItem(engineMenuItem())
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "退出 Motrix Native", action: #selector(quit), keyEquivalent: "q", target: self))
  }

  private func headerItem() -> NSMenuItem {
    let downloading = tasks.filter { $0.status == "active" && !$0.isSeeding }
    let seeding = tasks.filter(\.isSeeding)
    let state: String
    let detail: String
    let progress: Double?

    if lastError != nil {
      state = "下载引擎未连接"
      detail = "可以从下方重新连接或查看诊断信息"
      progress = nil
    } else if !downloading.isEmpty {
      state = "正在下载 \(downloading.count) 个任务"
      let percent = progressSummary?.percent ?? 0
      detail = "\(Formatting.speed(globalStat.downloadSpeed))  ·  整体进度 \(percent)%"
      progress = progressSummary?.progress
    } else if !seeding.isEmpty {
      state = "正在做种 \(seeding.count) 个任务"
      detail = "上传 \(Formatting.speed(globalStat.uploadSpeed))"
      progress = nil
    } else if globalStat.waiting > 0 {
      state = "有 \(globalStat.waiting) 个任务等待中"
      detail = "打开主窗口可以调整任务顺序和状态"
      progress = nil
    } else {
      let completed = tasks.filter { $0.status == "complete" }.count
      state = engine.statusText == "RPC 已连接" ? "下载引擎已连接" : engine.statusText
      detail = completed > 0 ? "最近有 \(completed) 个已完成任务" : "暂无进行中的任务"
      progress = nil
    }

    let item = NSMenuItem()
    item.view = StatusMenuHeaderView(
      state: state,
      detail: detail,
      progress: progress,
      isError: lastError != nil
    )
    return item
  }

  private func sectionHeader(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.tertiaryLabelColor
      ]
    )
    item.isEnabled = false
    return item
  }

  private func menuItem(
    title: String,
    systemImage: String,
    action: Selector?,
    keyEquivalent: String = "",
    representedObject: Any? = nil
  ) -> NSMenuItem {
    let item = NSMenuItem(
      title: title,
      action: action,
      keyEquivalent: keyEquivalent,
      target: action == nil ? nil : self,
      representedObject: representedObject
    )
    if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
      image.isTemplate = true
      item.image = image
    }
    return item
  }

  private func taskImageName(_ task: Aria2Task) -> String {
    if task.isSeeding {
      return "arrow.up.circle.fill"
    } else {
      switch task.status {
      case "active": return "arrow.down.circle.fill"
      case "waiting": return "clock"
      case "paused": return "pause.circle.fill"
      case "complete": return "checkmark.circle.fill"
      case "error": return "exclamationmark.circle.fill"
      default: return "circle"
      }
    }
  }

  private func renderStatusItem() {
    if lastError != nil {
      statusItem.button?.image = StatusProgressIcon.renderError()
      statusItem.button?.title = ""
    } else if !unreadCompletedTaskIDs.isEmpty {
      statusItem.button?.image = StatusProgressIcon.renderCompletion()
      statusItem.button?.title = unreadCompletedTaskIDs.count > 1 ? "\(unreadCompletedTaskIDs.count)" : ""
    } else {
      let activeSummary = progressSummary?.hasIncompleteTasks == true ? progressSummary : nil
      statusItem.button?.image = StatusProgressIcon.render(activeSummary)
      statusItem.button?.title = activeSummary?.statusTitle ?? ""
    }
    statusItem.button?.toolTip = statusTooltip()
  }

  private func statusTooltip() -> String {
    if let lastError {
      return "Motrix Native: RPC 未连接\n\(lastError)"
    }

    if !unreadCompletedTaskIDs.isEmpty {
      return "Motrix Native: \(unreadCompletedTaskIDs.count) 个任务下载完成"
    }

    if let progressSummary, progressSummary.hasIncompleteTasks {
      return "Motrix Native: \(progressSummary.taskCount) 个任务，整体进度 \(progressSummary.percent)%"
    }

    return "Motrix Native"
  }

  private func updateCompletionState(with tasks: [Aria2Task]) -> Set<String> {
    let completedIDs = Set(tasks.lazy.filter {
      $0.totalLength > 0 &&
        $0.completedLength >= $0.totalLength &&
        $0.status != "error" &&
        $0.status != "removed"
    }.map(\.id))
    guard hasEstablishedTaskBaseline else {
      knownCompletedTaskIDs = completedIDs
      hasEstablishedTaskBaseline = true
      return []
    }

    let newlyCompletedIDs = completedIDs.subtracting(knownCompletedTaskIDs)
    unreadCompletedTaskIDs.formUnion(newlyCompletedIDs)
    knownCompletedTaskIDs.formUnion(completedIDs)
    return newlyCompletedIDs
  }

  private func markCompletedTasksRead() {
    guard !unreadCompletedTaskIDs.isEmpty else {
      return
    }
    unreadCompletedTaskIDs.removeAll()
    renderStatusItem()
  }

  private func engineStatusItem() -> NSMenuItem {
    let error = engine.lastError.map { " (\($0))" } ?? ""
    let item = NSMenuItem(title: "引擎 \(engine.statusText)\(error)", action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func engineMenuItem() -> NSMenuItem {
    let item = menuItem(title: "引擎与诊断", systemImage: "bolt.horizontal.circle", action: nil)
    let submenu = NSMenu()
    submenu.addItem(engineStatusItem())
    let adaptiveItem = NSMenuItem(title: "智能并发 \(adaptiveController.statusText)", action: nil, keyEquivalent: "")
    adaptiveItem.isEnabled = false
    submenu.addItem(adaptiveItem)
    submenu.addItem(NSMenuItem.separator())
    submenu.addItem(NSMenuItem(title: "刷新状态", action: #selector(refreshNow), keyEquivalent: "r", target: self))
    submenu.addItem(NSMenuItem(title: "重启下载引擎", action: #selector(restartEngine), keyEquivalent: "", target: self))
    submenu.addItem(NSMenuItem(title: "引擎信息", action: #selector(showEngineInfo), keyEquivalent: "i", target: self))
    submenu.addItem(NSMenuItem.separator())
    submenu.addItem(NSMenuItem(title: "打开配置目录", action: #selector(openConfigDirectory), keyEquivalent: "", target: self))
    submenu.addItem(NSMenuItem(title: "打开 aria2 日志", action: #selector(openAria2Log), keyEquivalent: "", target: self))
    item.submenu = submenu
    return item
  }

  private func makeProgressSummary(_ tasks: [Aria2Task]) -> ProgressSummary? {
    let incomplete = tasks.filter { task in
      task.status == "active" || task.status == "waiting" || task.status == "paused"
    }

    if incomplete.isEmpty {
      let hasCompleted = tasks.contains { $0.status == "complete" }
      return hasCompleted
        ? ProgressSummary(progress: 1, taskCount: 0, hasIncompleteTasks: false)
        : nil
    }

    let knownSizeTasks = incomplete.filter { $0.totalLength > 0 }
    guard !knownSizeTasks.isEmpty else {
      return ProgressSummary(progress: 0, taskCount: incomplete.count, hasIncompleteTasks: true)
    }

    let completed = knownSizeTasks.reduce(Int64(0)) { $0 + $1.completedLength }
    let total = knownSizeTasks.reduce(Int64(0)) { $0 + $1.totalLength }
    let progress = total > 0 ? Double(completed) / Double(total) : 0
    return ProgressSummary(progress: progress, taskCount: incomplete.count, hasIncompleteTasks: true)
  }

  private func taskMenuItem(_ task: Aria2Task) -> NSMenuItem {
    let item = menuItem(title: taskTitle(task), systemImage: taskImageName(task), action: nil)
    let submenu = NSMenu()

    submenu.addItem(NSMenuItem(title: "查看任务详情", action: #selector(openTaskDetails(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    submenu.addItem(NSMenuItem.separator())
    let detail = NSMenuItem(title: taskDetail(task), action: nil, keyEquivalent: "")
    detail.isEnabled = false
    submenu.addItem(detail)
    submenu.addItem(NSMenuItem.separator())

    if task.status == "active" {
      submenu.addItem(NSMenuItem(title: "暂停", action: #selector(pauseTask(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    } else if task.status == "paused" || task.status == "waiting" {
      submenu.addItem(NSMenuItem(title: "继续", action: #selector(resumeTask(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    }

    if task.primaryFileURL != nil {
      submenu.addItem(NSMenuItem(title: "打开文件", action: #selector(openTaskFile(_:)), keyEquivalent: "", target: self, representedObject: task.id))
      submenu.addItem(NSMenuItem(title: "显示文件位置", action: #selector(revealTaskFile(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    }

    submenu.addItem(NSMenuItem(title: "移除", action: #selector(removeTask(_:)), keyEquivalent: "", target: self, representedObject: task.id))
    item.submenu = submenu
    return item
  }

  private func taskTitle(_ task: Aria2Task) -> String {
    let percent = Int(task.progress * 100)
    let name = task.name.count > 38 ? String(task.name.prefix(37)) + "…" : task.name
    return "\(name)   \(percent)% · \(task.localizedStatus)"
  }

  private func taskDetail(_ task: Aria2Task) -> String {
    let speed = task.downloadSpeed > 0 ? "  ·  \(Formatting.speed(task.downloadSpeed))" : ""
    return "\(Formatting.bytes(task.completedLength)) / \(Formatting.bytes(task.totalLength))\(speed)"
  }

  private func localizedStatus(_ status: String) -> String {
    switch status {
    case "active":
      return "下载中"
    case "waiting":
      return "等待"
    case "paused":
      return "暂停"
    case "complete":
      return "完成"
    case "error":
      return "错误"
    case "removed":
      return "已移除"
    default:
      return status
    }
  }

  @objc private func retry() {
    Task {
      await engine.ensureRunning(client: client, force: true)
      await refresh()
    }
  }

  @objc private func restartEngine() {
    Task {
      let latestConfig = MotrixConfig.load()
      config = latestConfig
      client.updateConfig(latestConfig)
      engine.updateConfig(latestConfig)
      adaptiveController.updateConfig(latestConfig)
      await engine.restart(client: client)
      await refresh()
    }
  }

  @objc private func refreshNow() {
    Task { await refresh() }
  }

  @objc private func openMainWindow() {
    showMainWindow()
  }

  @objc private func openPreferences() {
    showMainWindow()
    mainWindowController.showPreferences()
  }

  @objc private func openTaskDetails(_ sender: NSMenuItem) {
    guard
      let gid = sender.representedObject as? String,
      let task = tasks.first(where: { $0.id == gid })
    else {
      return
    }

    showMainWindow()
    mainWindowController.showDetails(task)
  }

  @objc private func openAddTask() {
    showMainWindow()
    mainWindowController.showAddTask()
  }

  @objc private func pauseTask(_ sender: NSMenuItem) {
    guard let gid = sender.representedObject as? String else {
      return
    }

    Task {
      do {
        try await client.pause(gid)
        await refresh()
      } catch {
        showError(error)
      }
    }
  }

  @objc private func resumeTask(_ sender: NSMenuItem) {
    guard let gid = sender.representedObject as? String else {
      return
    }

    Task {
      do {
        try await client.unpause(gid)
        await refresh()
      } catch {
        showError(error)
      }
    }
  }

  @objc private func removeTask(_ sender: NSMenuItem) {
    guard let gid = sender.representedObject as? String else {
      return
    }

    guard
      let task = tasks.first(where: { $0.id == gid }),
      MotrixConfig.load().skipsRemovalConfirmation || TaskRemovalConfirmation.confirm(task)
    else {
      return
    }

    Task {
      do {
        if task.status == "complete" || task.status == "error" || task.status == "removed" {
          try await client.removeDownloadResult(gid)
        } else {
          try await client.remove(gid)
        }
        await refresh()
      } catch {
        showError(error)
      }
    }
  }

  @objc private func openTaskFile(_ sender: NSMenuItem) {
    guard
      let gid = sender.representedObject as? String,
      let url = tasks.first(where: { $0.id == gid })?.primaryFileURL
    else {
      return
    }

    NSWorkspace.shared.open(url)
  }

  @objc private func revealTaskFile(_ sender: NSMenuItem) {
    guard
      let gid = sender.representedObject as? String,
      let url = tasks.first(where: { $0.id == gid })?.primaryFileURL
    else {
      return
    }

    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @objc private func openDownloadDirectory() {
    NSWorkspace.shared.open(config.downloadDirectory)
  }

  @objc private func openConfigDirectory() {
    NSWorkspace.shared.open(config.supportDirectory)
  }

  @objc private func openAria2Log() {
    NSWorkspace.shared.open(config.aria2LogPath)
  }

  @objc private func showEngineInfo() {
    let alert = NSAlert()
    alert.messageText = "Motrix Native 引擎信息"
    alert.informativeText = [
      "RPC: 127.0.0.1:\(config.rpcPort)",
      "下载目录: \(config.downloadDirectory.path)",
      "session: \(config.sessionPath.path)",
      "aria2c: \(config.aria2BinaryPath?.path ?? "未找到")",
      "引擎状态: \(engine.statusText)",
      "配置项: \(config.aria2StartArguments().count) 个启动参数",
      "max-connection-per-server: \(config.systemConfig["max-connection-per-server"] ?? "-")",
      "split: \(config.systemConfig["split"] ?? "-")",
      "max-overall-download-limit: \(config.systemConfig["max-overall-download-limit"] ?? "-")"
    ].joined(separator: "\n")
    alert.addButton(withTitle: "好")
    alert.runModal()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func showError(_ error: Error) {
    let alert = NSAlert(error: error)
    alert.runModal()
  }
}

private extension NSMenuItem {
  convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject?, representedObject: Any? = nil) {
    self.init(title: title, action: action, keyEquivalent: keyEquivalent)
    self.target = target
    self.representedObject = representedObject
  }
}
