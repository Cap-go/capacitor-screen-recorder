import { WebPlugin } from '@capacitor/core';

import type { ScreenRecorderPlugin } from './definitions';

export class ScreenRecorderWeb
  extends WebPlugin
  implements ScreenRecorderPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
