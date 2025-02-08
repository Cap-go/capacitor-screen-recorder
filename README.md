# Capacitor-screen-recorder
 <a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin"> ➡️ Get Instant updates for your App with Capgo 🚀</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin"> Fix your annoying bug now, Hire a Capacitor expert 💪</a></h2>
</div>
Record device's screen

## Install

```bash
npm install @capgo/capacitor-screen-recorder
npx cap sync
```

## IOS

add NSPhotoLibraryUsageDescription in your info.plist

## Android
increase project's minSdk version to 23, it's required by the dependency scrcast

Add this permissions in your `AndroidManifest.xml`
```xml
  <uses-permission android:name="android.permission.CAPTURE_VIDEO_OUTPUT" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
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

* [`start()`](#start)
* [`stop()`](#stop)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### start()

```typescript
start() => Promise<void>
```

start the recording

--------------------


### stop()

```typescript
stop() => Promise<void>
```

stop the recording

--------------------

</docgen-api>
