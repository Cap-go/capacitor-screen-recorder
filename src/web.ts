import { WebPlugin } from '@capacitor/core';

import type { ScreenRecorderPlugin } from './definitions';

export class ScreenRecorderWeb extends WebPlugin implements ScreenRecorderPlugin {
  async start(): Promise<void> {
    throw new Error('Method not implemented.');
  }
  async stop(): Promise<void> {
    throw new Error('Method not implemented.');
  }

  async getPluginVersion(): Promise<{ version: string }> {
    return { version: 'web' };
  }
}
