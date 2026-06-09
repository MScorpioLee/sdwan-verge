import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate, NSMenuDelegate {
  private let tunChannelName = "sdwan_client/tun"
  private let defaultCpeHost = "192.168.1.140"
  private let helperName = "sdwan-macos-helper"
  private let installedHelperPath = "/Library/PrivilegedHelperTools/com.sdwan.verge.helper"
  private let launchAgentIdentifier = "com.sdwan.verge.launcher"
  private let openVpnDirName = "OpenVPN"
  private var tunChannel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?
  private var statusToggleItem: NSMenuItem?
  private var lastCpeHost = "192.168.1.140"
  private var didStopAccelerationBeforeExit = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    registerTunChannel()
    DispatchQueue.main.async { [weak self] in
      self?.registerTunChannel()
      self?.configureWindowLifecycle()
    }
    setupStatusItem()
  }

  func registerTunChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: tunChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler(handleTunCall)
    tunChannel = channel
  }

  private func registerTunChannel() {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      registerTunChannel(controller: controller)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    stopAccelerationBeforeExit()
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showMainWindow(nil)
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }

  private func handleTunCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    lastCpeHost = cpeHost(from: call.arguments)
    switch call.method {
    case "status":
      let status = helperStatus(call.arguments)
      updateStatusItemAppearance()
      result(status)
    case "healthCheck":
      result(helperHealth(call.arguments))
    case "logs":
      result(helperLogs(call.arguments))
    case "connections":
      result(helperConnections(call.arguments))
    case "installHelper":
      result(installHelper(call.arguments))
    case "uninstallHelper":
      result(uninstallHelper(call.arguments))
    case "start":
      let status = startHelper(call.arguments)
      updateStatusItemAppearance()
      result(status)
    case "stop":
      let status = stopHelper(call.arguments)
      updateStatusItemAppearance()
      result(status)
    case "launchAtLoginStatus":
      result(launchAtLoginEnabled())
    case "setLaunchAtLogin":
      result(setLaunchAtLogin(call.arguments))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configureWindowLifecycle() {
    mainFlutterWindow?.delegate = self
  }

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.toolTip = "SD-WAN"
    let menu = NSMenu()
    menu.delegate = self
    let showItem = NSMenuItem(
      title: "显示主窗口",
      action: #selector(showMainWindow(_:)),
      keyEquivalent: ""
    )
    showItem.target = self
    menu.addItem(showItem)
    let toggleItem = NSMenuItem(
      title: "关闭加速",
      action: #selector(toggleAccelerationFromStatusMenu(_:)),
      keyEquivalent: ""
    )
    toggleItem.target = self
    menu.addItem(toggleItem)
    statusToggleItem = toggleItem
    menu.addItem(NSMenuItem.separator())
    let quitItem = NSMenuItem(
      title: "退出",
      action: #selector(quitFromStatusMenu(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item
    updateStatusItemAppearance()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    updateStatusItemAppearance()
  }

  @objc private func showMainWindow(_ sender: Any?) {
    guard let window = mainFlutterWindow else {
      return
    }
    window.deminiaturize(nil)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quitFromStatusMenu(_ sender: Any?) {
    stopAccelerationBeforeExit()
    NSApp.terminate(nil)
  }

  private func stopAccelerationBeforeExit() {
    guard !didStopAccelerationBeforeExit else {
      return
    }
    didStopAccelerationBeforeExit = true
    guard installedHelperAvailable() || isAccelerationRunning(arguments: statusMenuArguments()) else {
      return
    }
    _ = stopHelper(statusMenuArguments())
    updateStatusItemAppearance()
  }

  @objc private func toggleAccelerationFromStatusMenu(_ sender: Any?) {
    statusToggleItem?.isEnabled = false
    let arguments = statusMenuArguments()
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }
      if self.isAccelerationRunning(arguments: arguments) {
        _ = self.stopHelper(arguments)
      } else {
        _ = self.startHelper(arguments)
      }
      DispatchQueue.main.async { [weak self] in
        self?.statusToggleItem?.isEnabled = true
        self?.updateStatusItemAppearance()
      }
    }
  }

  private func statusMenuArguments() -> [String: Any] {
    ["cpeHost": lastCpeHost]
  }

  private func isAccelerationRunning(arguments: Any? = nil) -> Bool {
    let status = helperStatus(arguments ?? statusMenuArguments())
    let state = status["state"] as? String
    return state == "running" || state == "starting"
  }

  private func updateStatusItemAppearance() {
    let running = isAccelerationRunning()
    statusToggleItem?.title = running ? "关闭加速" : "开启加速"
    statusItem?.button?.toolTip = running ? "SD-WAN Verge - 已加速" : "SD-WAN Verge"
    if #available(macOS 11.0, *) {
      let symbolName = running ? "bolt.circle.fill" : "bolt.circle"
      statusItem?.button?.image = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: running ? "已加速" : "未加速"
      )
      statusItem?.button?.imagePosition = .imageOnly
      statusItem?.button?.contentTintColor = running ? .systemGreen : .secondaryLabelColor
      statusItem?.button?.title = ""
    } else {
      statusItem?.button?.image = nil
      statusItem?.button?.title = running ? "SD+" : "SD"
    }
  }

  private func unsupportedStatus(
    state: String = "stopped",
    message: String = "macOS 半路由后端尚未接入",
    cpeHost: String? = nil
  ) -> [String: Any] {
    return [
      "state": state,
      "permission": "unsupported",
      "cpe": unavailableHealth(cpeHost: cpeHost),
      "lastError": message,
    ]
  }

  private func unavailableHealth(cpeHost: String? = nil) -> [String: Any] {
    return [
      "host": cpeHost ?? defaultCpeHost,
      "reachable": false,
      "serviceReady": false,
      "error": "半路由服务尚未接入",
    ]
  }

  private func helperStatus(_ arguments: Any?) -> [String: Any] {
    if mode(from: arguments) == "openvpn" {
      return openVpnStatus(arguments: arguments)
    }
    guard helperPath() != nil else {
      return unsupportedStatus(
        message: "macOS helper 未安装",
        cpeHost: cpeHost(from: arguments)
      )
    }
    if !installedHelperReady() {
      var status: [String: Any] = [
        "state": "stopped",
        "permission": "needsHelperInstall",
        "helperInstalled": false,
        "cpe": helperHealth(arguments),
        "txBytes": 0,
        "rxBytes": 0,
        "txRate": 0,
        "rxRate": 0,
        "txPackets": 0,
        "rxPackets": 0,
        "txDropped": 0,
        "rxDropped": 0,
        "natMisses": 0,
        "sendFailures": 0,
        "udp443Packets": 0,
      ]
      if installedHelperNeedsUpdate() {
        status["lastError"] = "助手版本已更新，请重新授权安装"
      }
      return status
    }
    var pairs = parsePairs(runHelper(helperArguments(["status"], from: arguments)).output)
    normalizeRecoveredStatus(&pairs, arguments: arguments)
    let status = statusFromPairs(pairs, fallbackState: "stopped")
    return status
  }

  private func helperHealth(_ arguments: Any?) -> [String: Any] {
    if mode(from: arguments) == "openvpn" {
      return openVpnHealth(arguments: arguments)
    }
    guard helperPath() != nil else {
      return [
        "host": cpeHost(from: arguments),
        "reachable": false,
        "serviceReady": false,
        "error": "macOS helper 未安装",
      ]
    }
    return healthFromPairs(parsePairs(runHelper(helperArguments(["health"], from: arguments)).output))
  }

  private func startHelper(_ arguments: Any?) -> [String: Any] {
    if mode(from: arguments) == "openvpn" {
      return startOpenVpn(arguments: arguments)
    }
    guard helperPath() != nil else {
      return unsupportedStatus(
        state: "failed",
        message: "macOS helper 未安装",
        cpeHost: cpeHost(from: arguments)
      )
    }
    if installedHelperNeedsUpdate() {
      return unsupportedStatus(
        state: "failed",
        message: "助手版本已更新，请重新授权安装",
        cpeHost: cpeHost(from: arguments)
      )
    }
    let startArgs = helperArguments(["start"], from: arguments)
    let run = installedHelperReady() ? runHelper(startArgs) : runHelperPrivileged(startArgs)
    if run.exitCode != 0 {
      return unsupportedStatus(
        state: "failed",
        message: run.output.isEmpty ? "helper 启动失败" : run.output,
        cpeHost: cpeHost(from: arguments)
      )
    }
    let status = waitForHelperStatus(
      preferredState: "running",
      fallbackState: "failed",
      arguments: arguments
    )
    if status["state"] as? String == "running" {
      return status
    }
    var failed = status
    failed["state"] = "failed"
    if failed["lastError"] == nil {
        failed["lastError"] = "半路由未进入运行状态，请查看日志"
    }
    return failed
  }

  private func stopHelper(_ arguments: Any?) -> [String: Any] {
    if mode(from: arguments) == "openvpn" {
      return stopOpenVpn(arguments: arguments)
    }
    guard helperPath() != nil else {
      return unsupportedStatus(
        message: "macOS helper 未安装",
        cpeHost: cpeHost(from: arguments)
      )
    }
    let stopArgs = helperArguments(["stop"], from: arguments)
    let run = installedHelperAvailable() ? runInstalledHelper(stopArgs) : runHelperPrivileged(stopArgs)
    if run.exitCode != 0 {
      return statusFromPairs(
        ["state": "failed", "lastError": run.output],
        fallbackState: "failed"
      )
    }
    return statusFromPairs(
      parsePairs(runHelper(helperArguments(["status"], from: arguments)).output),
      fallbackState: "stopped"
    )
  }

  private func statusFromPairs(_ pairs: [String: String], fallbackState: String) -> [String: Any] {
    let state = pairs["state"] ?? fallbackState
    var status: [String: Any] = [
      "state": state,
      "adapterName": pairs["adapterName"] ?? "macOS Half Route",
      "permission": pairs["permission"] ?? "needsHelperInstall",
      "helperInstalled": installedHelperReady(),
      "cpe": healthFromPairs(pairs),
      "txBytes": intFromPair(pairs["tx_bytes"]),
      "rxBytes": intFromPair(pairs["rx_bytes"]),
      "txRate": intFromPair(pairs["tx_rate"]),
      "rxRate": intFromPair(pairs["rx_rate"]),
      "txPackets": intFromPair(pairs["tx_packets"]),
      "rxPackets": intFromPair(pairs["rx_packets"]),
      "txDropped": intFromPair(pairs["tx_dropped"]),
      "rxDropped": intFromPair(pairs["rx_dropped"]),
      "natMisses": intFromPair(pairs["nat_misses"]),
      "sendFailures": intFromPair(pairs["send_failures"]),
      "udp443Packets": intFromPair(pairs["udp443_packets"]),
    ]
    if let lastError = pairs["lastError"] ?? pairs["message"],
       !lastError.isEmpty,
       lastError != "running",
       lastError != "stopped" {
      status["lastError"] = lastError
    }
    return status
  }

  private func normalizeRecoveredStatus(_ pairs: inout [String: String], arguments: Any?) {
    guard pairs["state"] == "autoRecovered" else {
      return
    }
    let health = parsePairs(runHelper(helperArguments(["health"], from: arguments)).output)
    guard health["reachable"] == "true", health["serviceReady"] == "true" else {
      return
    }
    pairs["state"] = "stopped"
    pairs["lastError"] = ""
    pairs["message"] = ""
    pairs["reachable"] = health["reachable"]
    pairs["serviceReady"] = health["serviceReady"]
    pairs["error"] = health["error"] ?? ""
  }

  private func waitForHelperStatus(
    preferredState: String,
    fallbackState: String,
    arguments: Any?
  ) -> [String: Any] {
    var latest: [String: Any] = unsupportedStatus(
      state: fallbackState,
      message: "",
      cpeHost: cpeHost(from: arguments)
    )
    for _ in 0..<40 {
      let pairs = parsePairs(runHelper(helperArguments(["status"], from: arguments)).output)
      latest = statusFromPairs(pairs, fallbackState: fallbackState)
      if pairs["state"] == preferredState {
        return latest
      }
      if pairs["state"] == "failed" {
        return latest
      }
      Thread.sleep(forTimeInterval: 0.2)
    }
    return latest
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

  private func helperLogs(_ arguments: Any?) -> [[String: String]] {
    if mode(from: arguments) == "openvpn" {
      return openVpnLogs(limit: logsLimit(from: arguments))
    }
    let limit = logsLimit(from: arguments)
    let output = runHelper(helperArguments(["logs", "\(limit)"], from: arguments)).output
    return output
      .split(separator: "\n")
      .compactMap { line in
        let text = String(line)
        guard text.count > 20 else {
          return nil
        }
        let timeEnd = text.index(text.startIndex, offsetBy: 19)
        let messageStart = text.index(after: timeEnd)
        return [
          "time": String(text[..<timeEnd]),
          "message": String(text[messageStart...]),
        ]
      }
  }

  private func helperConnections(_ arguments: Any?) -> [[String: Any]] {
    if mode(from: arguments) == "openvpn" {
      return []
    }
    let limit = logsLimit(from: arguments)
    let output = runHelper(helperArguments(["connections", "\(limit)"], from: arguments)).output
    return output
      .split(separator: "\n")
      .compactMap { line in connectionFromLine(String(line)) }
  }

  private func connectionFromLine(_ line: String) -> [String: Any]? {
    var values: [String: String] = [:]
    for part in line.split(separator: "|") {
      guard let separator = part.firstIndex(of: "=") else {
        continue
      }
      let key = String(part[..<separator])
      let value = String(part[part.index(after: separator)...])
      values[key] = value
    }
    guard !values.isEmpty else {
      return nil
    }
    return [
      "lastSeen": values["lastSeen"] ?? "",
      "proto": values["proto"] ?? "",
      "source": values["source"] ?? "",
      "target": values["target"] ?? "",
      "domain": values["domain"] ?? "",
      "via": values["via"] ?? "",
      "txBytes": intFromPair(values["txBytes"]),
      "rxBytes": intFromPair(values["rxBytes"]),
      "txRate": intFromPair(values["txRate"]),
      "rxRate": intFromPair(values["rxRate"]),
      "dnsRedirect": values["dnsRedirect"] == "true",
    ]
  }

  private func installHelper(_ arguments: Any?) -> [String: Any] {
    if mode(from: arguments) == "openvpn" {
      return openVpnStatus(arguments: arguments)
    }
    guard bundledHelperPath() != nil else {
      return unsupportedStatus(
        state: "failed",
        message: "macOS helper 未安装",
        cpeHost: cpeHost(from: arguments)
      )
    }
    let run = runHelperPrivileged(["install"], useBundledHelper: true)
    if run.exitCode != 0 {
      return unsupportedStatus(
        state: "failed",
        message: run.output.isEmpty ? "助手安装失败" : run.output
      )
    }
    return statusFromPairs(
      parsePairs(runHelper(helperArguments(["status"], from: arguments)).output),
      fallbackState: "stopped"
    )
  }

  private func uninstallHelper(_ arguments: Any?) -> [String: Any] {
    if mode(from: arguments) == "openvpn" {
      return stopOpenVpn(arguments: arguments)
    }
    let run: (exitCode: Int32, output: String)
    if installedHelperAvailable() {
      run = runInstalledHelper(helperArguments(["uninstall"], from: arguments))
    } else {
      run = runHelperPrivileged(
        helperArguments(["uninstall"], from: arguments),
        useBundledHelper: true
      )
    }
    if run.exitCode != 0 {
      return statusFromPairs(
        ["state": "failed", "lastError": run.output],
        fallbackState: "failed"
      )
    }
    return statusFromPairs(
      parsePairs(runHelper(helperArguments(["status"], from: arguments)).output),
      fallbackState: "stopped"
    )
  }

  private func launchAtLoginEnabled() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentURL().path)
  }

  private func setLaunchAtLogin(_ arguments: Any?) -> Bool {
    guard
      let args = arguments as? [String: Any],
      let enabled = args["enabled"] as? Bool
    else {
      return launchAtLoginEnabled()
    }
    if enabled {
      return installLaunchAgent()
    }
    return uninstallLaunchAgent()
  }

  private func installLaunchAgent() -> Bool {
    let url = launchAgentURL()
    let payload: [String: Any] = [
      "Label": launchAgentIdentifier,
      "ProgramArguments": ["/usr/bin/open", Bundle.main.bundlePath],
      "RunAtLoad": true,
      "LimitLoadToSessionType": "Aqua",
    ]
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try PropertyListSerialization.data(
        fromPropertyList: payload,
        format: .xml,
        options: 0
      )
      try data.write(to: url, options: .atomic)
      return true
    } catch {
      return false
    }
  }

  private func uninstallLaunchAgent() -> Bool {
    let url = launchAgentURL()
    do {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      return false
    } catch {
      return launchAtLoginEnabled()
    }
  }

  private func launchAgentURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("LaunchAgents")
      .appendingPathComponent("\(launchAgentIdentifier).plist")
  }

  private func logsLimit(from arguments: Any?) -> Int {
    guard
      let args = arguments as? [String: Any],
      let rawLimit = args["limit"]
    else {
      return 80
    }
    if let limit = rawLimit as? Int {
      return max(1, min(limit, 300))
    }
    if let limit = Int("\(rawLimit)") {
      return max(1, min(limit, 300))
    }
    return 80
  }

  private func cpeHost(from arguments: Any?) -> String {
    guard
      let args = arguments as? [String: Any],
      let rawHost = args["cpeHost"] ?? args["cpe"]
    else {
      return defaultCpeHost
    }
    let host = "\(rawHost)".trimmingCharacters(in: .whitespacesAndNewlines)
    return host.isEmpty ? defaultCpeHost : host
  }

  private func mode(from arguments: Any?) -> String {
    guard
      let args = arguments as? [String: Any],
      let rawMode = args["mode"]
    else {
      return "halfRoute"
    }
    let normalized = "\(rawMode)"
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "-", with: "")
    return normalized == "openvpn" ? "openvpn" : "\(rawMode)"
  }

  private func openVpnRemoteHost(from arguments: Any?) -> String {
    guard
      let args = arguments as? [String: Any],
      let rawHost = args["openvpnRemoteHost"]
    else {
      return cpeHost(from: arguments)
    }
    let host = "\(rawHost)".trimmingCharacters(in: .whitespacesAndNewlines)
    return host.isEmpty ? cpeHost(from: arguments) : host
  }

  private func openVpnHealth(arguments: Any?) -> [String: Any] {
    let host = openVpnRemoteHost(from: arguments)
    guard findOpenVpnBinary() != nil else {
      return [
        "host": host,
        "reachable": false,
        "serviceReady": false,
        "error": "未找到 OpenVPN CLI，请安装 openvpn 或设置 SDWAN_OPENVPN_PATH",
      ]
    }
    return [
      "host": host,
      "reachable": true,
      "serviceReady": openVpnPidRunning(),
    ]
  }

  private func openVpnStatus(arguments: Any?, state overrideState: String? = nil, error: String? = nil) -> [String: Any] {
    let hasBinary = findOpenVpnBinary() != nil
    let running = openVpnPidRunning()
    let state = overrideState ?? (running ? "running" : "stopped")
    return [
      "state": state,
      "adapterName": "OpenVPN",
      "permission": hasBinary ? "ready" : "unsupported",
      "helperInstalled": hasBinary,
      "cpe": openVpnHealth(arguments: arguments),
      "txBytes": 0,
      "rxBytes": 0,
      "txRate": 0,
      "rxRate": 0,
      "txPackets": 0,
      "rxPackets": 0,
      "txDropped": 0,
      "rxDropped": 0,
      "natMisses": 0,
      "sendFailures": 0,
      "udp443Packets": 0,
      "lastError": error ?? "",
    ]
  }

  private func openVpnLogs(limit: Int) -> [[String: String]] {
    guard let text = try? String(contentsOf: openVpnLogFile(), encoding: .utf8) else {
      return []
    }
    return text
      .split(separator: "\n")
      .suffix(limit)
      .map { line in
        [
          "time": String(Date().description.prefix(19)),
          "message": String(line),
        ]
      }
  }

  private func startOpenVpn(arguments: Any?) -> [String: Any] {
    guard let binary = findOpenVpnBinary() else {
      return openVpnStatus(
        arguments: arguments,
        state: "failed",
        error: "未找到 OpenVPN CLI，请安装 openvpn 或设置 SDWAN_OPENVPN_PATH"
      )
    }
    do {
      try prepareOpenVpnRuntime(arguments: arguments)
      let command = [
        shellQuote(binary),
        "--config", shellQuote(openVpnConfigFile().path),
        "--writepid", shellQuote(openVpnPidFile().path),
        "--log", shellQuote(openVpnLogFile().path),
        "--status", shellQuote(openVpnStatusFile().path), "10",
        "--daemon", "sdwan-verge",
      ].joined(separator: " ")
      let run = runShellPrivileged(command, timeout: 60)
      if run.exitCode != 0 {
        return openVpnStatus(
          arguments: arguments,
          state: "failed",
          error: run.output.isEmpty ? "OpenVPN 启动失败" : run.output
        )
      }
      Thread.sleep(forTimeInterval: 0.8)
      return openVpnStatus(arguments: arguments, state: openVpnPidRunning() ? "running" : "failed")
    } catch {
      return openVpnStatus(arguments: arguments, state: "failed", error: error.localizedDescription)
    }
  }

  private func stopOpenVpn(arguments: Any?) -> [String: Any] {
    if let pid = openVpnPid() {
      _ = runShellPrivileged("/bin/kill \(pid) 2>/dev/null || true", timeout: 20)
    }
    try? FileManager.default.removeItem(at: openVpnPidFile())
    try? FileManager.default.removeItem(at: openVpnAuthFile())
    return openVpnStatus(arguments: arguments, state: "stopped")
  }

  private func prepareOpenVpnRuntime(arguments: Any?) throws {
    try FileManager.default.createDirectory(
      at: openVpnDirectory(),
      withIntermediateDirectories: true
    )
    if let authText = openVpnAuthText(from: arguments) {
      try authText.write(to: openVpnAuthFile(), atomically: true, encoding: .utf8)
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: openVpnAuthFile().path
      )
    }
    let config = openVpnConfigText(from: arguments, authFilePath: openVpnAuthFile().path)
    try config.write(to: openVpnConfigFile(), atomically: true, encoding: .utf8)
  }

  private func openVpnConfigText(from arguments: Any?, authFilePath: String) -> String {
    let args = arguments as? [String: Any] ?? [:]
    var lines: [String] = []
    lines.append("client")
    let tunName = "\(args["openvpnTunName"] ?? "auto")"
    lines.append("dev \(tunName == "auto" ? "tun" : tunName)")
    lines.append("proto \(args["openvpnProtocol"] ?? "udp4")")
    lines.append("remote \(openVpnRemoteHost(from: arguments)) \(args["openvpnRemotePort"] ?? 1194)")
    let redirect = "\(args["openvpnRedirectGateway"] ?? "def1")"
    if !redirect.isEmpty {
      lines.append("redirect-gateway \(redirect)")
    }
    if boolArg(args["openvpnAuthUserPass"], defaultValue: false) {
      lines.append("auth-user-pass \(openVpnConfigQuote(authFilePath))")
    }
    if boolArg(args["openvpnIpv4Only"], defaultValue: true) {
      lines.append("pull-filter ignore \"ifconfig-ipv6\"")
    }
    if boolArg(args["openvpnPullFilterIpv6"], defaultValue: true) {
      lines.append("pull-filter ignore \"route-ipv6\"")
    }
    let mtu = "\(args["openvpnMtu"] ?? "auto")"
    if mtu != "auto" {
      lines.append("tun-mtu \(mtu)")
    }
    let mssfix = "\(args["openvpnMssfix"] ?? "auto")"
    if mssfix != "auto" {
      lines.append("mssfix \(mssfix)")
    }
    if let directives = args["openvpnCustomDirectives"] as? [String] {
      for directive in directives where !isIgnoredOpenVpnDirectiveOnDarwin(directive) {
        lines.append(directive)
      }
    }
    if let blocks = args["openvpnInlineBlocks"] as? [String: String] {
      for (name, content) in blocks {
        lines.append("<\(name)>")
        lines.append(content)
        lines.append("</\(name)>")
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private func openVpnConfigQuote(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  private func isIgnoredOpenVpnDirectiveOnDarwin(_ raw: String) -> Bool {
    let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
      return false
    }
    let key = line.split { $0 == " " || $0 == "\t" }.first?.lowercased() ?? ""
    return key == "client" || key == "block-outside-dns"
  }

  private func openVpnAuthText(from arguments: Any?) -> String? {
    guard
      let args = arguments as? [String: Any],
      let username = args["openvpnUsername"] as? String,
      let password = args["openvpnPassword"] as? String
    else {
      return nil
    }
    return "\(username)\n\(password)\n"
  }

  private func findOpenVpnBinary() -> String? {
    if let env = ProcessInfo.processInfo.environment["SDWAN_OPENVPN_PATH"],
       FileManager.default.isExecutableFile(atPath: env) {
      return env
    }
    let candidates = [
      "/opt/homebrew/sbin/openvpn",
      "/opt/homebrew/bin/openvpn",
      "/usr/local/sbin/openvpn",
      "/usr/local/bin/openvpn",
      "/usr/sbin/openvpn",
      "/usr/bin/openvpn",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  private func openVpnPidRunning() -> Bool {
    guard let pid = openVpnPid() else {
      return false
    }
    return kill(pid, 0) == 0
  }

  private func openVpnPid() -> Int32? {
    guard let text = try? String(contentsOf: openVpnPidFile(), encoding: .utf8) else {
      return nil
    }
    return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private func openVpnDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SD-WAN Verge", isDirectory: true)
      .appendingPathComponent(openVpnDirName, isDirectory: true)
  }

  private func openVpnConfigFile() -> URL {
    openVpnDirectory().appendingPathComponent("client.ovpn")
  }

  private func openVpnAuthFile() -> URL {
    openVpnDirectory().appendingPathComponent("auth.txt")
  }

  private func openVpnPidFile() -> URL {
    openVpnDirectory().appendingPathComponent("openvpn.pid")
  }

  private func openVpnLogFile() -> URL {
    openVpnDirectory().appendingPathComponent("openvpn.log")
  }

  private func openVpnStatusFile() -> URL {
    openVpnDirectory().appendingPathComponent("openvpn.status")
  }

  private func boolArg(_ value: Any?, defaultValue: Bool) -> Bool {
    if let bool = value as? Bool {
      return bool
    }
    if let string = value as? String {
      return string == "true"
    }
    return defaultValue
  }

  private func helperArguments(_ base: [String], from arguments: Any?) -> [String] {
    return base + ["--cpe", cpeHost(from: arguments)]
  }

  private func intFromPair(_ value: String?) -> Int {
    Int(value ?? "") ?? 0
  }

  private func helperPath() -> String? {
    if installedHelperReady() {
      return installedHelperPath
    }
    return bundledHelperPath()
  }

  private func bundledHelperPath() -> String? {
    let bundle = Bundle.main
    if let path = bundle.path(forResource: helperName, ofType: nil),
       FileManager.default.isExecutableFile(atPath: path) {
      return path
    }
    if let path = bundle.resourceURL?.appendingPathComponent(helperName).path,
       FileManager.default.isExecutableFile(atPath: path) {
      return path
    }
    let contentsPath = bundle.bundleURL
      .appendingPathComponent("Contents")
      .appendingPathComponent("Resources")
      .appendingPathComponent(helperName)
      .path
    return FileManager.default.isExecutableFile(atPath: contentsPath) ? contentsPath : nil
  }

  private func installedHelperAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: installedHelperPath)
  }

  private func installedHelperReady() -> Bool {
    installedHelperAvailable() && !installedHelperNeedsUpdate()
  }

  private func installedHelperNeedsUpdate() -> Bool {
    guard installedHelperAvailable(), let bundled = bundledHelperPath() else {
      return false
    }
    guard
      let installedData = try? Data(contentsOf: URL(fileURLWithPath: installedHelperPath)),
      let bundledData = try? Data(contentsOf: URL(fileURLWithPath: bundled))
    else {
      return true
    }
    return installedData != bundledData
  }

  private func runHelper(_ arguments: [String]) -> (exitCode: Int32, output: String) {
    guard let helper = helperPath() else {
      return (127, "macOS helper 未安装")
    }
    return runHelper(at: helper, arguments: arguments)
  }

  private func runInstalledHelper(_ arguments: [String]) -> (exitCode: Int32, output: String) {
    guard installedHelperAvailable() else {
      return (127, "macOS helper 未安装")
    }
    return runHelper(at: installedHelperPath, arguments: arguments)
  }

  private func runHelper(
    at helper: String,
    arguments: [String]
  ) -> (exitCode: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helper)
    process.arguments = arguments
    return runProcess(process, timeout: 12)
  }

  private func runHelperPrivileged(
    _ arguments: [String],
    useBundledHelper: Bool = false
  ) -> (exitCode: Int32, output: String) {
    guard let helper = useBundledHelper ? bundledHelperPath() : helperPath() else {
      return (127, "macOS helper 未安装")
    }
    let command = ([helper] + arguments).map(shellQuote).joined(separator: " ")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [
      "-e",
      "do shell script \"\(appleScriptEscape(command))\" with administrator privileges",
    ]
    return runProcess(process, timeout: 180)
  }

  private func runShellPrivileged(
    _ command: String,
    timeout: TimeInterval
  ) -> (exitCode: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = [
      "-e",
      "do shell script \"\(appleScriptEscape(command))\" with administrator privileges",
    ]
    return runProcess(process, timeout: timeout)
  }

  private func runProcess(
    _ process: Process,
    timeout: TimeInterval
  ) -> (exitCode: Int32, output: String) {
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("sdwan-helper-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
      return (126, "无法创建 helper 输出文件")
    }
    process.standardOutput = outputHandle
    process.standardError = outputHandle
    do {
      try process.run()
    } catch {
      try? outputHandle.close()
      try? FileManager.default.removeItem(at: outputURL)
      return (126, error.localizedDescription)
    }

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
      process.terminate()
      Thread.sleep(forTimeInterval: 0.2)
    }
    try? outputHandle.close()
    let data = (try? Data(contentsOf: outputURL)) ?? Data()
    try? FileManager.default.removeItem(at: outputURL)
    let output = String(data: data, encoding: .utf8) ?? ""
    if process.isRunning {
      return (124, output.isEmpty ? "helper 执行超时" : output)
    }
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
