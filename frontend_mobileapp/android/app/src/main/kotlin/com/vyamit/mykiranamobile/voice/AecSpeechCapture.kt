package com.vyamit.mykiranamobile.voice

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Android 13+ capture path for Token Saver. It sends only recognized text to
 * Flutter; raw PCM stays inside this process and is never logged or persisted.
 */
class AecSpeechCapture(
    private val context: Context,
    private val emit: (String, Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val sampleRate = 16_000
        private const val channelCount = 1
        private const val frameBytes = sampleRate * 20 / 1_000 * 2
        private const val errorAudio = 3
        private const val errorClient = 5
        private const val errorPermission = 9
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var recorder: AudioRecord? = null
    private var aec: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var autoGainControl: AutomaticGainControl? = null
    private var recognizerInput: ParcelFileDescriptor? = null
    private var recorderOutput: ParcelFileDescriptor.AutoCloseOutputStream? = null
    private var captureExecutor: ExecutorService? = null
    private var running = false
    private var generation = 0
    private var lastRmsEventAt = 0L

    fun support(): Map<String, Any> = mapOf(
        "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            SpeechRecognizer.isRecognitionAvailable(context)),
        "api_level" to Build.VERSION.SDK_INT,
        "aec_available" to AcousticEchoCanceler.isAvailable(),
        "noise_suppression_available" to NoiseSuppressor.isAvailable(),
        "auto_gain_control_available" to AutomaticGainControl.isAvailable(),
    )

    fun start(): Map<String, Any> {
        if (running) return settings(started = true)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            !SpeechRecognizer.isRecognitionAvailable(context)
        ) return settings(started = false)

        return try {
            val runGeneration = ++generation
            val audioRecord = createAudioRecord()
            if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord.release()
                return settings(started = false)
            }
            recorder = audioRecord
            attachEffects(audioRecord)
            val pipe = ParcelFileDescriptor.createPipe()
            recognizerInput = pipe[0]
            recorderOutput = ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])
            val speechRecognizer = createRecognizer()
            recognizer = speechRecognizer
            speechRecognizer.setRecognitionListener(listener(runGeneration))
            running = true
            speechRecognizer.startListening(recognizerIntent(recognizerInput!!))
            audioRecord.startRecording()
            startCaptureLoop(runGeneration, audioRecord)
            emitOnMain("speechStatus", mapOf("status" to "listening"))
            settings(started = true)
        } catch (_: Exception) {
            stopInternal(emitStatus = false)
            settings(started = false)
        }
    }

    fun stop() = stopInternal(emitStatus = true)

    private fun createAudioRecord(): AudioRecord {
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(sampleRate)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()
        val minimumBuffer = AudioRecord.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        return AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
            .setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(minimumBuffer, frameBytes * 10))
            .build()
    }

    private fun attachEffects(audioRecord: AudioRecord) {
        aec = AcousticEchoCanceler.create(audioRecord.audioSessionId)?.also { it.setEnabled(true) }
        noiseSuppressor = NoiseSuppressor.create(audioRecord.audioSessionId)?.also { it.setEnabled(true) }
        autoGainControl = AutomaticGainControl.create(audioRecord.audioSessionId)?.also { it.setEnabled(true) }
    }

    private fun createRecognizer(): SpeechRecognizer =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        ) SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        else SpeechRecognizer.createSpeechRecognizer(context)

    private fun recognizerIntent(input: ParcelFileDescriptor): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, input)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, channelCount)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, sampleRate)
        }

    private fun listener(runGeneration: Int): RecognitionListener {
        fun current() = running && runGeneration == generation
        return object : RecognitionListener {
            override fun onReadyForSpeech(params: android.os.Bundle?) = Unit
            override fun onBeginningOfSpeech() {
                if (current()) emitOnMain("speechStatus", mapOf("status" to "speech_start"))
            }
            override fun onRmsChanged(rmsdB: Float) {
                val now = System.currentTimeMillis()
                if (current() && now - lastRmsEventAt >= 100) {
                    lastRmsEventAt = now
                    emitOnMain("soundLevel", mapOf("level" to rmsdB.toDouble()))
                }
            }
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit
            override fun onError(error: Int) {
                if (!current()) return
                emitOnMain("speechError", mapOf(
                    "code" to error,
                    "fatal" to (error == errorAudio || error == errorClient || error == errorPermission),
                ))
                stopInternal(emitStatus = false)
            }
            override fun onResults(results: android.os.Bundle?) {
                if (!current()) return
                emitResult(results, isFinal = true)
                stopInternal(emitStatus = false)
                emitOnMain("speechStatus", mapOf("status" to "done"))
            }
            override fun onPartialResults(partialResults: android.os.Bundle?) {
                if (current()) emitResult(partialResults, isFinal = false)
            }
            override fun onEvent(eventType: Int, params: android.os.Bundle?) = Unit
        }
    }

    private fun emitResult(bundle: android.os.Bundle?, isFinal: Boolean) {
        val text = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()?.trim().orEmpty()
        if (text.isNotEmpty()) {
            emitOnMain("speechResult", mapOf("recognizedWords" to text, "finalResult" to isFinal))
        }
    }

    private fun startCaptureLoop(runGeneration: Int, audioRecord: AudioRecord) {
        val output = recorderOutput ?: return
        val executor = Executors.newSingleThreadExecutor()
        captureExecutor = executor
        executor.execute {
            val frame = ByteArray(frameBytes)
            try {
                while (running && runGeneration == generation) {
                    val read = audioRecord.read(frame, 0, frame.size)
                    if (read > 0) output.write(frame, 0, read)
                    else if (read < 0) {
                        emitOnMain("speechError", mapOf("code" to errorAudio, "fatal" to true))
                        break
                    }
                }
            } catch (_: IOException) {
                // The recognizer closes the pipe on a completed or cancelled turn.
            } finally {
                try { output.close() } catch (_: IOException) {}
            }
        }
    }

    private fun stopInternal(emitStatus: Boolean) {
        if (!running && recognizer == null && recorder == null) return
        running = false
        generation += 1
        captureExecutor?.shutdownNow()
        captureExecutor = null
        try { recorderOutput?.close() } catch (_: IOException) {}
        recorderOutput = null
        recognizerInput?.close()
        recognizerInput = null
        recorder?.let { audioRecord ->
            try { audioRecord.stop() } catch (_: IllegalStateException) {}
            audioRecord.release()
        }
        recorder = null
        aec?.release(); aec = null
        noiseSuppressor?.release(); noiseSuppressor = null
        autoGainControl?.release(); autoGainControl = null
        recognizer?.let { speechRecognizer ->
            try { speechRecognizer.cancel() } catch (_: Exception) {}
            speechRecognizer.destroy()
        }
        recognizer = null
        if (emitStatus) emitOnMain("speechStatus", mapOf("status" to "stopped"))
    }

    private fun settings(started: Boolean): Map<String, Any> = mapOf(
        "started" to started,
        "aec_attached" to (aec?.getEnabled() == true && aec?.hasControl() == true),
        "noise_suppression_attached" to
            (noiseSuppressor?.getEnabled() == true && noiseSuppressor?.hasControl() == true),
        "auto_gain_control_attached" to
            (autoGainControl?.getEnabled() == true && autoGainControl?.hasControl() == true),
    )

    private fun emitOnMain(method: String, arguments: Map<String, Any?>) {
        mainHandler.post { emit(method, arguments) }
    }
}
