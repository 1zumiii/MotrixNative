import AppKit
import Darwin

if CommandLine.arguments.contains("--self-check") {
  let config = MotrixConfig.load()
  let binaryReady = config.aria2BinaryPath.map {
    FileManager.default.isExecutableFile(atPath: $0.path)
  } ?? false
  let configReady = FileManager.default.fileExists(atPath: config.aria2ConfigPath.path)
  let supportReady = config.supportDirectory.lastPathComponent == "Motrix Native"
  let seedTimeArgument = config.aria2StartArguments().first { $0.hasPrefix("--seed-time=") } ?? ""
  var disabledSeedingUser = config.userConfig
  disabledSeedingUser["seeding-enabled"] = false
  let disabledSeedingArgument = config.updating(user: disabledSeedingUser)
    .aria2StartArguments()
    .first { $0.hasPrefix("--seed-time=") } ?? ""
  let seedingDisableReady = disabledSeedingArgument == "--seed-time=0"
  let adaptiveStartReady = config.adaptiveStartingConnections == min(48, config.adaptiveConnectionCeiling)
  let syntheticTorrent = Aria2Task(
    id: "self-check",
    status: "complete",
    totalLength: 1,
    completedLength: 1,
    uploadLength: 0,
    downloadSpeed: 0,
    uploadSpeed: 0,
    connections: 0,
    pieceLength: 1,
    numPieces: 1,
    bitfield: "8",
    errorCode: "0",
    errorMessage: "",
    directory: "/tmp/downloads",
    bitTorrentName: "Example",
    infoHash: "",
    trackers: [],
    files: [],
    isBitTorrent: true
  )
  let controlFileMappingReady = CompletedControlFileCleaner.controlFiles(for: syntheticTorrent)
    .contains(URL(fileURLWithPath: "/tmp/downloads/Example.aria2"))
  let pieceBitfieldReady = syntheticTorrent.pieceCompletion == [true]
  let trackerNormalizationReady = TrackerList.aria2Value(
    from: "udp://tracker.example:80/announce\nhttps://tracker.example/announce\nwss://unsupported.example/announce"
  ) == "udp://tracker.example:80/announce,https://tracker.example/announce"
  let configuredTrackerValue = config.systemConfig["bt-tracker"] as? String ?? ""
  let configuredTrackerArgument = config.aria2StartArguments().first { $0.hasPrefix("--bt-tracker=") } ?? ""
  let configuredTrackerArgumentReady = !configuredTrackerArgument.contains("\n") && !configuredTrackerArgument.contains("wss://")
  let loggingArguments = Set(config.aria2StartArguments().filter {
    $0.hasPrefix("--log=")
      || $0.hasPrefix("--log-level=")
      || $0.hasPrefix("--quiet=")
      || $0.hasPrefix("--show-console-readout=")
      || $0.hasPrefix("--enable-color=")
  })
  let cleanFileLoggingReady = loggingArguments == [
    "--log=\(config.aria2LogPath.path)",
    "--log-level=notice",
    "--quiet=true",
    "--show-console-readout=false",
    "--enable-color=false"
  ]
  let logRotationReady: Bool = {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("motrix-native-log-check-\(UUID().uuidString)", isDirectory: true)
    let activeURL = directory.appendingPathComponent("aria2.log")
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let original = Data(repeating: 65, count: 65)
      try original.write(to: activeURL)
      let store = Aria2LogStore(activeURL: activeURL, maximumFileSize: 64, retainedArchiveCount: 2)
      store.rotateIfNeeded()
      let activeSize = try Data(contentsOf: activeURL).count
      let archived = try Data(contentsOf: store.archiveURL(index: 1))
      return activeSize == 0 && archived == original
    } catch {
      return false
    }
  }()
  let localizationReady: Bool = {
    let key = "action.cancel"
    let values = ["zh-Hans", "en"].compactMap { language -> String? in
      guard
        let path = Bundle.main.path(forResource: language, ofType: "lproj"),
        let bundle = Bundle(path: path)
      else {
        return nil
      }
      return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    return values.count == 2 && values.allSatisfy { $0 != key } && values[0] != values[1]
  }()
  let languageSwitchReady: Bool = {
    defer { L10n.configure(language: config.appLanguage) }
    L10n.configure(language: L10n.Language.english.rawValue)
    let english = L10n.tr("action.cancel")
    L10n.configure(language: L10n.Language.simplifiedChinese.rawValue)
    let simplifiedChinese = L10n.tr("action.cancel")
    return english != "action.cancel" && simplifiedChinese != "action.cancel" && english != simplifiedChinese
  }()
  let result: [String: Any] = [
    "aria2Binary": config.aria2BinaryPath?.path ?? "",
    "aria2BinaryReady": binaryReady,
    "aria2Config": config.aria2ConfigPath.path,
    "aria2ConfigReady": configReady,
    "adaptiveConnectionCeiling": config.adaptiveConnectionCeiling,
    "adaptiveStartingConnections": config.adaptiveStartingConnections,
    "adaptiveStartReady": adaptiveStartReady,
    "rpcPort": config.rpcPort,
    "seedTimeArgument": seedTimeArgument,
    "seedingDisableReady": seedingDisableReady,
    "session": config.sessionPath.path,
    "supportDirectory": config.supportDirectory.path,
    "supportDirectoryReady": supportReady,
    "controlFileMappingReady": controlFileMappingReady,
    "pieceBitfieldReady": pieceBitfieldReady,
    "trackerNormalizationReady": trackerNormalizationReady,
    "configuredTrackerArgumentReady": configuredTrackerArgumentReady,
    "cleanFileLoggingReady": cleanFileLoggingReady,
    "logRotationReady": logRotationReady,
    "localizationReady": localizationReady,
    "languageSwitchReady": languageSwitchReady,
    "configuredTrackerCount": TrackerList.supportedEntries(from: configuredTrackerValue).count,
    "ignoredTrackerCount": TrackerList.unsupportedEntries(from: configuredTrackerValue).count
  ]
  let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
  exit(binaryReady && configReady && supportReady && controlFileMappingReady && pieceBitfieldReady && trackerNormalizationReady && configuredTrackerArgumentReady && cleanFileLoggingReady && logRotationReady && localizationReady && languageSwitchReady && seedingDisableReady && adaptiveStartReady ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
