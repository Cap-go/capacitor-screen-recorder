export interface ScreenRecorderPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
