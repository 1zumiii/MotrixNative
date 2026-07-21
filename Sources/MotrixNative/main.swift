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
    "controlFileMappingReady": controlFileMappingReady
  ]
  let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
  exit(binaryReady && configReady && supportReady && controlFileMappingReady && seedingDisableReady && adaptiveStartReady ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
