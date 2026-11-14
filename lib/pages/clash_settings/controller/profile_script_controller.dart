import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';

class ProfileScriptController with NopLifecycle, AlScopeManager {
  late final scripts = () {
    return SettingsHive.scripts.al.value
        .map((k, v) => .new(k, (id: k, data: v)))
        .values
        .toList();
  }.mount(this);
}
