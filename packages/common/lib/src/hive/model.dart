part of '../hive.dart';

enum ApplicationListMode {
  none,
  blackList,
  whiteList;

  static ApplicationListMode fromJson(dynamic json) {
    if (json is! int) return .none;
    return values[json % values.length];
  }

  int toJson() {
    return index;
  }

  String get tr {
    return switch (this) {
      none => 'none',
      blackList =>  'Blacklist mode',
      whiteList => "Whitelist mode",
    };
  }

  String get label {
    return switch (this) {
      none => '',
      blackList => 'Selected applications bypass the VPN.',
      whiteList => 'Only selected applications use the VPN.',
    };
  }
}

enum SettingMode {
  global,
  rule,
  direct;

  String get showName {
    final n = name;
    final first = n[0];
    return first.toUpperCase() + n.substring(1);
  }

  static SettingMode fromJson(dynamic json) {
    if (json is! int) return .direct;
    return values[json % values.length];
  }

  int toJson() {
    return index;
  }
}

enum ClashLogLevel {
  silent,
  error,
  warning,
  info,
  debug;

  static ClashLogLevel fromJson(dynamic json) {
    if (json is! int) return .info;
    return values[json % values.length];
  }

  int toJson() {
    return index;
  }
}

enum ClashTunStack {
  system,
  gvisor,
  mixed;

  String get showName {
    final n = name;
    final first = n[0];
    return first.toUpperCase() + n.substring(1);
  }

  static ClashTunStack fromJson(dynamic json) {
    if (json is! int) return .mixed;
    return values[json % values.length];
  }

  int toJson() {
    return index;
  }
}
