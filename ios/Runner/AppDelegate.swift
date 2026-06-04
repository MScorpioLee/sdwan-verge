import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let tunChannelName = "sdwan_client/tun"
  private let defaultCpeHost = "192.168.1.140"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: tunChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler(handleTunCall)
  }

  private func handleTunCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(unsupportedStatus(host: cpeHost(from: call.arguments)))
    case "healthCheck":
      result(unavailableHealth(host: cpeHost(from: call.arguments)))
    case "logs":
      result([])
    case "connections":
      result([])
    case "installHelper":
      result(
        unsupportedStatus(
          state: "failed",
          message: "iOS Packet Tunnel 后端尚未接入",
          host: cpeHost(from: call.arguments)
        )
      )
    case "uninstallHelper":
      result(unsupportedStatus(host: cpeHost(from: call.arguments)))
    case "start":
      result(
        unsupportedStatus(
          state: "failed",
          message: "iOS Packet Tunnel 后端尚未接入",
          host: cpeHost(from: call.arguments)
        )
      )
    case "stop":
      result(unsupportedStatus(host: cpeHost(from: call.arguments)))
    case "launchAtLoginStatus":
      result(false)
    case "setLaunchAtLogin":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func unsupportedStatus(
    state: String = "stopped",
    message: String = "iOS Packet Tunnel 后端尚未接入",
    host: String? = nil
  ) -> [String: Any] {
    return [
      "state": state,
      "permission": "unsupported",
      "cpe": unavailableHealth(host: host),
      "helperInstalled": false,
      "txBytes": 0,
      "rxBytes": 0,
      "txRate": 0,
      "rxRate": 0,
      "lastError": message,
    ]
  }

  private func unavailableHealth(host: String? = nil) -> [String: Any] {
    let resolvedHost = host ?? defaultCpeHost
    return [
      "host": resolvedHost,
      "reachable": false,
      "serviceReady": false,
      "error": "TUN 原生服务尚未接入",
    ]
  }

  private func cpeHost(from arguments: Any?) -> String {
    guard
      let map = arguments as? [String: Any],
      let value = map["cpeHost"] as? String,
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return defaultCpeHost
    }
    return value
  }
}
