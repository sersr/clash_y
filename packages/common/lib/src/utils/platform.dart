import 'package:flutter/foundation.dart';

extension PlatformExt on TargetPlatform {
  bool get isDesktop {
    return switch (this) {
      .android || .iOS || .fuchsia => false,
      .macOS || .linux || .windows => true,
    };
  }
}
