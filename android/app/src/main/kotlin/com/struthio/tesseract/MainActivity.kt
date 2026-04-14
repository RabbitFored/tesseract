package com.struthio.tesseract

import android.media.MediaScannerConnection
import android.os.Build
import android.os.PowerManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Timer
import java.util.TimerTask

class MainActivity : FlutterActivity() {
    private val MEDIA_SCANNER_CHANNEL = "tesseract/media_scanner"
    private val THERMAL_CHANNEL = "tesseract/thermal"

    private var thermalEventSink: EventChannel.EventSink? = null
    private var thermalTimer: Timer? = null
    private var thermalListener: Any? = null // PowerManager.OnThermalStatusChangedListener (API 29+)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Media scanner channel ──────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SCANNER_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGS", "Path is null", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // ── Thermal state event channel ────────────────────────────────
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            THERMAL_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                thermalEventSink = events
                startThermalMonitoring()
            }

            override fun onCancel(arguments: Any?) {
                stopThermalMonitoring()
                thermalEventSink = null
            }
        })
    }

    private fun startThermalMonitoring() {
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // API 29+: use the proper thermal status listener.
            val listener = PowerManager.OnThermalStatusChangedListener { status ->
                // THERMAL_STATUS_SEVERE = 5, THERMAL_STATUS_CRITICAL = 6,
                // THERMAL_STATUS_EMERGENCY = 7, THERMAL_STATUS_SHUTDOWN = 8
                val isHigh = status >= PowerManager.THERMAL_STATUS_SEVERE
                thermalEventSink?.success(isHigh)
            }
            pm.addThermalStatusListener(mainExecutor, listener)
            thermalListener = listener

            // Emit the current state immediately on subscribe.
            val currentStatus = pm.currentThermalStatus
            val isHigh = currentStatus >= PowerManager.THERMAL_STATUS_SEVERE
            thermalEventSink?.success(isHigh)
        } else {
            // API < 29: poll isPowerSaveMode as a rough proxy for thermal stress.
            thermalTimer = Timer().also { timer ->
                timer.scheduleAtFixedRate(object : TimerTask() {
                    override fun run() {
                        val isHigh = pm.isPowerSaveMode
                        runOnUiThread { thermalEventSink?.success(isHigh) }
                    }
                }, 0L, 30_000L) // poll every 30 seconds
            }
        }
    }

    private fun stopThermalMonitoring() {
        thermalTimer?.cancel()
        thermalTimer = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val pm = getSystemService(POWER_SERVICE) as? PowerManager
            @Suppress("UNCHECKED_CAST")
            val listener = thermalListener as? PowerManager.OnThermalStatusChangedListener
            if (pm != null && listener != null) {
                pm.removeThermalStatusListener(listener)
            }
            thermalListener = null
        }
    }

    override fun onDestroy() {
        stopThermalMonitoring()
        super.onDestroy()
    }
}
