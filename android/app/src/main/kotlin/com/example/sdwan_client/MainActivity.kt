package com.example.sdwan_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val tunChannelName = "sdwan_client/tun"
    private val defaultCpeHost = "192.168.1.140"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            tunChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(unsupportedStatus())
                "healthCheck" -> result.success(unavailableHealth())
                "start" -> result.success(
                    unsupportedStatus(
                        state = "failed",
                        message = "Android VpnService 后端尚未接入",
                    ),
                )
                "stop" -> result.success(unsupportedStatus())
                else -> result.notImplemented()
            }
        }
    }

    private fun unsupportedStatus(
        state: String = "stopped",
        message: String = "Android VpnService 后端尚未接入",
    ): Map<String, Any> = mapOf(
        "state" to state,
        "permission" to "unsupported",
        "cpe" to unavailableHealth(),
        "lastError" to message,
    )

    private fun unavailableHealth(): Map<String, Any> = mapOf(
        "host" to defaultCpeHost,
        "reachable" to false,
        "serviceReady" to false,
        "error" to "TUN 原生服务尚未接入",
    )
}
