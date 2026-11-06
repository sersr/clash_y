import 'package:clashy/event/repository.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';

class ClashSettingsController with NopLifecycle {
  late final repo = getType<Repository>();

  final _listenable = Listenable.merge(SettingsHive.values.map((e) => e.al));

  @override
  void nopInit() {
    _listenable.addListener(_update);
    super.nopInit();
  }

  void _update() {
    repo.clashEvent.reloadCurrentConfig();
  }

  @override
  void nopDispose() {
    _listenable.removeListener(_update);
    super.nopDispose();
  }
}
