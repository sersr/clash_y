import 'dart:convert';

import 'package:flutter_nop/flutter_nop.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nop/utils.dart';

abstract class HiveRegister {
  static final _handlers = <Type, Function>{};
  static T? wrapSync<T>(T? Function() body) {
    try {
      return body();
    } catch (e) {
      Log.w(e);
    }
    return null;
  }

  static void register<T>({required Function fromJson}) {
    assert(() {
      if (T == dynamic) {
        return false;
      }
      if (_handlers.containsKey(T)) {
        Log.e('HiveRegister: $T 已注册');
      }
      return true;
    }());
    _handlers[T] = fromJson;
  }

  static void unregister<T>() {
    _handlers.remove(T);
  }
}

class _BoxValueWarapper {
  _BoxValueWarapper(dynamic value) : value = WeakReference(value);
  final dynamic value;
}

extension HiveRegisterBoxExt on Box {
  static final _weekRef = <String, _BoxValueWarapper>{};

  static final _finalizer = Finalizer<String>((v) {
    _weekRef.remove(v);
  });

  void _wrap(String key, dynamic obx) {
    final old = _weekRef[key];
    if (old != null) {
      _finalizer.detach(old);
    }

    final wrapper = _BoxValueWarapper(obx);
    _weekRef[key] = wrapper;
    _finalizer.attach(obx, key, detach: wrapper);
  }

  AutoListenNotifier<T?> read<T>(String key) {
    if (_weekRef[key] case _BoxValueWarapper(
      value: WeakReference(target: AutoListenNotifier<T?> target),
    )) {
      return target;
    }

    final obx = AutoListenNotifier(_read<T>(key));
    obx.addListener(() {
      _saveData(key, obx.value);
    });
    _wrap(key, obx);
    return obx;
  }

  T? _read<T>(String key) {
    return HiveRegister.wrapSync(() {
      final data = get(key);
      if (data == null) {
        return null;
      }

      final v = jsonDecode(data);

      final handler = HiveRegister._handlers[T];
      if (handler case var handler?) {
        return handler(v);
      } else if (v is T) {
        return v;
      }

      Log.e("call HiveRegister.register<$T>() first.");

      return null;
    });
  }

  ChangeAutoListenList<T> readDefaultList<T>(String key, List<T> defaultValue) {
    if (_weekRef[key] case _BoxValueWarapper(
      value: ChangeAutoListenList<T> target,
    )) {
      return target;
    }

    final value = _read<List<T>>(key) ?? defaultValue;
    final obx = ChangeAutoListenList<T>(List.from(value));
    obx.addListener(() {
      _saveData<List<T>>(key, obx.value);
    });

    _wrap(key, obx);
    return obx;
  }

  AutoListenNotifier<T> readDefault<T>(String key, T defaultValue) {
    if (_weekRef[key] case _BoxValueWarapper(
      value: AutoListenNotifier<T> target,
    )) {
      return target;
    }

    final value = _read<T>(key) ?? defaultValue;
    final obx = AutoListenNotifier<T>(value);
    obx.addListener(() {
      _saveData<T>(key, obx.value);
    });

    _wrap(key, obx);
    return obx;
  }

  Future<void> _saveData<T>(String key, T? data) async {
    if (data == null) {
      return delete(key);
    }

    try {
      final jsonData = jsonEncode(data);
      await put(key, jsonData);
    } catch (e) {
      Log.e(e);
    }
  }
}
