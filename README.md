# Capacitor-screen-recorder
 <a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin_screen_recorder"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin_screen_recorder"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>
Record device's screen

## Documentation

The most complete doc is available here: https://capgo.app/docs/plugins/screen-recorder/

## Compatibility

| Plugin version | Capacitor compatibility | Maintained |
| -------------- | ----------------------- | ---------- |
| v8.\*.\*       | v8.\*.\*                | ✅          |
| v7.\*.\*       | v7.\*.\*                | On demand   |
| v6.\*.\*       | v6.\*.\*                | ❌          |
| v5.\*.\*       | v5.\*.\*                | ❌          |

> **Note:** The major version of this plugin follows the major version of Capacitor. Use the version that matches your Capacitor installation (e.g., plugin v8 for Capacitor 8). Only the latest major version is actively maintained.

## Install

```bash
npm install @capgo/capacitor-screen-recorder
npx cap sync
```

## IOS

add NSPhotoLibraryUsageDescription in your info.plist

## Android
increase project's minSdk version to 23, it's required by the dependency HBRecorder

Add these permissions in your `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_INTERNAL_STORAGE" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
```

### Add JitPack Repository
Add JitPack repository to your Android app's build.gradle (android/app/build.gradle):

```gradle
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io/' }
    }
}
```

### Variables

This plugin will use the following project variables (defined in your app's `variables.gradle` file):
- `$kotlinVersion` version of `org.jetbrains.kotlin:kotlin-stdlib-jdk7` (default: `1.7.21`)

If you have compilation issue `Duplicate class androidx.lifecycle.ViewModelLazy`
i found in this the solution who worked for me:
https://stackoverflow.com/questions/73406969/duplicate-class-androidx-lifecycle-viewmodellazy-found-in-modules-lifecycle-view

Add this
```
configurations {
    all {
        exclude group: 'androidx.lifecycle', module: 'lifecycle-runtime-ktx'
        exclude group: 'androidx.lifecycle', module: 'lifecycle-viewmodel-ktx'
    }
}
an
```
line 2 in file `android/app/build.gradle`

## Configuration

No configuration required for this plugin.

## API

<docgen-index>

* [`start(...)`](#start)
* [`stop()`](#stop)
* [`getPluginVersion()`](#getpluginversion)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

Capacitor Screen Recorder Plugin for recording the device screen.
Allows you to capture video recordings of the screen with optional audio.

### start(...)

```typescript
start(options?: { recordAudio?: boolean | undefined; } | undefined) => Promise<void>
```

Start recording the device screen.

Initiates screen recording with optional audio capture. The user will be
prompted to grant screen recording permissions if not already granted.
On iOS, the system recording UI will be displayed. On Android, the recording
starts immediately after permission is granted.

| Param         | Type                                    | Description                       |
| ------------- | --------------------------------------- | --------------------------------- |
| **`options`** | <code>{ recordAudio?: boolean; }</code> | - Recording configuration options |

**Since:** 1.0.0

--------------------


### stop()

```typescript
stop() => Promise<void>
```

Stop the current screen recording.

Stops the active screen recording and saves the video to the device's
camera roll or gallery. On iOS, the system will show a preview of the
recording. On Android, the video is saved directly to the gallery.

**Since:** 1.0.0

--------------------


### getPluginVersion()

```typescript
getPluginVersion() => Promise<{ version: string; }>
```

Get the native Capacitor plugin version.

**Returns:** <code>Promise&lt;{ version: string; }&gt;</code>

**Since:** 1.0.0

--------------------

</docgen-api>
