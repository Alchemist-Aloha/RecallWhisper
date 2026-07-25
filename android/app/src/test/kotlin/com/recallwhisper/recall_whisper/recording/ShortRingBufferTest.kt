package com.recallwhisper.recall_whisper.recording

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class ShortRingBufferTest {
    @Test
    fun keepsNewestValuesInOrderAcrossWraparound() {
        val ring = ShortRingBuffer(5)
        ring.add(shortArrayOf(1, 2, 3))
        assertArrayEquals(shortArrayOf(1, 2, 3), ring.snapshot())
        ring.add(shortArrayOf(4, 5, 6, 7))
        assertArrayEquals(shortArrayOf(3, 4, 5, 6, 7), ring.snapshot())
    }
}
