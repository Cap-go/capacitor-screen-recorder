export interface ScreenRecorderPlugin {
  /**
   * start the recording
   * @param options Recording options
   */
  start(options?: { recordAudio?: boolean }): Promise<void>;
  /**
   * stop the recording
   */
  stop(): Promise<void>;

  /**
   * Get the native Capacitor plugin version
   *
   * @returns {Promise<{ id: string }>} an Promise with version for this device
   * @throws An error if the something went wrong
   */
  getPluginVersion(): Promise<{ version: string }>;
}
