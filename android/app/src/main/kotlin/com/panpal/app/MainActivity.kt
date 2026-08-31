package com.panpal.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import com.gopeed.libgopeed.Libgopeed

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.panpal.app/gopeed"
    private var gopeedStarted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startGopeed" -> {
                    try {
                        if (!gopeedStarted) {
                            val storageDir = filesDir.absolutePath + "/gopeed"
                            val config = JSONObject()
                            config.put("network", "tcp")
                            config.put("address", "127.0.0.1:0")
                            config.put("storage", storageDir)
                            config.put("productionMode", true)
                            val port = Libgopeed.start(config.toString())
                            gopeedStarted = true
                            result.success(port)
                        } else {
                            result.success(0)
                        }
                    } catch (e: Exception) {
                        result.error("GOPEED_START_FAILED", e.message, null)
                    }
                }
                "stopGopeed" -> {
                    try {
                        if (gopeedStarted) {
                            Libgopeed.stop()
                            gopeedStarted = false
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("GOPEED_STOP_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try {
            if (gopeedStarted) {
                Libgopeed.Stop()
                gopeedStarted = false
            }
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
