package com.vyamit.mykirana

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.media.AudioManager
import android.os.Build

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.vyamit.mykirana/volume"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "muteSystemSounds" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            audioManager.adjustStreamVolume(AudioManager.STREAM_SYSTEM, AudioManager.ADJUST_MUTE, 0)
                            audioManager.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_MUTE, 0)
                        } else {
                            @Suppress("DEPRECATION")
                            audioManager.setStreamMute(AudioManager.STREAM_SYSTEM, true)
                            @Suppress("DEPRECATION")
                            audioManager.setStreamMute(AudioManager.STREAM_NOTIFICATION, true)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "Unknown error", null)
                    }
                }
                "unmuteSystemSounds" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            audioManager.adjustStreamVolume(AudioManager.STREAM_SYSTEM, AudioManager.ADJUST_UNMUTE, 0)
                            audioManager.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_UNMUTE, 0)
                        } else {
                            @Suppress("DEPRECATION")
                            audioManager.setStreamMute(AudioManager.STREAM_SYSTEM, false)
                            @Suppress("DEPRECATION")
                            audioManager.setStreamMute(AudioManager.STREAM_NOTIFICATION, false)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "Unknown error", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}

