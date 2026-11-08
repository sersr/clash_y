# clashy

clash windows UIE

## Required 
flutter --version

    Flutter 3.49.0-1.0.pre-185 • channel master • https://github.com/flutter/flutter.git
    Framework • revision 43596b3519 (2 days ago) • 2026-09-28 12:44:56 +0000
    Engine • hash 716f597e7d8ca6773c78d19f69c2bdf40343a95a (revision 31a2ab8801) (4 days ago) •
    2026-09-26 02:22:33.000Z
    Tools • Dart 3.14.0 (build 3.14.0-271.0.dev) • DevTools 2.61.0-dev.0

## Release builds

Release builds strip Go debug information from the bundled Clash core. The
iOS Debug configuration retains Go debug symbols; set
`CLASH_CORE_KEEP_DEBUG_SYMBOLS=1` when building other native cores for
debugging. Android release builds also enable R8, resource shrinking, and
compressed native-library packaging to reduce APK download size. The plugin's
consumer rules preserve JNI entry-point classes.

For smaller Flutter application binaries, split Dart symbols out of the
installers and archive the generated symbols for matching releases:

```sh
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols/android
flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios
flutter build macos --release --obfuscate --split-debug-info=build/symbols/macos
flutter build linux --release --obfuscate --split-debug-info=build/symbols/linux
flutter build windows --release --obfuscate --split-debug-info=build/symbols/windows
```

Prefer the Android App Bundle for Play Store distribution; Google Play
generates ABI-specific downloads. For direct APK distribution, use
`--split-per-abi` and distribute the APK matching each device.
