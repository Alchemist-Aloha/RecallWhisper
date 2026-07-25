package com.recallwhisper.recall_whisper.recording

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class VadContextTest {
    @Test
    fun prependsPreviousFrameTailAndResetsIt() {
        val context = VadContext(2)
        val first = context.prepend(shortArrayOf(1, 2, 3))
        assertArrayEquals(floatArrayOf(0f, 0f, 1 / 32768f, 2 / 32768f, 3 / 32768f), first, 0f)

        val second = context.prepend(shortArrayOf(4, 5, 6))
        assertArrayEquals(floatArrayOf(2 / 32768f, 3 / 32768f, 4 / 32768f, 5 / 32768f, 6 / 32768f), second, 0f)

        context.reset()
        assertArrayEquals(
            floatArrayOf(0f, 0f, 7 / 32768f, 8 / 32768f, 9 / 32768f),
            context.prepend(shortArrayOf(7, 8, 9)),
            0f,
        )
    }
}
