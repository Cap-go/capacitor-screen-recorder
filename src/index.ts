import { registerPlugin } from '@capacitor/core';

import type { ScreenRecorderPlugin } from './definitions';

const ScreenRecorder = registerPlugin<ScreenRecorderPlugin>('ScreenRecorder', {
  web: () => import('./web').then(m => new m.ScreenRecorderWeb()),
});

export * from './definitions';
export { ScreenRecorder };
