import Foundation

enum AdaptiveConnectionProfileStore {
  static func load(from url: URL) -> [String: Int] {
    guard
      let data = try? Data(contentsOf: url),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }

    return object.reduce(into: [:]) { result, entry in
      if let value = entry.value as? Int {
        result[entry.key] = value
      } else if let value = entry.value as? NSNumber {
        result[entry.key] = value.intValue
      }
    }
  }

  static func save(_ profiles: [String: Int], to url: URL) {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try JSONSerialization.data(withJSONObject: profiles, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: url, options: .atomic)
    } catch {
      // Adaptive history is only an optimization; downloads must continue if it cannot be persisted.
    }
  }
}

@MainActor
final class AdaptiveConnectionController {
  private struct ProbeState {
    let host: String
    let startedAt: Date
    var currentConnections: Int
    var bestConnections: Int
    var bestSpeed: Double
    var samples: [Int64]
    var settleUntil: Date
    var adjustments: Int
    var isFinished: Bool
  }

  private var config: MotrixConfig
  private let client: Aria2RPCClient
  private var states: [String: ProbeState] = [:]
  private var profiles: [String: Int]
  private var lastResult: String?

  private(set) var statusText: String

  init(config: MotrixConfig, client: Aria2RPCClient) {
    self.config = config
    self.client = client
    self.profiles = AdaptiveConnectionProfileStore.load(from: config.adaptiveProfilePath)
    self.statusText = config.adaptiveConnectionsEnabled ? "待命" : "已关闭"
  }

  func updateConfig(_ config: MotrixConfig) {
    self.config = config
    states.removeAll()
    profiles = AdaptiveConnectionProfileStore.load(from: config.adaptiveProfilePath)
    lastResult = nil
    statusText = config.adaptiveConnectionsEnabled ? "待命" : "已关闭"
  }

  func observe(_ tasks: [Aria2Task]) async {
    guard config.adaptiveConnectionsEnabled else {
      statusText = "已关闭"
      return
    }

    let retainedIDs = Set(tasks.filter {
      $0.status == "active" || $0.status == "waiting"
    }.map(\.id))
    states = states.filter { retainedIDs.contains($0.key) }

    let candidates = tasks.filter {
      $0.status == "active" &&
        !$0.isBitTorrent &&
        $0.sourceHost != nil &&
        $0.totalLength >= 128 * 1024 * 1024 &&
        $0.progress < 0.10 &&
        states[$0.id]?.isFinished != true
    }

    guard !candidates.isEmpty else {
      statusText = lastResult ?? "待命"
      return
    }

    statusText = "正在优化 \(candidates.count) 个任务"
    let sharedBudget = max(16, 320 / candidates.count)
    for task in candidates {
      await observe(task, sharedBudget: sharedBudget)
    }
  }

  private func observe(_ task: Aria2Task, sharedBudget: Int) async {
    guard let host = task.sourceHost else {
      return
    }

    let ceiling = min(config.adaptiveConnectionCeiling, sharedBudget)
    guard ceiling >= 1 else {
      return
    }

    var state: ProbeState
    if let existing = states[task.id] {
      state = existing
    } else {
      let options = try? await client.getOption(task.id)
      let split = Int(options?["split"] ?? "") ?? config.adaptiveConnectionCeiling
      let perServer = Int(options?["max-connection-per-server"] ?? "") ?? split
      let reported = max(1, min(split, perServer))
      let current = min(reported, ceiling)

      if reported != current {
        try? await apply(current, to: task.id)
      }

      state = ProbeState(
        host: host,
        startedAt: Date(),
        currentConnections: current,
        bestConnections: current,
        bestSpeed: 0,
        samples: [],
        settleUntil: Date().addingTimeInterval(6),
        adjustments: 0,
        isFinished: false
      )
    }

    guard !state.isFinished else {
      states[task.id] = state
      return
    }

    if task.progress >= 0.10 || Date().timeIntervalSince(state.startedAt) >= 90 {
      finish(&state)
      states[task.id] = state
      return
    }

    guard Date() >= state.settleUntil, task.downloadSpeed > 0 else {
      states[task.id] = state
      return
    }

    state.samples.append(task.downloadSpeed)
    guard state.samples.count >= 4 else {
      states[task.id] = state
      return
    }

    let average = Double(state.samples.reduce(Int64(0), +)) / Double(state.samples.count)
    state.samples.removeAll(keepingCapacity: true)

    if state.bestSpeed == 0 {
      state.bestSpeed = average
      state.bestConnections = state.currentConnections
    } else if average >= state.bestSpeed * 1.10 {
      state.bestSpeed = average
      state.bestConnections = state.currentConnections
    } else {
      if state.currentConnections != state.bestConnections {
        try? await apply(state.bestConnections, to: task.id)
      }
      finish(&state)
      states[task.id] = state
      return
    }

    guard
      state.adjustments < 3,
      let next = nextConnectionLevel(after: state.currentConnections, ceiling: ceiling)
    else {
      finish(&state)
      states[task.id] = state
      return
    }

    do {
      try await apply(next, to: task.id)
      state.currentConnections = next
      state.adjustments += 1
      state.settleUntil = Date().addingTimeInterval(6)
    } catch {
      finish(&state)
    }

    states[task.id] = state
  }

  private func apply(_ connections: Int, to gid: String) async throws {
    try await client.changeOption(gid, options: [
      "split": "\(connections)",
      "max-connection-per-server": "\(connections)"
    ])
  }

  private func nextConnectionLevel(after current: Int, ceiling: Int) -> Int? {
    [8, 16, 32, 64, 96, 128].first { $0 > current && $0 <= ceiling }
  }

  private func finish(_ state: inout ProbeState) {
    state.isFinished = true
    profiles[state.host] = state.bestConnections
    AdaptiveConnectionProfileStore.save(profiles, to: config.adaptiveProfilePath)
    lastResult = "\(state.host): \(state.bestConnections) 个连接"
    statusText = lastResult ?? "待命"
  }
}
