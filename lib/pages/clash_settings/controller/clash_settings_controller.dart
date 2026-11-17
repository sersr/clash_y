import 'package:clashy/event/clash_event.dart';

import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';

class ClashSettingsController with NopLifecycle {
  late final clashEvent = getType<ClashEvent>();

  final _listenable = Listenable.merge(SettingsHive.values.map((e) => e.val));

  @override
  void nopInit() {
    _listenable.addListener(_update);
    super.nopInit();
  }

  void _update() {
    clashEvent.reloadCurrentConfig();
  }

  @override
  void nopDispose() {
    _listenable.removeListener(_update);
    super.nopDispose();
  }
}
