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
   *
   * // Android: use a lower profile for better device compatibility
   * await ScreenRecorder.start({
   *   video: { width: 1280, height: 720, frameRate: 30, bitrate: 3000000 },
   * });
   * ```
   */
  start(options?: ScreenRecorderStartOptions): Promise<void>;

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

/**
 * Android-specific video tuning options for screen recording.
 *
 * Use these values to reduce compatibility issues on devices that fail with
 * `MediaRecorder prepare failed` when the default recorder profile is too heavy.
 *
 * @since 8.2.24
 */
export interface ScreenRecorderVideoOptions {
  /**
   * Recording width in pixels. Use `-1` (default) to let Android pick the display width.
   *
   * @since 8.2.24
   */
  width?: number;
  /**
   * Recording height in pixels. Use `-1` (default) to let Android pick the display height.
   *
   * @since 8.2.24
   */
  height?: number;
  /**
   * Video encoding bitrate in bits per second. Defaults to `5000000` (5 Mbps).
   *
   * @since 8.2.24
   */
  bitrate?: number;
  /**
   * Recording frame rate (fps). Defaults to `30`.
   *
   * @since 8.2.24
   */
  frameRate?: number;
  /**
   * Maximum recording duration in seconds. `0` means unlimited.
   *
   * @since 8.2.24
   */
  maxLengthSecs?: number;
}

/**
 * Options used when starting a recording.
 *
 * @since 8.2.24
 */
export interface ScreenRecorderStartOptions {
  /**
   * Whether to record audio along with the screen video.
   *
   * @since 1.0.0
   */
  recordAudio?: boolean;
  /**
   * Android-only video recorder options.
   *
   * @since 8.2.24
   */
  video?: ScreenRecorderVideoOptions;
}
