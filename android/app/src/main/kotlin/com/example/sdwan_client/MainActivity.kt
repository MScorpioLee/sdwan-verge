package com.example.sdwan_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL

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
                "status" -> result.success(unsupportedStatus(host = cpeHost(call.arguments)))
                "healthCheck" -> result.success(unavailableHealth(cpeHost(call.arguments)))
                "logs" -> result.success(emptyList<Map<String, Any>>())
                "connections" -> result.success(emptyList<Map<String, Any>>())
                "installHelper" -> result.success(
                    unsupportedStatus(
                        state = "failed",
                        message = "Android VpnService 后端尚未接入",
                        host = cpeHost(call.arguments),
                    ),
                )
                "uninstallHelper" -> result.success(
                    unsupportedStatus(host = cpeHost(call.arguments)),
                )
                "start" -> result.success(
                    unsupportedStatus(
                        state = "failed",
                        message = "Android VpnService 后端尚未接入",
                        host = cpeHost(call.arguments),
                    ),
                )
                "stop" -> result.success(unsupportedStatus(host = cpeHost(call.arguments)))
                "launchAtLoginStatus" -> result.success(false)
                "setLaunchAtLogin" -> result.success(false)
                "probeLatency" -> probeLatency(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun unsupportedStatus(
        state: String = "stopped",
        message: String = "Android VpnService 后端尚未接入",
        host: String = defaultCpeHost,
    ): Map<String, Any> = mapOf(
        "state" to state,
        "permission" to "unsupported",
        "cpe" to unavailableHealth(host),
        "helperInstalled" to false,
        "txBytes" to 0,
        "rxBytes" to 0,
        "txRate" to 0,
        "rxRate" to 0,
        "lastError" to message,
    )

    private fun unavailableHealth(host: String = defaultCpeHost): Map<String, Any> = mapOf(
        "host" to host,
        "reachable" to false,
        "serviceReady" to false,
        "error" to "TUN 原生服务尚未接入",
    )

    @Suppress("UNCHECKED_CAST")
    private fun cpeHost(arguments: Any?): String {
        val map = arguments as? Map<String, Any?> ?: return defaultCpeHost
        return map["cpeHost"]?.toString()?.takeIf { it.isNotBlank() } ?: defaultCpeHost
    }

    @Suppress("UNCHECKED_CAST")
    private fun probeLatency(arguments: Any?, result: MethodChannel.Result) {
        val map = arguments as? Map<String, Any?> ?: emptyMap()
        val url = map["url"]?.toString()?.trim().orEmpty()
        val timeoutMs = (map["timeoutMs"] as? Number)?.toInt() ?: 5000
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            result.success(latencyFailure("invalid url"))
            return
        }

        Thread {
            val started = System.currentTimeMillis()
            var connection: HttpURLConnection? = null
            try {
                connection = URL(url).openConnection() as HttpURLConnection
                connection.connectTimeout = timeoutMs
                connection.readTimeout = timeoutMs
                connection.instanceFollowRedirects = true
                connection.setRequestProperty("User-Agent", "SD-WAN Verge")
                connection.setRequestProperty("Connection", "close")
                val code = connection.responseCode
                val latencyMs = (System.currentTimeMillis() - started).toInt()
                val value = if (code in 200..499) {
                    mapOf(
                        "status" to "success",
                        "latencyMs" to latencyMs,
                    )
                } else {
                    latencyFailure("HTTP $code")
                }
                runOnUiThread { result.success(value) }
            } catch (_: SocketTimeoutException) {
                runOnUiThread { result.success(mapOf("status" to "timeout")) }
            } catch (error: Exception) {
                runOnUiThread { result.success(latencyFailure(error.message ?: error.toString())) }
            } finally {
                connection?.disconnect()
            }
        }.start()
    }

    private fun latencyFailure(error: String): Map<String, Any> = mapOf(
        "status" to "failed",
        "error" to error,
    )
}
