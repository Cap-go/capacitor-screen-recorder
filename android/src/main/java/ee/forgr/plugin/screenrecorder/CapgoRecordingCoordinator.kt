package ee.forgr.plugin.screenrecorder

internal object CapgoRecordingCoordinator {
    private val lock = Any()

    @Volatile
    private var active = false

    fun tryAcquire(): Boolean = synchronized(lock) {
        if (active) {
            false
        } else {
            active = true
            true
        }
    }

    fun release() {
        synchronized(lock) {
            active = false
        }
    }
}
