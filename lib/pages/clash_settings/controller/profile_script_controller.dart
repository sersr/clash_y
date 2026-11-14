import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:jsf/jsf.dart';
import 'package:nop/nop.dart';

class ProfileScriptController with NopLifecycle, AlScopeManager {
  late final scripts = () {
    return SettingsHive.scripts.al.value
        .map((k, v) => .new(k, (id: k, data: v)))
        .values
        .toList();
  }.mount(this);

  bool verify(String script) {
    try {
      final js = JsRuntime();
      js.execInitScript(script);
      final value = js.eval('main({});');
      Log.w(value);
      return true;
    } catch (e) {
      return false;
    }
  }
}
