package com.example.resq

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity registers two Flutter ↔ Kotlin bridges:
 *
 *   MethodChannel  "resq/gemma"
 *     • initialize(modelPath: String) → Boolean
 *     • isReady()                     → Boolean
 *
 *   EventChannel   "resq/gemma_stream"
 *     • Emits each token as a String while generating
 *     • Emits null as the final event (signals completion)
 */
class MainActivity : FlutterActivity() {

    private val engine by lazy { GemmaEngine(this) }
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val METHOD_CHANNEL  = "resq/gemma"
        private const val EVENT_CHANNEL   = "resq/gemma_stream"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── MethodChannel ────────────────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "initialize" -> {
                    val modelPath = call.argument<String>("modelPath")
                    if (modelPath == null) {
                        result.error("INVALID_ARG", "modelPath is required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            engine.initialize(modelPath)
                            mainHandler.post { result.success(true) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("INIT_FAILED", e.message, null)
                            }
                        }
                    }.start()
                }

                "isReady" -> result.success(engine.isInitialized)

                else -> result.notImplemented()
            }
        }

        // ── EventChannel ─────────────────────────────────────────────────────
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {

            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val prompt = (arguments as? String) ?: run {
                    events.error("INVALID_ARG", "Prompt string required", null)
                    return
                }
                if (!engine.isInitialized) {
                    events.error("NOT_READY", "Model not initialised", null)
                    return
                }

                Thread {
                    try {
                        engine.generate(prompt) { token, done ->
                            mainHandler.post {
                                if (!done) {
                                    events.success(token)
                                } else {
                                    events.endOfStream()
                                }
                            }
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            events.error("GENERATE_FAILED", e.message, null)
                        }
                    }
                }.start()
            }

            override fun onCancel(arguments: Any?) {
                // Stream cancelled by Flutter side — nothing to do.
            }
        })
    }

    override fun onDestroy() {
        engine.close()
        super.onDestroy()
    }
}
