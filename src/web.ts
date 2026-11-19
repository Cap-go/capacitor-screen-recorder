import { WebPlugin } from '@capacitor/core';

import type {
  ScreenCaptureState,
  ScreenRecorderPlugin,
  StartRecordingOptions,
} from './definitions';

export class ScreenRecorderWeb extends WebPlugin implements ScreenRecorderPlugin {
  async start(_options?: StartRecordingOptions): Promise<void> {
    throw new Error('Method not implemented.');
  }
  async stop(): Promise<void> {
    throw new Error('Method not implemented.');
  }

  async getPluginVersion(): Promise<{ version: string }> {
    return { version: 'web' };
  }

  async getCaptureState(): Promise<ScreenCaptureState> {
    throw new Error('Method not implemented.');
  }
}
