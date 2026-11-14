part of '_g.dart';

@JsonSerializable(explicitToJson: true)
class Profile with Equatable {
  Profile({
    this.id,
    this.name,
    this.rawName,
    this.updateInterval,
    this.updateTime,
    this.url,
    this.upload,
    this.download,
    this.total,
    this.expire,
    this.scriptId,
  });

  final String? id;
  final String? url;
  final String? name;
  final String? rawName;
  final int? updateInterval;
  final DateTime? updateTime;
  final String? scriptId;

  // subscription-userinfo
  final int? upload;
  final int? download;
  final int? total;
  final int? expire;

  String get showName {
    final n = name;
    if (n == null || n.isEmpty) {
      return rawName ?? url ?? '';
    }
    return n;
  }

  bool shouldUpdate() {
    final lastUpdateTime = updateTime;
    if (lastUpdateTime == null) return true;
    final interval = updateInterval;
    if (interval == null || interval <= 0) {
      return false;
    }

    return DateTime.now().difference(lastUpdateTime).inMinutes >= interval;
  }

  bool isCurrent(Profile profile) {
    if (identical(this, profile)) return true;
    return id == profile.id;
  }

  String get used {
    final quota = total;
    if (quota == null) return '';

    final consumed = (upload ?? 0) + (download ?? 0);
    String gigabytes(int bytes) => (bytes / 1073741824).toStringAsFixed(2);
    return '${gigabytes(consumed)} GB / ${gigabytes(quota)} GB';
  }

  String get filePath {
    if (url case var url?) {
      final paths = Paths.g();
      return paths.getCacheFile(url).path;
    }
    return '';
  }

  Future<Map<String, dynamic>> getConfigData() async {
    final js = QuickjsRuntime();
    Map<String, dynamic> data = {};
    try {
      data = await getConfigMap(filePath);
      final script = SettingsHive.getScript(scriptId);
      if (script == null) return data;

      final scriptErrors = <String?>[];
      js.eval(
        script.script,
        filename: 'profile-script.js',
        errMsg: scriptErrors,
      );

      if (scriptErrors.isNotEmpty) {
        throw FormatException(
          scriptErrors.first ?? 'unable to evaluate profile script',
        );
      }

      js.setGlobal('profileConfig', data);

      final resultErrors = <String?>[];
      final value = js.eval(
        'main(profileConfig);',
        filename: 'profile-script-main.js',
        errMsg: resultErrors,
      );

      if (resultErrors.isNotEmpty) {
        throw FormatException(
          resultErrors.first ?? 'unable to execute profile script',
        );
      }
      if (value == null) {
        throw const FormatException('profile script returned no config');
      }

      return jsonDecode(value);
    } catch (e) {
      Log.e(e);
      return data;
    } finally {
      js.close();
    }
  }

  factory fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);

  Profile copyWith({
    required String? url,
    required String? name,
    required int? updateInterval,
    required String? scriptId,
    String? rawName,
    DateTime? updateTime,
    int? upload,
    int? download,
    int? total,
    int? expire,
  }) {
    return Profile(
      id: id,
      url: url,
      name: name,
      scriptId: scriptId,
      updateInterval: updateInterval,
      rawName: rawName ?? this.rawName,
      updateTime: updateTime ?? this.updateTime,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      total: total ?? this.total,
      expire: expire ?? this.expire,
    );
  }

  Map<String, dynamic> toJson() {
    return _$ProfileToJson(this);
  }

  @override
  List<Object?> get props => [
    id,
    name,
    scriptId,
    url,
    rawName,
    updateInterval,
    updateTime,
    upload,
    download,
    total,
    expire,
  ];
}
