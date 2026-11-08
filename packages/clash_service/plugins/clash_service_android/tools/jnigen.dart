import 'dart:io';

import 'package:jnigen/jnigen.dart';

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  final workspaceRoot = packageRoot.resolve('../../../../');
  final androidSdkRoot = _androidSdkRoot(workspaceRoot);

  final generator = JniGenerator(
    input: Input(
      classes: [
        'android.app.Activity',
        'android.content.Context',
        'android.content.Intent',
        'android.net.VpnService',
        'android.os.Build',
      ],
      androidSdk: AndroidSdk(versions: [36, 35, 34], sdkRoot: androidSdkRoot),
    ),
    output: Output(
      dart: DartOutput(
        path: packageRoot.resolve('lib/src/generated/'),
        structure: OutputStructure.packageStructure,
      ),
      generateStubs: false,
    ),
  );
  await generator.generate();
}

Uri _androidSdkRoot(Uri workspaceRoot) {
  final environment = Platform.environment;
  final configuredPath =
      environment['ANDROID_SDK_ROOT'] ?? environment['ANDROID_HOME'];
  if (configuredPath != null && configuredPath.isNotEmpty) {
    return Uri.directory(configuredPath);
  }

  final propertiesFile = File.fromUri(
    workspaceRoot.resolve('android/local.properties'),
  );
  if (propertiesFile.existsSync()) {
    for (final line in propertiesFile.readAsLinesSync()) {
      if (line.startsWith('sdk.dir=')) {
        return Uri.directory(
          line.substring('sdk.dir='.length).replaceAll(r'\:', ':'),
        );
      }
    }
  }
  throw StateError(
    'Set ANDROID_SDK_ROOT or ANDROID_HOME before generating JNI bindings.',
  );
}
