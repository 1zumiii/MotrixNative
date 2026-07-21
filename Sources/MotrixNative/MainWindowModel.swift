import AppKit
import SwiftUI

struct NewDownloadOptions {
  var directory: URL
  var outputName = ""
  var headers = ""
  var cookie = ""
  var referer = ""
  var checksum = ""
  var pauseAtStart = false

  var aria2Options: [String: Any] {
    var result: [String: Any] = [:]
    let outputName = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
    let referer = referer.trimmingCharacters(in: .whitespacesAndNewlines)
    let checksum = checksum.trimmingCharacters(in: .whitespacesAndNewlines)
    var headerLines = headers
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)

    if !outputName.isEmpty { result["out"] = outputName }
    if !referer.isEmpty { result["referer"] = referer }
    if !checksum.isEmpty { result["checksum"] = checksum }
    if !cookie.isEmpty { headerLines.append("Cookie: \(cookie)") }
    if !headerLines.isEmpty { result["header"] = headerLines }
    if pauseAtStart { result["pause"] = "true" }
    return result
  }
}

struct PreparedTorrent: Identifiable {
  let id: String
  let sourceURL: URL
  let directory: URL
  let files: [Aria2TaskFile]
}

private enum NewTaskError: LocalizedError {
  case noTorrentFiles
  case noFilesSelected

  var errorDescription: String? {
    switch self {
    case .noTorrentFiles: return "aria2 没有从这个 torrent 中解析出文件"
    case .noFilesSelected: return "请至少选择一个要下载的文件"
    }
  }
}

@MainActor
final class MainWindowModel: ObservableObject {
  enum Filter: Int, CaseIterable, Identifiable {
    case all
    case active
    case waiting
    case paused
    case completed

    var id: Int { rawValue }

    var title: String {
      switch self {
      case .all: return "全部任务"
      case .active: return "下载中"
      case .waiting: return "等待中"
      case .paused: return "已暂停"
      case .completed: return "已完成"
      }
    }

    var systemImage: String {
      switch self {
      case .all: return "tray.full"
      case .active: return "arrow.down.circle.fill"
      case .waiting: return "clock.fill"
      case .paused: return "pause.circle.fill"
      case .completed: return "checkmark.circle.fill"
      }
    }

    var color: Color {
      switch self {
      case .all: return .indigo
      case .active: return .teal
      case .waiting: return .orange
      case .paused: return .gray
      case .completed: return .green
      }
    }
  }

  enum Section: Hashable {
    case tasks(Filter)
    case preferences(PreferencesSection)
  }

  enum PreferencesSection: Int, CaseIterable, Identifiable {
    case general
    case download
    case bittorrent
    case connection

    var id: Int { rawValue }

    var title: String {
      switch self {
      case .general: return "通用"
      case .download: return "下载"
      case .bittorrent: return "BitTorrent"
      case .connection: return "连接"
      }
    }

    var subtitle: String {
      switch self {
      case .general: return "应用行为与任务提醒"
      case .download: return "保存位置、速度和任务调度"
      case .bittorrent: return "元数据、做种与 Tracker"
      case .connection: return "RPC 与监听端口"
      }
    }

    var systemImage: String {
      switch self {
      case .general: return "gearshape.fill"
      case .download: return "arrow.down.circle.fill"
      case .bittorrent: return "point.3.connected.trianglepath.dotted"
      case .connection: return "network"
      }
    }

    var color: Color {
      switch self {
      case .general: return .blue
      case .download: return .teal
      case .bittorrent: return .purple
      case .connection: return .orange
      }
    }
  }

  @Published private(set) var config: MotrixConfig
  let client: Aria2RPCClient

  @Published var tasks: [Aria2Task] = []
  @Published var globalStat = Aria2GlobalStat(downloadSpeed: 0, uploadSpeed: 0, active: 0, waiting: 0, stopped: 0)
  @Published var filter: Filter = .all
  @Published var selectedSection: Section = .tasks(.all)
  @Published var searchText = ""
  @Published var errorText: String?
  @Published var showingAddTask = false
  @Published var selectedTaskID: String?
  @Published private(set) var selectedPeers: [Aria2Peer] = []
  @Published private(set) var selectedTaskOptions: [String: String] = [:]
  @Published var settings = SettingsDraft()
  @Published var settingsSaved = false

