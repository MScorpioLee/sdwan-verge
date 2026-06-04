import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let tunChannelName = "sdwan_client/tun"
  private let defaultCpeHost = "192.168.1.140"
  private let helperName = "sdwan-macos-helper"

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: tunChannelName,
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.setMethodCallHandler(handleTunCall)
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func handleTunCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(helperStatus())
    case "healthCheck":
      result(helperHealth())
    case "start":
      result(startHelper())
    case "stop":
      result(stopHelper())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func unsupportedStatus(
    state: String = "stopped",
    message: String = "macOS Packet Tunnel 后端尚未接入"
  ) -> [String: Any] {
    return [
      "state": state,
      "permission": "unsupported",
      "cpe": unavailableHealth(),
      "lastError": message,
    ]
  }

  private func unavailableHealth() -> [String: Any] {
    return [
      "host": defaultCpeHost,
      "reachable": false,
      "serviceReady": false,
      "error": "TUN 原生服务尚未接入",
    ]
  }

  private func helperStatus() -> [String: Any] {
    guard helperPath() != nil else {
      return unsupportedStatus(message: "macOS helper 未安装")
    }
    let output = runHelper(["status"]).output
    return statusFromPairs(parsePairs(output), fallbackState: "stopped")
  }

  private func helperHealth() -> [String: Any] {
    guard helperPath() != nil else {
      return [
        "host": defaultCpeHost,
        "reachable": false,
        "serviceReady": false,
        "error": "macOS helper 未安装",
      ]
    }
    return healthFromPairs(parsePairs(runHelper(["health"]).output))
  }

  private func startHelper() -> [String: Any] {
    guard helperPath() != nil else {
      return unsupportedStatus(state: "failed", message: "macOS helper 未安装")
    }
    let run = runHelperPrivileged(["start"])
    if run.exitCode != 0 {
      return unsupportedStatus(
        state: "failed",
        message: run.output.isEmpty ? "helper 启动失败" : run.output
      )
    }
    return statusFromPairs(parsePairs(runHelper(["status"]).output), fallbackState: "running")
  }

  private func stopHelper() -> [String: Any] {
    guard helperPath() != nil else {
      return unsupportedStatus(message: "macOS helper 未安装")
    }
    let run = runHelperPrivileged(["stop"])
    if run.exitCode != 0 {
      return statusFromPairs(
        ["state": "failed", "lastError": run.output],
        fallbackState: "failed"
      )
    }
    return statusFromPairs(parsePairs(runHelper(["status"]).output), fallbackState: "stopped")
  }

  private func statusFromPairs(_ pairs: [String: String], fallbackState: String) -> [String: Any] {
    let state = pairs["state"] ?? fallbackState
    var status: [String: Any] = [
      "state": state,
      "permission": pairs["permission"] ?? "needsHelperInstall",
      "cpe": healthFromPairs(pairs),
    ]
    if let lastError = pairs["lastError"] ?? pairs["message"], !lastError.isEmpty {
      status["lastError"] = lastError
    }
    return status
  }

  private func healthFromPairs(_ pairs: [String: String]) -> [String: Any] {
    return [
      "host": pairs["host"] ?? pairs["cpe"] ?? defaultCpeHost,
      "reachable": pairs["reachable"] == "true",
      "serviceReady": pairs["serviceReady"] == "true",
      "error": pairs["error"] ?? "",
    ]
  }

  private func parsePairs(_ output: String) -> [String: String] {
    var pairs: [String: String] = [:]
    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
      guard let separator = line.firstIndex(of: "=") else {
        continue
      }
      let key = String(line[..<separator])
      let value = String(line[line.index(after: separator)...])
      pairs[key] = value
    }
    return pairs
  }

  private func helperPath() -> String? {
    if let bundled = Bundle.main.path(forResource: helperName, ofType: nil) {
      return bundled
    }
    let devPath = FileManager.default.currentDirectoryPath
      + "/build/macos/helper/"
      + helperName
    return FileManager.default.isExecutableFile(atPath: devPath) ? devPath : nil
  }

  private func runHelper(_ arguments: [String]) -> (exitCode: Int32, output: String) {
    guard let helper = helperPath() else {
      return (127, "macOS helper 未安装")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helper)
    process.arguments = arguments
    return runProcess(process)
  }

  private func runHelperPrivileged(_ arguments: [String]) -> (exitCode: Int32, output: String) {
    guard let helper = helperPath() else {
      return (127, "macOS helper 未安装")
    }
    let command = ([helper] + arguments).map(shellQuote).joined(separator: " ")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [
      "-e",
      "do shell script \"\(appleScriptEscape(command))\" with administrator privileges",
    ]
    return runProcess(process)
  }

  private func runProcess(_ process: Process) -> (exitCode: Int32, output: String) {
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return (126, error.localizedDescription)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private func shellQuote(_ value: String) -> String {
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func appleScriptEscape(_ value: String) -> String {
    return value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}
