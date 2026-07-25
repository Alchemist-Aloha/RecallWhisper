package com.recallwhisper.recall_whisper.recording

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import java.nio.FloatBuffer
import java.nio.LongBuffer

class SileroVad(context: Context) : AutoCloseable {
    private val environment = OrtEnvironment.getEnvironment()
    private val session: OrtSession
    private val contextWindow = VadContext(CONTEXT_SAMPLES)
    private var state = Array(2) { Array(1) { FloatArray(128) } }

    init {
        val model = context.assets.open("silero_vad.onnx").use { it.readBytes() }
        val options = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(1)
            setInterOpNumThreads(1)
        }
        session = environment.createSession(model, options)
    }

    fun probability(pcm: ShortArray): Float {
        require(pcm.size == FRAME_SAMPLES)
        val samples = contextWindow.prepend(pcm)
        OnnxTensor.createTensor(
            environment,
            FloatBuffer.wrap(samples),
            longArrayOf(1, samples.size.toLong()),
        ).use { input ->
            OnnxTensor.createTensor(environment, state).use { memory ->
                OnnxTensor.createTensor(
                    environment,
                    LongBuffer.wrap(longArrayOf(SAMPLE_RATE.toLong())),
                    longArrayOf(),
                ).use { rate ->
                    session.run(mapOf("input" to input, "state" to memory, "sr" to rate)).use {
                        val probability = (it.get("output").orElseThrow().value
                            as Array<FloatArray>)[0][0]
                        @Suppress("UNCHECKED_CAST")
                        state = it.get("stateN").orElseThrow().value
                            as Array<Array<FloatArray>>
                        return probability
                    }
                }
            }
        }
    }

    fun reset() {
        state = Array(2) { Array(1) { FloatArray(128) } }
        contextWindow.reset()
    }

    override fun close() = session.close()

    companion object {
        const val SAMPLE_RATE = 16_000
        const val FRAME_SAMPLES = 512
        const val CONTEXT_SAMPLES = 64
    }
}

class VadContext(private val size: Int) {
    private val previous = FloatArray(size)

    fun prepend(pcm: ShortArray): FloatArray {
        val input = FloatArray(size + pcm.size)
        previous.copyInto(input)
        for (index in pcm.indices) input[size + index] = pcm[index] / 32768f
        for (index in previous.indices) {
            previous[index] = pcm[pcm.size - size + index] / 32768f
        }
        return input
    }

    fun reset() = previous.fill(0f)
}
