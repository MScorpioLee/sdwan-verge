import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let tunChannelName = "sdwan_client/tun"
  private let defaultCpeHost = "192.168.1.140"

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
      result(unsupportedStatus())
    case "healthCheck":
      result(unavailableHealth())
    case "start":
      result(
        unsupportedStatus(
          state: "failed",
          message: "macOS Packet Tunnel 后端尚未接入"
        )
      )
    case "stop":
      result(unsupportedStatus())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func unsupportedStatus(
    state: String = "stopped",
    message: String = "macOS Packet Tunnel 后端尚未接入"
  ) -> [String: Any] {
    [
      "state": state,
      "permission": "unsupported",
      "cpe": unavailableHealth(),
      "lastError": message,
    ]
  }

  private func unavailableHealth() -> [String: Any] {
    [
      "host": defaultCpeHost,
      "reachable": false,
      "serviceReady": false,
      "error": "TUN 原生服务尚未接入",
    ]
  }
}
