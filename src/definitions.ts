export interface ScreenRecorderPlugin {
  /**
   * start the recording
   *
   */
  start(): Promise<void>;
  /**
   * stop the recording
   *
   */
  stop(): Promise<void>;
}
