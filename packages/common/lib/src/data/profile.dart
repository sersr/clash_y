part of '_g.dart';

extension ProfileExt on Profile {
  String get filePath {
    if (url case var url?) {
      return G.getCacheFile(url).path;
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
}
