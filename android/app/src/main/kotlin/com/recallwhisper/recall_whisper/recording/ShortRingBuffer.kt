package com.recallwhisper.recall_whisper.recording

class ShortRingBuffer(private val capacity: Int) {
    private val values = ShortArray(capacity)
    private var next = 0
    private var size = 0

    fun add(input: ShortArray) {
        for (value in input) {
            values[next] = value
            next = (next + 1) % capacity
            if (size < capacity) size++
        }
    }

    fun snapshot(): ShortArray {
        val output = ShortArray(size)
        val first = (next - size + capacity) % capacity
        for (index in output.indices) output[index] = values[(first + index) % capacity]
        return output
    }

    fun clear() {
        next = 0
        size = 0
    }
}
