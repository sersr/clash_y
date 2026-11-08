# clash_service_android

Android backend for [`clash_service`](../../), implemented with
[`package:jni`](https://pub.dev/packages/jni) and
[`package:jni_flutter`](https://pub.dev/packages/jni_flutter).

## How it works

There is no `MethodChannel` or Java bridge class. Dart drives the
whole flow:

1. `jni_flutter` exposes the Android application `Context` and the current
   `Activity` to Dart.
2. Dart calls `VpnService.prepare(Context)` to find out whether the user already
   granted the VPN consent, and launches the system consent dialog when they
   have not.
3. Once consent is granted, Dart builds an `Intent` for
   `io.aote.vpnService.ClashVpnService` and starts it with
   `Context.startForegroundService`.

### Why the consent dialog needs `startActivityForResult`

`com.android.vpndialogs.ConfirmDialog` learns which package to authorize from
`Activity.getCallingPackage()`, and Android only populates that when the caller
passed a request code. Launching the dialog with plain `startActivity` — or from
the application context — leaves the package `null`, so the dialog's pre-check
succeeds and it finishes immediately: no dialog, no consent recorded, and a
caller that waits for consent waits forever.

The plugin therefore starts the dialog with `Activity.startActivityForResult`
from the current activity, and detects the outcome by polling
`VpnService.prepare`, which starts returning `null` once the dialog has recorded
the consent system-side.

The Android service and its support classes are implemented in Kotlin:

| File | Purpose |
| --- | --- |
| `android/src/main/kotlin/io/aote/vpnService/ClashVpnService.kt` | The `VpnService` that establishes the TUN device and owns mihomo's lifetime. |
| `android/src/main/kotlin/io/aote/vpnService/ClashCore.kt` | Native methods into `libclash` (provided by `package:clash_core`). |
| `android/src/main/kotlin/io/aote/vpnService/VpnServiceContract.kt` | The actions/extras shared with `lib/src/android_vpn_service.dart`. |
| `android/src/main/kotlin/io/aote/vpnService/ProfileConfigUpdater.kt` | Downloads subscriptions and merges app-owned configuration blocks. |
| `android/src/main/kotlin/io/aote/vpnService/TrafficMonitor.kt` | Reads live upload/download rates from mihomo's Unix controller socket for the foreground notification. |
| `android/src/main/AndroidManifest.xml` | Declares the service and the foreground-service permissions. |

Dart talks to the service purely through the `Intent` extras defined in
`VpnServiceContract.kt`; the two sides must stay in sync.

The Android framework bindings used by Dart are generated with JNIgen into
`lib/src/generated/`. Regenerate them from this package directory after
`dart pub get` with:

```sh
dart --packages=.dart_tool/package_config.json tools/jnigen.dart
```

The direct invocation avoids running Flutter native-asset build hooks while
starting the generator.

Set `ANDROID_SDK_ROOT` or `ANDROID_HOME` first, or configure `android/local.properties`
at the workspace root. Generation uses Android API levels 34, 35, and 36.

## Public API

```dart
import 'package:clash_service_android/clash_service_android.dart' as clash;

final started = await clash.start(
  '/data/user/0/io.aote.clashy/files/clashy/clash_config',
  allowList: true,
  allowedApplications: const ['org.telegram.messenger'],
  disallowedApplications: const [],
);

await clash.stop();
```

`start` returns `true` once the VPN consent is granted and the foreground
service has been asked to start — not when mihomo is ready. `ClashVpnService`
deliberately keeps no runtime status object, so callers that need mihomo itself
should poll its API.

Use `AndroidVpnService.hasVpnConsent()` to check the consent state on its own,
and `AndroidVpnService` for the same operations with named access to the flow
constants (`permissionTimeout`, `permissionPollInterval`).

Failures are reported through `debugPrint` with the `clash_service_android` tag
rather than being swallowed, so `flutter run` and logcat show which step failed.

## Android setup

The plugin manifest already declares `ClashVpnService` and the required
foreground-service permissions; they are merged into the application. Nothing
else is required from the host application.

## Regenerating the Android library module

`ffiPlugin: true` in `pubspec.yaml` is what keeps this plugin's Android library
module in the application's Gradle build, so the Kotlin sources and the manifest
are compiled and merged. Removing it would silently drop `ClashVpnService` from
the APK.
