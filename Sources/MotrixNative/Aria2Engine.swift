import Foundation

@MainActor
final class Aria2Engine {
  private var config: MotrixConfig
  private var process: Process?
  private var lastStartAttempt: Date?
  private var consecutiveFailures = 0

  private(set) var statusText = "未启动"
  private(set) var lastError: String?

  init(config: MotrixConfig) {
    self.config = config
  }

  func updateConfig(_ config: MotrixConfig) {
    self.config = config
  }

  func ensureRunning(client: Aria2RPCClient, force: Bool = false) async {
    if await canConnect(client: client) {
      statusText = "RPC 已连接"
      consecutiveFailures = 0
      lastError = nil
      return
    }

    guard force || shouldAttemptStart() else {
      return
    }

    startBundledAria2()

    for _ in 0..<15 {
      try? await Task.sleep(for: .milliseconds(200))
      if await canConnect(client: client) {
        statusText = "RPC 已连接"
        consecutiveFailures = 0
        lastError = nil
        return
      }
    }

    statusText = "RPC 未连接"
  }

  func stop() {
    guard let process, process.isRunning else {
      return
    }

    process.terminate()
  }

  func stopGracefully(client: Aria2RPCClient) async {
    guard let ownedProcess = process, ownedProcess.isRunning else {
      return
    }

    statusText = "正在保存任务"
    try? await client.saveSession()
    try? await client.shutdown()

    for _ in 0..<15 where ownedProcess.isRunning {
      try? await Task.sleep(for: .milliseconds(100))
    }

    if ownedProcess.isRunning {
      appendLog("aria2 did not exit after RPC shutdown; terminating the owned process.")
      ownedProcess.terminate()
    }
  }

  func restart(client: Aria2RPCClient) async {
    stop()
    process = nil
    consecutiveFailures = 0
    lastStartAttempt = nil
    await ensureRunning(client: client, force: true)
  }

  private func canConnect(client: Aria2RPCClient) async -> Bool {
    do {
      _ = try await client.getGlobalStat()
      return true
    } catch {
      return false
    }
  }

  private func startBundledAria2() {
    guard let binary = config.aria2BinaryPath else {
      statusText = "缺少 aria2c"
      lastError = "找不到 aria2c"
      return
    }

    lastStartAttempt = Date()
    statusText = "正在启动 aria2"

    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: config.supportDirectory, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = binary
    process.currentDirectoryURL = config.supportDirectory
    process.arguments = config.aria2StartArguments()
    process.terminationHandler = { [weak self] process in
      Task { @MainActor in
        self?.handleProcessExit(process)
      }
    }
    let logURL = config.aria2LogPath
    compactExistingLog(at: logURL)
    if !fileManager.fileExists(atPath: logURL.path) {
      fileManager.createFile(atPath: logURL.path, contents: nil)
    }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      self.process = process
      appendLog("Motrix Native launched aria2c with \(process.arguments?.count ?? 0) arguments.")
    } catch {
      consecutiveFailures += 1
      statusText = "aria2 启动失败"
      lastError = error.localizedDescription
      appendLog("Motrix Native failed to launch aria2c: \(error.localizedDescription)")
      self.process = nil
    }
  }

  private func shouldAttemptStart() -> Bool {
    if let process, process.isRunning {
      return false
    }

    guard let lastStartAttempt else {
      return true
    }

    let delay = min(30, max(2, 1 << min(consecutiveFailures, 5)))
    return Date().timeIntervalSince(lastStartAttempt) >= TimeInterval(delay)
  }

  private func handleProcessExit(_ process: Process) {
    guard self.process === process else {
      return
    }

    self.process = nil
    if process.terminationStatus == 0 {
      statusText = "aria2 已退出"
      return
    }

    consecutiveFailures += 1
    statusText = "aria2 异常退出"
    lastError = "exit \(process.terminationStatus)"
  }

  private func appendLog(_ message: String) {
    let line = "[Motrix Native \(Date())] \(message)\n"
    guard let data = line.data(using: .utf8) else {
      return
    }

    if !FileManager.default.fileExists(atPath: config.aria2LogPath.path) {
      FileManager.default.createFile(atPath: config.aria2LogPath.path, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: config.aria2LogPath) else {
      return
    }

    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
    try? handle.close()
  }

  private func compactExistingLog(at url: URL) {
    guard
      let data = try? Data(contentsOf: url),
      !data.isEmpty,
      let original = String(data: data, encoding: .utf8)
    else {
      return
    }

    let ansiPattern = "\u{001B}\\[[0-9;]*m"
    let plain = original.replacingOccurrences(
      of: ansiPattern,
      with: "",
      options: .regularExpression
    )
    let normalizedNewlines = plain
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    var lines: [String] = []
    var previousLineWasBlank = true
    for line in normalizedNewlines.split(separator: "\n", omittingEmptySubsequences: false) {
      let value = String(line)
      let isBlank = value.trimmingCharacters(in: .whitespaces).isEmpty
      if isBlank {
        if !previousLineWasBlank {
          lines.append("")
        }
      } else {
        lines.append(value)
      }
      previousLineWasBlank = isBlank
    }

    while lines.last?.isEmpty == true {
      lines.removeLast()
    }

    let compacted = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    guard compacted != original else {
      return
    }

    try? Data(compacted.utf8).write(to: url, options: .atomic)
  }
}
