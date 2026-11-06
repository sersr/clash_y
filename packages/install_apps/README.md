# install_apps

Reads applications visible to Android's `PackageManager` and loads their icons
from Dart through JNIgen-generated bindings.

```dart
import 'package:install_apps/install_apps.dart';

final apps = await InstallApps.getInstalledApps(includeSystemApps: true);
```

`AppIconImageProvider` can be used to display an app icon by package name.
Android package visibility rules still apply; the host app must declare the
appropriate `<queries>` entries in its manifest.

Regenerate the Android bindings after changing the JNIgen input classes:

```sh
dart run tools/jnigen.dart
```

The generator reads the Android SDK path from `ANDROID_SDK_ROOT` or
`ANDROID_HOME`, falling back to `android/local.properties` in the workspace.