  private var refreshTimer: Timer?

  init(config: MotrixConfig, client: Aria2RPCClient) {
    self.config = config
    self.client = client
    self.settings = SettingsDraft(config: config)
  }

  var filteredTasks: [Aria2Task] {
    guard case .tasks(let filter) = selectedSection else {
      return []
    }

    var result = tasks

    switch filter {
    case .all:
      break
    case .active:
      result = result.filter { $0.status == "active" }
    case .waiting:
      result = result.filter { $0.status == "waiting" }
    case .paused:
      result = result.filter { $0.status == "paused" }
    case .completed:
      result = result.filter { $0.status == "complete" }
    }

    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
      result = result.filter {
        $0.name.localizedCaseInsensitiveContains(query) ||
          ($0.primaryFileURL?.path.localizedCaseInsensitiveContains(query) ?? false)
      }
    }

    return result
  }

  var summaryText: String {
    "\(filteredTasks.count) 个任务 · 下载 \(Formatting.speed(globalStat.downloadSpeed)) · 上传 \(Formatting.speed(globalStat.uploadSpeed))"
  }

  var selectedTask: Aria2Task? {
    guard let selectedTaskID else { return nil }
    return tasks.first { $0.id == selectedTaskID }
  }

  var defaultDownloadDirectory: URL { config.downloadDirectory }
  var defaultPauseAtStart: Bool { settings.pause }

  func count(for filter: Filter) -> Int {
    switch filter {
    case .all:
      return tasks.count
    case .active:
      return tasks.filter { $0.status == "active" }.count
    case .waiting:
      return tasks.filter { $0.status == "waiting" }.count
    case .paused:
      return tasks.filter { $0.status == "paused" }.count
    case .completed:
      return tasks.filter { $0.status == "complete" }.count
    }
  }

  func select(_ section: Section) {
    selectedTaskID = nil
    selectedTaskOptions = [:]
    selectedPeers = []
    selectedSection = section
    if case .tasks(let filter) = section {
      self.filter = filter
    }
  }

  func showDetails(_ task: Aria2Task) {
    selectedTaskID = task.id
    selectedTaskOptions = [:]
    selectedPeers = []
    Task { await refreshDetails(for: task) }
  }

  func closeDetails() {
    selectedTaskID = nil
    selectedTaskOptions = [:]
    selectedPeers = []
  }

  func copyGID(_ task: Aria2Task) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(task.id, forType: .string)
  }

  func startRefreshing() {
    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.refresh()
      }
    }
    Task { await refresh() }
  }

  func stopRefreshing() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  func refresh() async {
    do {
      let latestStat = try await client.getGlobalStat()
      let latestTasks = try await client.listTasks()
      tasks = latestTasks
      globalStat = latestStat.usingActiveTaskSpeeds(latestTasks)
      if let selectedTaskID, let selected = latestTasks.first(where: { $0.id == selectedTaskID }) {
        selectedTaskOptions = (try? await client.getOption(selectedTaskID)) ?? [:]
        if selected.isBitTorrent {
          selectedPeers = (try? await client.getPeers(selectedTaskID)) ?? []
        } else {
          selectedPeers = []
        }
      } else {
        selectedTaskOptions = [:]
        selectedPeers = []
      }
      errorText = nil
    } catch {
      errorText = "RPC 未连接"
    }
  }

  @discardableResult
  func addLink(_ uri: String, options: NewDownloadOptions? = nil) async -> Bool {
    let uri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !uri.isEmpty else {
      return false
    }

    let options = options ?? NewDownloadOptions(directory: config.downloadDirectory)
    do {
      try await client.addURI(
        uri,
        directory: options.directory,
        additionalOptions: options.aria2Options
      )
      await refresh()
      return true
    } catch {
      NSAlert(error: error).runModal()
      return false
    }
  }

  func prepareTorrent(_ fileURL: URL, directory: URL) async -> PreparedTorrent? {
    var gid: String?
    do {
      gid = try await client.addTorrent(
        fileURL,
        directory: directory,
        additionalOptions: ["pause": "true"]
      )

      var files: [Aria2TaskFile] = []
      for _ in 0..<10 where files.isEmpty {
        files = try await client.getFiles(gid ?? "")
        if files.isEmpty {
          try? await Task.sleep(for: .milliseconds(100))
        }
      }

      guard let gid, !files.isEmpty else {
        throw NewTaskError.noTorrentFiles
      }
      await refresh()
      return PreparedTorrent(id: gid, sourceURL: fileURL, directory: directory, files: files)
    } catch {
      if let gid {
        try? await client.remove(gid)
      }
      NSAlert(error: error).runModal()
      await refresh()
      return nil
    }
  }

  @discardableResult
  func startPreparedTorrent(
    _ torrent: PreparedTorrent,
    selectedFileIDs: Set<String>,
    pauseAtStart: Bool
  ) async -> Bool {
    guard !selectedFileIDs.isEmpty else {
      NSAlert(error: NewTaskError.noFilesSelected).runModal()
      return false
    }

    do {
      let selected = selectedFileIDs
        .compactMap(Int.init)
        .sorted()
        .map(String.init)
        .joined(separator: ",")
      try await client.changeOption(torrent.id, options: ["select-file": selected])
      if !pauseAtStart {
        try await client.unpause(torrent.id)
      }
      await refresh()
      return true
    } catch {
      NSAlert(error: error).runModal()
      return false
    }
  }

  func discardPreparedTorrent(_ torrent: PreparedTorrent) async {
    try? await client.remove(torrent.id)
    await refresh()
  }

  private func refreshDetails(for task: Aria2Task) async {
    let options = (try? await client.getOption(task.id)) ?? [:]
    let peers = task.isBitTorrent ? ((try? await client.getPeers(task.id)) ?? []) : []
    guard selectedTaskID == task.id else { return }
    selectedTaskOptions = options
    selectedPeers = peers
  }

  func pause(_ task: Aria2Task) async {
    do {
      try await client.pause(task.id)
      tasks = tasks.map {
        $0.id == task.id
          ? $0.updating(status: "paused", downloadSpeed: 0, uploadSpeed: 0)
          : $0
      }
      globalStat = globalStat.usingActiveTaskSpeeds(tasks)
      await refresh()
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  func resume(_ task: Aria2Task) async {
    await perform {
      try await client.unpause(task.id)
    }
  }

  func remove(_ task: Aria2Task) async {
    guard settings.noConfirmBeforeDeleteTask || TaskRemovalConfirmation.confirm(task) else {
      return
    }

    await perform {
      if task.status == "complete" || task.status == "error" || task.status == "removed" {
        try await client.removeDownloadResult(task.id)
      } else {
        try await client.remove(task.id)
      }
    }
    if selectedTaskID == task.id {
      selectedTaskID = nil
    }
  }

  func reveal(_ task: Aria2Task) {
    guard let url = task.primaryFileURL else {
      NSWorkspace.shared.open(config.downloadDirectory)
      return
    }

    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func openDownloadDirectory() {
    NSWorkspace.shared.open(config.downloadDirectory)
  }

  func chooseDownloadDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = config.downloadDirectory

    if panel.runModal() == .OK, let url = panel.url {
      settings.downloadDirectory = url.path
    }
  }

  func saveSettings() {
    do {
      let system = settings.systemConfig(basedOn: config.systemConfig)
      let user = settings.userConfig(basedOn: config.userConfig)
      try config.save(system: system, user: user)
      config = config.updating(system: system, user: user)
      settings = SettingsDraft(config: config)
      settingsSaved = true

      do {
        try LoginItemManager.apply(settings.openAtLogin)
      } catch {
        let alert = NSAlert(error: error)
        alert.messageText = "无法更新登录项"
        alert.runModal()
      }

      if settings.taskNotification {
        TaskNotificationManager.requestAuthorization()
      }
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  func resetSettings() {
    settings = SettingsDraft(config: config)
    settingsSaved = false
  }

  private func perform(_ operation: () async throws -> Void) async {
    do {
      try await operation()
      await refresh()
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }
}

struct SettingsDraft {
  var downloadDirectory = ""
  var maxOverallDownloadLimit = ""
  var maxOverallUploadLimit = ""
  var maxConcurrentDownloads = 5
  var maxConnectionPerServer = 64
  var split = 64
  var pause = true
  var continueDownloads = true
  var btSaveMetadata = true
  var btForceEncryption = false
  var seedingEnabled = true
  var seedRatio = 1
  var seedTime = 60
  var btTracker = ""
  var rpcPort = 16800
  var rpcSecret = ""
  var listenPort = 21301
  var dhtListenPort = 26701
  var openAtLogin = false
  var taskNotification = true
  var noConfirmBeforeDeleteTask = false
  var adaptiveConnections = true

  init() {}

  init(config: MotrixConfig) {
    let system = config.systemConfig
    let user = config.userConfig
    downloadDirectory = system["dir"] as? String ?? config.downloadDirectory.path
    maxOverallDownloadLimit = Self.string(system["max-overall-download-limit"], fallback: "0")
    maxOverallUploadLimit = Self.string(system["max-overall-upload-limit"], fallback: "0")
    maxConcurrentDownloads = Self.int(system["max-concurrent-downloads"], fallback: 5)
    maxConnectionPerServer = Self.int(system["max-connection-per-server"], fallback: 64)
    split = Self.int(system["split"], fallback: 64)
    pause = Self.bool(system["pause"], fallback: true)
    continueDownloads = Self.bool(system["continue"], fallback: true)
    btSaveMetadata = Self.bool(system["bt-save-metadata"], fallback: true)
    btForceEncryption = Self.bool(system["bt-force-encryption"], fallback: false)
    seedRatio = Self.int(system["seed-ratio"], fallback: 1)
    seedTime = Self.int(system["seed-time"], fallback: 60)
    seedingEnabled = Self.bool(
      user["seeding-enabled"],
      fallback: Self.bool(user["keep-seeding"], fallback: false) || seedTime != 0
    )
    btTracker = system["bt-tracker"] as? String ?? ""
    rpcPort = Self.int(system["rpc-listen-port"], fallback: 16800)
    rpcSecret = system["rpc-secret"] as? String ?? ""
    listenPort = Self.int(system["listen-port"], fallback: 21301)
    dhtListenPort = Self.int(system["dht-listen-port"], fallback: 26701)
    openAtLogin = Self.bool(user["open-at-login"], fallback: false)
    taskNotification = Self.bool(user["task-notification"], fallback: true)
    noConfirmBeforeDeleteTask = Self.bool(user["no-confirm-before-delete-task"], fallback: false)
    adaptiveConnections = Self.bool(user["adaptive-connections"], fallback: true)
  }

  func systemConfig(basedOn base: [String: Any]) -> [String: Any] {
    var result = base
    result["dir"] = downloadDirectory
    result["max-overall-download-limit"] = maxOverallDownloadLimit
    result["max-overall-upload-limit"] = maxOverallUploadLimit
    result["max-concurrent-downloads"] = maxConcurrentDownloads
    result["max-connection-per-server"] = maxConnectionPerServer
    result["split"] = split
    result["pause"] = pause
    result["continue"] = continueDownloads
    result["bt-save-metadata"] = btSaveMetadata
    result["bt-force-encryption"] = btForceEncryption
    result["seed-ratio"] = seedRatio
    result["seed-time"] = seedingEnabled ? seedTime : 0
    result["bt-tracker"] = btTracker
    result["rpc-listen-port"] = rpcPort
    result["rpc-secret"] = rpcSecret
    result["listen-port"] = listenPort
    result["dht-listen-port"] = dhtListenPort
    return result
  }

  func userConfig(basedOn base: [String: Any]) -> [String: Any] {
    var result = base
    result["open-at-login"] = openAtLogin
    result["task-notification"] = taskNotification
    result["no-confirm-before-delete-task"] = noConfirmBeforeDeleteTask
    result["adaptive-connections"] = adaptiveConnections
    result["seeding-enabled"] = seedingEnabled
    if !seedingEnabled {
      result["keep-seeding"] = false
    }
    return result
  }

  private static func string(_ value: Any?, fallback: String) -> String {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return fallback
  }

  private static func int(_ value: Any?, fallback: Int) -> Int {
    if let value = value as? Int { return value }
    if let value = value as? String { return Int(value) ?? fallback }
    if let value = value as? NSNumber { return value.intValue }
    return fallback
  }

  private static func bool(_ value: Any?, fallback: Bool) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String { return value == "true" }
    return fallback
  }
}
