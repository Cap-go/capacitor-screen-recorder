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
}
