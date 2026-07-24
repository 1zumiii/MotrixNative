import Foundation

@MainActor
final class AdaptiveConnectionController {
  private struct ProbeState {
    let host: String
    let startedAt: Date
    var currentConnections: Int
    var bestConnections: Int
    var bestSpeed: Double
    let probeCeiling: Int
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
    self.statusText = config.adaptiveConnectionsEnabled ? L10n.tr("adaptive.standby") : L10n.tr("adaptive.disabled")
  }

  func updateConfig(_ config: MotrixConfig) {
    self.config = config
    states.removeAll()
    profiles = AdaptiveConnectionProfileStore.load(from: config.adaptiveProfilePath)
    lastResult = nil
    statusText = config.adaptiveConnectionsEnabled ? L10n.tr("adaptive.standby") : L10n.tr("adaptive.disabled")
  }

  func observe(_ tasks: [Aria2Task]) async {
    guard config.adaptiveConnectionsEnabled else {
      statusText = L10n.tr("adaptive.disabled")
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
      statusText = lastResult ?? L10n.tr("adaptive.standby")
      return
    }

    statusText = L10n.format("adaptive.optimizing_tasks", String(candidates.count))
    let sharedBudget = max(16, 320 / candidates.count)
    for task in candidates {
      await observe(task, sharedBudget: sharedBudget)
    }
  }

  private func observe(_ task: Aria2Task, sharedBudget: Int) async {
    guard let host = task.sourceHost else {
      return
    }

    var state: ProbeState
    if let existing = states[task.id] {
      state = existing
    } else {
      let options = try? await client.getOption(task.id)
      let split = Int(options?["split"] ?? "") ?? config.adaptiveConnectionCeiling
      let ceiling = Aria2Limits.clampConnections(
        min(config.adaptiveConnectionCeiling, sharedBudget, split)
      )
      let reported = Int(options?["max-connection-per-server"] ?? "")
        ?? config.adaptiveStartingConnections
      let current = min(Aria2Limits.clampConnections(reported), ceiling)

      if reported != current {
        try? await apply(current, to: task.id)
      }

      state = ProbeState(
        host: host,
        startedAt: Date(),
        currentConnections: current,
        bestConnections: current,
        bestSpeed: 0,
        probeCeiling: ceiling,
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
      let options = try? await client.getOption(task.id),
      let split = Int(options["split"] ?? ""),
      let next = nextConnectionLevel(
        after: state.currentConnections,
        ceiling: min(config.adaptiveConnectionCeiling, sharedBudget, split)
      )
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
    let connections = Aria2Limits.clampConnections(connections)
    try await client.changeOption(gid, options: [
      "max-connection-per-server": "\(connections)"
    ])
  }

  private func nextConnectionLevel(after current: Int, ceiling: Int) -> Int? {
    let ceiling = Aria2Limits.clampConnections(ceiling)
    return [8, 16, 32, 48, 64].first { $0 > current && $0 <= ceiling }
  }

  private func finish(_ state: inout ProbeState) {
    state.isFinished = true
    state.bestConnections = Aria2Limits.clampConnections(state.bestConnections)
    let existing = profiles[state.host] ?? 1
    profiles[state.host] = state.probeCeiling < config.adaptiveConnectionCeiling
      ? max(existing, state.bestConnections)
      : state.bestConnections
    AdaptiveConnectionProfileStore.save(profiles, to: config.adaptiveProfilePath)
    lastResult = L10n.format("adaptive.result", state.host, String(state.bestConnections))
    statusText = lastResult ?? L10n.tr("adaptive.standby")
  }
}
