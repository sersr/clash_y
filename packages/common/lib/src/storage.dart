import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:hive_ce/hive.dart';
import 'package:nop/utils.dart';

final class StorageTransform {
  final Function fn;
  final dynamic defaultValue;

  final ValueNotifier Function(dynamic v)? createN;
  const new(this.fn, [this.defaultValue, this.createN]);
  const new base([this.defaultValue, this.createN]) : fn = _base;

  ValueNotifier? createNotifier(dynamic value) {
    if (createN case var create?) {
      return create(value);
    }

    return null;
  }

  static StorageTransform list<E>([List<E>? defaultValue]) {
    return .new(_list<E>, defaultValue, (value) => AList<E>(value ?? <E>[]));
  }

  static List Function(List list) listDy(Function fn) =>
      (List list) => list.map((e) => fn(e)).toList();

  static StorageTransform map<K, E>(Function fn, [Map<K, E>? defaultValue]) {
    return .new(
      (Map map) => map.map<K, E>((k, v) => MapEntry(k, fn(v))),
      defaultValue,
      (value) => AMap<K, E>(value ?? <K, E>{}),
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
    return al.value;
  }

  AutoValueNotifier<D> get al {
    return target.readLate<D>(this, _transform) as AutoValueNotifier<D>;
  }

  StorageTransform _transform() => transform;

  set value(D value) {
    al.value = value;
  }

  StorageTransform get transform;
}

mixin StorageMixin {
  dynamic get(Object key);
  Future<void> delete(Object key);
  Future<void> put(Object key, dynamic data);

  static final _weekRef = <Object, _Wrapper>{};

  static final _finalizer = Finalizer<Object>((v) {
    _weekRef.remove(v);
  });

  static void _wrap(Object key, dynamic obx) {
    final old = _weekRef[key];
    if (old != null) {
      _finalizer.detach(old);
    }

    final wrapper = _Wrapper(obx);
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
    var obx = t.createNotifier(v) as ValueNotifier<T?>?;
    if (obx == null) {
      if (v != null) {
        obx = ValueNotifier<T>(v);
      } else {
        obx = .new(v);
      }
    }

    final o = obx;
    o.addListener(() {
      _saveData(key, o.value);
    });
    StorageMixin._wrap(key, o);

    return o.al;
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
  _Wrapper(dynamic value) : value = WeakReference(value);
  final dynamic value;
}
