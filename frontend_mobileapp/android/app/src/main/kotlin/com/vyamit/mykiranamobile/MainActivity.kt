package com.vyamit.mykiranamobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.vyamit.mykiranamobile.voice.AecSpeechCapture

class MainActivity : FlutterActivity() {
    private val aecCaptureChannel = "com.vyamit.mykirana/aec_speech_capture"
    private var aecSpeechCapture: AecSpeechCapture? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, aecCaptureChannel)
        val capture = AecSpeechCapture(this) { method, arguments ->
            channel.invokeMethod(method, arguments)
        }
        aecSpeechCapture = capture
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getAecCaptureSupport" -> result.success(capture.support())
                    "startAecCapture" -> result.success(capture.start())
                    "stopAecCapture" -> {
                        capture.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("AEC_CAPTURE_ERROR", error.message ?: "AEC capture failed", null)
            }
        }
    }

    override fun onDestroy() {
        aecSpeechCapture?.stop()
        aecSpeechCapture = null
        super.onDestroy()
    }
}
