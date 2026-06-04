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
      result(unsupportedStatus())
    case "healthCheck":
      result(unavailableHealth())
    case "start":
      result(
        unsupportedStatus(
          state: "failed",
          message: "iOS Packet Tunnel 后端尚未接入"
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
    message: String = "iOS Packet Tunnel 后端尚未接入"
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
