import { WebPlugin } from '@capacitor/core';
import type { PluginListenerHandle } from '@capacitor/core';

import type { ScreenRecorderPlugin, ScreenRecorderStoppedEvent, StartRecordingOptions } from './definitions';

export class ScreenRecorderWeb extends WebPlugin implements ScreenRecorderPlugin {
  async start(_options?: StartRecordingOptions): Promise<void> {
    throw new Error('Method not implemented.');
  }
  async stop(): Promise<void> {
    throw new Error('Method not implemented.');
  }

  async addListener(
    _eventName: 'onStopped',
    _listenerFunc: (event: ScreenRecorderStoppedEvent) => void,
  ): Promise<PluginListenerHandle> {
    throw new Error('Method not implemented.');
  }

  async removeAllListeners(): Promise<void> {
    throw new Error('Method not implemented.');
  }

  async getPluginVersion(): Promise<{ version: string }> {
    return { version: 'web' };
  }
}
