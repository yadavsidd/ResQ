package com.example.resq

import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference

/**
 * GemmaEngine wraps the MediaPipe LLM Inference SDK.
 *
 * The model file (gemma-4-e2b.tflite) lives at the path returned by
 * Flutter's getApplicationDocumentsDirectory().
 *
 * Usage:
 *   val engine = GemmaEngine(context)
 *   engine.initialize(modelPath)               // call once; blocking ~5–15s
 *   engine.generate(prompt) { token, done -> } // streaming callback
 *   engine.close()                             // free GPU memory
 */
class GemmaEngine(private val context: Context) {

    private var llmInference: LlmInference? = null

    /**
     * Loads the model from [modelPath] onto the GPU (falls back to CPU).
     * Throws on failure so the caller can surface the error to Flutter.
     */
    fun initialize(modelPath: String) {
        // Release any previously loaded model first.
        llmInference?.close()
        llmInference = null

        val options = LlmInference.LlmInferenceOptions.builder()
            .setModelPath(modelPath)
            .setMaxTokens(1024)
            .build()

        llmInference = LlmInference.createFromOptions(context, options)
    }

    /**
     * Runs streaming inference.
     * [onPartialResult] is invoked on each token; when [done] is true the
     * generation is complete.
     */
    fun generate(prompt: String, onPartialResult: (token: String, done: Boolean) -> Unit) {
        val engine = llmInference
            ?: throw IllegalStateException("GemmaEngine not initialised — call initialize() first.")
        engine.generateResponseAsync(prompt, onPartialResult)
    }

    val isInitialized: Boolean get() = llmInference != null

    fun close() {
        llmInference?.close()
        llmInference = null
    }
}
