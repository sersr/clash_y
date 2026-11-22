import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:hive_ce/hive.dart';
import 'package:nop/utils.dart';

final class StorageTransform {
  final Function fn;
  final dynamic defaultValue;

  const new(this.fn, [this.defaultValue]);
  const new base([this.defaultValue]) : fn = _base;

  static StorageTransform list<E>([List<E>? defaultValue]) {
    return .new(_list<E>, defaultValue);
  }

  static List<E> Function(List list) listDy<E>(Function fn) =>
      (List list) => list.map((e) => fn(e) as E).toList();

  static StorageTransform map<K, E>(Function fn, [Map<K, E>? defaultValue]) {
    return .new(
      (Map map) => map.map<K, E>((k, v) => MapEntry(k, fn(v))),
      defaultValue,
    );
  }

  static dynamic _base(dynamic v) => v;
  static List<E> _list<E>(List v) => v.cast();
}

mixin StorageMixinEnumBox on Enum {
  Box get box => Hive.box(name);
}

mixin StorageMixinHive on StorageMixin {
  Box get box;
  @override
  Future<void> delete(Object key) {
    return box.delete(_keyStr(key));
  }

  @override
  dynamic get(Object key) {
    return box.get(_keyStr(key));
  }

  @override
  Future<void> put(Object key, dynamic data) {
    return box.put(_keyStr(key), data);
  }

  String _keyStr(Object key) {
    return switch (key) {
      String v => v,
      Enum v => v.name,
      var v => v.toString(),
    };
  }
}

mixin StorageEnum<D> on Enum {
  StorageMixin get target;

  D get value {
    final v = val;
    if (v is D) {
      return v as D;
    }
    return v.value;
  }

  AutoValueNotifier<D> get val {
    return target.readLate<D>(key, _transform) as AutoValueNotifier<D>;
  }

  dynamic get key => this;

  StorageTransform _transform() => transform;

  set value(D value) {
    val.value = value;
  }

  StorageTransform get transform;

  bool reset() {
    return target.resetSelf(key);
  }
}

mixin StorageEnumV<D, T> on StorageEnum<D> {
  AutoValueNotifier<D> alArg(T arg) {
    return target.readLate<D>(keyArg(arg), _transform) as AutoValueNotifier<D>;
  }

  Object keyArg(T arg) => key;

  void resetArg(T arg) {
    target.resetSelf(keyArg(arg));
  }
}

mixin StorageMixin {
  dynamic get(Object key);
  Future<void> delete(Object key);
  Future<void> put(Object key, dynamic data);

  bool resetSelf(Object key) {
    final item = _weekRef[key];
    if (item == null) return false;
    final target = item.value.target;
    target?.value = item.defaultValue;
    return true;
  }

  void reset() {
    for (var item in _weekRef.values) {
      final target = item.value.target;
      target?.value = item.defaultValue;
    }
  }

  void refresh(Object key, StorageTransform transform) {
    if (_weekRef[key] case _Wrapper(
      value: WeakReference(target: ValueNotifier target),
    )) {
      target.value = _read<dynamic>(key, transform) ?? transform.defaultValue;
    }
  }

  static final _weekRef = <Object, _Wrapper>{};

  static final _finalizer = Finalizer<Object>((v) {
    _weekRef.remove(v);
  });

  static void _wrap(Object key, dynamic obx, dynamic defaultValue) {
    final old = _weekRef[key];
    if (old != null) {
      _finalizer.detach(old);
    }

    final wrapper = _Wrapper(obx, defaultValue);
    _weekRef[key] = wrapper;
    _finalizer.attach(obx, key, detach: wrapper);
  }

  static T? wrapSync<T>(T? Function() body) {
    try {
      return body();
    } catch (e) {
      Log.w(e);
    }
    return null;
  }

  AV<T> readDef<T>(Object key, StorageTransform transform) {
    return read<T>(key, transform) as AV<T>;
  }

  AV<T?> read<T>(Object key, StorageTransform transform) {
    return readLate<T>(key, () => transform);
  }

  AV<T?> readLate<T>(Object key, StorageTransform Function() transform) {
    if (StorageMixin._weekRef[key] case _Wrapper(
      value: WeakReference(target: ValueNotifier<T?> target),
    )) {
      return target.al;
    }

    final t = transform();

    final v = _read<T>(key, t) ?? t.defaultValue;
    ValueNotifier<T?> obx;

    if (v != null) {
      obx = ValueNotifier<T>(v);
    } else {
      obx = .new(v);
    }

    obx.addListener(() {
      _saveData(key, obx.value);
    });
    StorageMixin._wrap(key, obx, t.defaultValue);

    return obx.al;
  }

  T? _read<T>(Object key, StorageTransform transform) {
    return wrapSync(() {
      final data = get(key);
      if (data == null) {
        return null;
      }

      return transform.fn(jsonDecode(data));
    });
  }

  Future<void> _saveData<T>(Object key, T? data) async {
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

class _Wrapper {
  _Wrapper(ValueNotifier value, this.defaultValue)
    : value = WeakReference(value);
  final WeakReference<ValueNotifier> value;
  final dynamic defaultValue;
}
