/**
 * Supported video container formats for screen recordings.
 *
 * @since 8.3.0
 */
export type ScreenRecorderVideoFormat = 'mp4' | 'mov';

/**
 * Options for {@link ScreenRecorderPlugin.start}.
 *
 * @since 8.3.0
 */
export interface StartRecordingOptions {
  /**
   * Whether to record audio along with the screen video.
   *
   * @default false
   * @since 1.0.0
   */
  recordAudio?: boolean;

  /**
   * Video container format for the saved recording.
   *
   * Accepts `mp4`, `mov`, or MIME types `video/mp4` and `video/quicktime`.
   * iOS supports both `mp4` and `mov`. Android records MPEG-4 (`.mp4`) regardless of this value.
   *
   * @default 'mp4'
   * @since 8.3.0
   * @example 'mov'
   */
  format?: ScreenRecorderVideoFormat | 'video/mp4' | 'video/quicktime';
}

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
   * @param options.format - Video container format for the saved recording. Defaults to `mp4`.
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
   *
   * // Start recording as MOV on iOS
   * await ScreenRecorder.start({ format: 'mov' });
   * ```
   */
  start(options?: StartRecordingOptions): Promise<void>;

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
