/**
 * Capacitor Screen Recorder Plugin for recording the device screen.
 * Allows you to capture video recordings of the screen with optional audio.
 *
 * @since 1.0.0
 */
export interface ScreenRecorderPlugin {
  /**
   * Start recording the device screen.
   *
   * Initiates screen recording with optional audio capture. The user will be
   * prompted to grant screen recording permissions if not already granted.
   * On iOS, the system recording UI will be displayed. On Android, the recording
   * starts immediately after permission is granted.
   *
   * @param options - Recording configuration options
   * @param options.recordAudio - Whether to record audio along with the screen video. Defaults to false.
   * @returns Promise that resolves when recording starts
   * @throws Error if recording fails to start or permissions are denied
   * @since 1.0.0
   * @example
   * ```typescript
   * // Start recording without audio
   * await ScreenRecorder.start();
   *
   * // Start recording with audio
   * await ScreenRecorder.start({ recordAudio: true });
   * ```
   */
  start(options?: { recordAudio?: boolean }): Promise<void>;

  /**
   * Stop the current screen recording.
   *
   * Stops the active screen recording and saves the video to the device's
   * camera roll or gallery. On iOS, the system will show a preview of the
   * recording. On Android, the video is saved directly to the gallery.
   *
   * @returns Promise that resolves when recording stops and the video is saved
   * @throws Error if stopping the recording fails or no recording is active
   * @since 1.0.0
   * @example
   * ```typescript
   * await ScreenRecorder.stop();
   * console.log('Recording saved to gallery');
   * ```
   */
  stop(): Promise<void>;

  /**
   * Get the native Capacitor plugin version.
   *
   * @returns Promise that resolves with the plugin version
   * @throws Error if getting the version fails
   * @since 1.0.0
   * @example
   * ```typescript
   * const { version } = await ScreenRecorder.getPluginVersion();
   * console.log('Plugin version:', version);
   * ```
   */
  getPluginVersion(): Promise<{ version: string }>;
}
