import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';

import 'src/generated/android/content/Context.dart';
import 'src/generated/android/content/pm/ApplicationInfo.dart';
import 'src/generated/android/content/pm/PackageItemInfo.dart';
import 'src/generated/android/content/pm/PackageInfo.dart';
import 'src/generated/android/content/pm/PackageManager.dart';
import 'src/generated/android/graphics/Bitmap.dart';
import 'src/generated/android/graphics/Canvas.dart';
import 'src/generated/android/graphics/drawable/Drawable.dart';
import 'src/generated/java/io/ByteArrayOutputStream.dart';
import 'src/installed_application.dart';

export 'src/installed_application.dart';

/// Accesses installed application information using Android's PackageManager.
abstract final class InstallApps {
  static const _internetPermission = 'android.permission.INTERNET';

  static Future<List<InstalledApplication>> getInstalledApps({
    bool includeSystemApps = false,
  }) => Isolate.run(() => _getInstalledApps(includeSystemApps));

  static List<InstalledApplication> _getInstalledApps(
    bool includeSystemApps,
  ) {
    final context = androidApplicationContext.as(
      Context.type,
      releaseOriginal: true,
    );
    try {
      final packageManager =
          context.packageManager ??
          (throw StateError('Android PackageManager is unavailable.'));
      try {
        final apps =
            packageManager.getInstalledApplications$1(0) ??
            (throw StateError(
              'Android returned no installed application list.',
            ));
        try {
          final internetPermissions = _getInternetPermissionByPackage(
            packageManager,
          );
          final result = <InstalledApplication>[];
          final count = apps.size();
          for (var index = 0; index < count; index++) {
            final app = apps.get(index);
            if (app == null) continue;
            try {
              final systemApp = app.flags & ApplicationInfo.FLAG_SYSTEM != 0;
              if (!includeSystemApps && systemApp) continue;

              final label = packageManager.getApplicationLabel(app);
              late final String appName;
              try {
                appName = label?.toString() ?? '';
              } finally {
                label?.release();
              }
              final packageItem = app.as(PackageItemInfo.type);
              late final String? packageName;
              try {
                packageName = packageItem.packageName?.toDartString(
                  releaseOriginal: true,
                );
              } finally {
                packageItem.release();
              }
              if (packageName == null || packageName.isEmpty) {
                throw StateError(
                  'Android returned an application without a package name.',
                );
              }
              result.add(
                InstalledApplication(
                  appName: appName,
                  packageName: packageName,
                  systemApp: systemApp,
                  hasInternetPermission:
                      internetPermissions[packageName] ?? false,
                ),
              );
            } finally {
              app.release();
            }
          }
          result.sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );
          return result;
        } finally {
          apps.release();
        }
      } finally {
        packageManager.release();
      }
    } finally {
      context.release();
    }
  }

  static Map<String, bool> _getInternetPermissionByPackage(
    PackageManager packageManager,
  ) {
    final packages =
        packageManager.getInstalledPackages$1(PackageManager.GET_PERMISSIONS) ??
        (throw StateError('Android returned no installed package list.'));
    try {
      final result = <String, bool>{};
      for (var index = 0; index < packages.size(); index++) {
        final packageInfo = packages.get(index);
        if (packageInfo == null) continue;
        try {
          final packageName = packageInfo.packageName?.toDartString(
            releaseOriginal: true,
          );
          if (packageName == null || packageName.isEmpty) continue;

          final requestedPermissions = packageInfo.requestedPermissions;
          var hasInternetPermission = false;
          try {
            if (requestedPermissions != null) {
              for (
                var permissionIndex = 0;
                permissionIndex < requestedPermissions.length;
                permissionIndex++
              ) {
                final permission = requestedPermissions[permissionIndex]
                    ?.toDartString(releaseOriginal: true);
                if (permission == _internetPermission) {
                  hasInternetPermission = true;
                  break;
                }
              }
            }
          } finally {
            requestedPermissions?.release();
          }
          result[packageName] = hasInternetPermission;
        } finally {
          packageInfo.release();
        }
      }
      return result;
    } finally {
      packages.release();
    }
  }

  static Future<Uint8List> getAppIcon(String packageName) =>
      Isolate.run(() => _getAppIcon(packageName));

  static Uint8List _getAppIcon(String packageName) {
    final context = androidApplicationContext.as(
      Context.type,
      releaseOriginal: true,
    );
    try {
      final packageManager =
          context.packageManager ??
          (throw StateError('Android PackageManager is unavailable.'));
      try {
        final javaPackageName = packageName.toJString();
        ApplicationInfo? app;
        try {
          app = packageManager.getApplicationInfo$1(javaPackageName, 0);
        } finally {
          javaPackageName.release();
        }
        if (app == null) {
          throw StateError('Application not found: $packageName');
        }
        try {
          final icon = packageManager.getApplicationIcon(app);
          if (icon == null) {
            throw StateError('Application icon not found: $packageName');
          }
          try {
            final width = icon.intrinsicWidth.clamp(1, 512);
            final height = icon.intrinsicHeight.clamp(1, 512);
            final config = Bitmap$Config.ARGB_8888;
            Bitmap? bitmap;
            try {
              bitmap = Bitmap.createBitmap$10(width, height, config);
            } finally {
              config.release();
            }
            if (bitmap == null) {
              throw StateError(
                'Android could not allocate the application icon bitmap.',
              );
            }
            try {
              final canvas = Canvas.new$1(bitmap);
              try {
                icon.setBounds(0, 0, width, height);
                icon.draw(canvas);

                final output = ByteArrayOutputStream();
                try {
                  final compressFormat = Bitmap$CompressFormat.PNG;
                  late final bool compressed;
                  try {
                    compressed = bitmap.compress(compressFormat, 100, output);
                  } finally {
                    compressFormat.release();
                  }
                  if (!compressed) {
                    throw StateError(
                      'Android failed to encode the application icon.',
                    );
                  }
                  final bytes = output.toByteArray();
                  if (bytes == null) {
                    throw StateError(
                      'Android returned no application icon bytes.',
                    );
                  }
                  try {
                    return Uint8List.fromList(bytes.getRange(0, bytes.length));
                  } finally {
                    bytes.release();
                  }
                } finally {
                  output.release();
                }
              } finally {
                canvas.release();
              }
            } finally {
              bitmap.release();
            }
          } finally {
            icon.release();
          }
        } finally {
          app.release();
        }
      } finally {
        packageManager.release();
      }
    } finally {
      context.release();
    }
  }
}

/// Lazily loads an installed application's icon.
class AppIconImageProvider extends ImageProvider<AppIconImageProvider> {
  const AppIconImageProvider(this.packageName, {this.scale = 1});

  final String packageName;
  final double scale;

  @override
  Future<AppIconImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AppIconImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    AppIconImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
    );
  }

  Future<ui.Codec> _loadAsync(
    AppIconImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await InstallApps.getAppIcon(key.packageName);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is AppIconImageProvider &&
      other.packageName == packageName &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(packageName, scale);
}
