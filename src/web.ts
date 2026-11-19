import { WebPlugin } from '@capacitor/core';

import type {
  ScreenRecorderPlugin,
  ScreenRecorderStopResult,
  StartRecordingOptions,
} from './definitions';

export class ScreenRecorderWeb extends WebPlugin implements ScreenRecorderPlugin {
  async start(_options?: StartRecordingOptions): Promise<void> {
    throw new Error('Method not implemented.');
  }
  async stop(): Promise<ScreenRecorderStopResult> {
    throw new Error('Method not implemented.');
  }

  async getPluginVersion(): Promise<{ version: string }> {
    return { version: 'web' };
  }
}
