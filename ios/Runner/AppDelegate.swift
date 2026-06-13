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
    case "probeLatency":
      probeLatency(arguments: call.arguments, result: result)
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

  private func probeLatency(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    guard
      let rawUrl = args["url"] as? String,
      let url = URL(string: rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme == "http" || url.scheme == "https"
    else {
      result(latencyFailure("invalid url"))
      return
    }

    let timeoutMs = timeoutMilliseconds(from: args["timeoutMs"])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = max(1, timeoutMs / 1000.0)
    configuration.timeoutIntervalForResource = max(1, timeoutMs / 1000.0)
    let session = URLSession(configuration: configuration)
    var request = URLRequest(url: url)
    request.setValue("SD-WAN Verge", forHTTPHeaderField: "User-Agent")
    request.setValue("close", forHTTPHeaderField: "Connection")
    let started = Date()

    session.dataTask(with: request) { _, response, error in
      defer {
        session.finishTasksAndInvalidate()
      }

      let value: [String: Any]
      if let error = error as NSError? {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
          value = ["status": "timeout"]
        } else {
          value = self.latencyFailure(error.localizedDescription)
        }
      } else if let http = response as? HTTPURLResponse {
        if (200..<500).contains(http.statusCode) {
          value = [
            "status": "success",
            "latencyMs": Int(Date().timeIntervalSince(started) * 1000),
          ]
        } else {
          value = self.latencyFailure("HTTP \(http.statusCode)")
        }
      } else {
        value = self.latencyFailure("invalid response")
      }

      DispatchQueue.main.async {
        result(value)
      }
    }.resume()
  }

  private func latencyFailure(_ error: String) -> [String: Any] {
    return [
      "status": "failed",
      "error": error,
    ]
  }

  private func timeoutMilliseconds(from value: Any?) -> Double {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let text = value as? String, let number = Double(text) {
      return number
    }
    return 5000
  }
}
