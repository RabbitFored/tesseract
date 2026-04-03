package com.struthio.tesseract

import android.media.MediaScannerConnection
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "tesseract/media_scanner"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    MediaScannerConnection.scanFile(
                        this,
                        arrayOf(path),
                        null,
                        null
                    )
                    result.success(null)
                } else {
                    result.error("INVALID_ARGS", "Path is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
