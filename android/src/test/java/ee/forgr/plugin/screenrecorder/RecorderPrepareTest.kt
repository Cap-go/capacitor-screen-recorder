package ee.forgr.plugin.screenrecorder

import android.media.MediaRecorder
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mockito.Mockito.doThrow
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify

class VideoSizeResolverTest {
    @Test
    fun alignDimensionsToRotation_swapsWhenLandscapeRotationWithPortraitMetrics() {
        val (width, height) = VideoSizeResolver.alignDimensionsToRotation(1080, 1920, 1)
        assertEquals(1920, width)
        assertEquals(1080, height)
    }

    @Test
    fun alignDimensionsToRotation_swapsWhenPortraitRotationWithLandscapeMetrics() {
        val (width, height) = VideoSizeResolver.alignDimensionsToRotation(1920, 1080, 0)
        assertEquals(1080, width)
        assertEquals(1920, height)
    }

    @Test
    fun alignDimensionsToRotation_keepsWhenAlreadyAligned() {
        val (width, height) = VideoSizeResolver.alignDimensionsToRotation(1920, 1080, 1)
        assertEquals(1920, width)
        assertEquals(1080, height)
    }

    @Test
    fun clamp_makesOddDimensionsEven() {
        val (width, height) = VideoSizeResolver.clamp(801, 601)
        assertEquals(800, width)
        assertEquals(600, height)
    }

    @Test
    fun clamp_scalesDownTo1080p() {
        val (width, height) = VideoSizeResolver.clamp(1440, 3200)
        assertEquals(486, width)
        assertEquals(1080, height)
        assertEquals(0, width % 2)
        assertEquals(0, height % 2)
    }
}

class MediaRecorderPrepareTest {
    @Test
    fun tryPrepare_returnsNullOnSuccess() {
        val recorder = mock(MediaRecorder::class.java)
        assertNull(MediaRecorderPrepare.tryPrepare(recorder))
        verify(recorder).prepare()
    }

    @Test
    fun tryPrepare_returnsIOExceptionWithoutThrowing() {
        val recorder = mock(MediaRecorder::class.java)
        val error = IOException("prepare failed")
        doThrow(error).`when`(recorder).prepare()

        val result = MediaRecorderPrepare.tryPrepare(recorder)

        assertEquals(error, result)
    }
}
