package com.panpal.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.panpal.app/foreground"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    val title = call.argument<String>("title") ?: "初眠网盘运行中"
                    val body = call.argument<String>("body") ?: "本地HTTP服务器正在运行"
                    ChumianDriveForegroundService.start(this, title, body)
                    result.success(null)
                }
                "stopForeground" -> {
                    ChumianDriveForegroundService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
