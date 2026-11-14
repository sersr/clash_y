/// The profile a running service should keep up to date.
///
/// The service only needs enough information to refresh the configuration it
/// is running: where the subscription comes from ([url]) and how often it
/// should be downloaded ([updateInterval], in minutes).
class ClashProfile {
  const ClashProfile({
    required this.configDir,
    this.id,
    this.name,
    this.url,
    this.updateInterval,
    this.updateTime,
    this.script,
  });

  /// Directory holding the `config.yaml` the core runs with.
  final String configDir;
  final String? id;
  final String? name;
  final String? url;

  /// Profile script applied to downloaded subscription configs.
  final String? script;

  /// Subscription refresh interval in minutes. `null` or `<= 0` disables the
  /// automatic updates.
  final int? updateInterval;

  /// When the subscription was last downloaded successfully.
  final DateTime? updateTime;

  bool get canAutoUpdate {
    final lastUpdateTime = updateTime;
    if (lastUpdateTime == null) return true;
    final interval = updateInterval;
    if (interval == null || interval <= 0) {
      return false;
    }

    return DateTime.now().difference(lastUpdateTime).inMinutes >= interval;
  }

  static const _minDelay = Duration(seconds: 5);

  /// How long to wait before the next download.
  ///
  /// Returns `null` when the profile has no schedule. A profile that is already
  /// due (or was never downloaded) still waits [_minDelay] so a fresh start is
  /// not immediately followed by another download.
  Duration? nextUpdateDelay([DateTime? now]) {
    if (!canAutoUpdate) return null;
    final last = updateTime;
    if (last == null) return _minDelay;

    final due = last.add(Duration(minutes: updateInterval!));
    final current = now ?? DateTime.now();
    if (!due.isAfter(current)) return _minDelay;

    final delay = due.difference(current);
    return delay < _minDelay ? _minDelay : delay;
  }

  ClashProfile copyWith({
    String? configDir,
    String? id,
    String? name,
    String? url,
    int? updateInterval,
    DateTime? updateTime,
    String? script,
  }) {
    return ClashProfile(
      configDir: configDir ?? this.configDir,
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      updateInterval: updateInterval ?? this.updateInterval,
      updateTime: updateTime ?? this.updateTime,
      script: script ?? this.script,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'configDir': configDir,
      'updateInterval': updateInterval,
      'updateTime': updateTime?.toIso8601String(),
      'script': script,
    };
  }

  factory ClashProfile.fromJson(Map<dynamic, dynamic> json) {
    final configDir = json['configDir'];
    return ClashProfile(
      configDir: configDir is String ? configDir : '',
      id: json['id'] as String?,
      name: json['name'] as String?,
      url: json['url'] as String?,
      updateInterval: switch (json['updateInterval']) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value),
        _ => null,
      },
      script: json['script'] as String?,
      updateTime: switch (json['updateTime']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  /// Parses the body of a start request.
  ///
  /// Older clients post the configuration directory as a plain string; those
  /// requests keep working but cannot schedule updates.
  static ClashProfile? tryParse(Object? data) {
    return switch (data) {
      final String configDir when configDir.isNotEmpty => ClashProfile(
        configDir: configDir,
      ),
      final Map<dynamic, dynamic> json => ClashProfile.fromJson(json),
      _ => null,
    };
  }
}
