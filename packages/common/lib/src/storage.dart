import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:hive_ce/hive.dart';
import 'package:nop/utils.dart';

typedef StorageTransformFn<T> = T Function(dynamic data);
typedef StorageTransformJsonFn<T> = T Function(Map<String, dynamic> data);

extension type StorageTransformDef<T>._(StorageTransform<T> target)
    implements StorageTransform<T> {
  factory def(StorageTransformFn<T> fn, T defaultValue) {
    return ._(.new(fn, defaultValue));
  }

  factory fromJson(StorageTransformJsonFn<T> fn, T defaultValue) {
    return ._(.fromJson(fn, defaultValue));
  }

  factory base(T defaultValue) {
    return ._(.base(defaultValue));
  }

  static StorageTransformDef<List<E>> list<E>([List<E>? defaultValue]) {
    return ._(._(StorageTransform._list, defaultValue));
  }

  static StorageTransformDef<String> string(String defaultValue) {
    return .base(defaultValue);
  }

  static StorageTransformDef<int> nInt(int defaultValue) {
    return .base(defaultValue);
  }

  static StorageTransformDef<Double> nDouble(Double defaultValue) {
    return .base(defaultValue);
  }

  static StorageTransformDef<num> nNum(num defaultValue) {
    return .base(defaultValue);
  }
}

final class StorageTransform<T> {
  final Function fn;
  final T? defaultValue;
  const new(StorageTransformFn<T> this.fn, [this.defaultValue]);
  const new fromJson(StorageTransformJsonFn<T> this.fn, [this.defaultValue]);
  const new _(this.fn, this.defaultValue);
  const new base([this.defaultValue]) : fn = _base;

  static StorageTransform<List<E>> list<E>([List<E>? defaultValue]) {
    return ._(_list, defaultValue);
  }

  static StorageTransform<String> string([String? defaultValue]) =>
      .base(defaultValue);

  static StorageTransform<int> nInt([int? defaultValue]) => .base(defaultValue);
  static StorageTransform<Double> nDouble([Double? defaultValue]) =>
      .base(defaultValue);

  static StorageTransform<num> nNum([num? defaultValue]) => .base(defaultValue);

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

  AV<T> readDef<T>(Object key, StorageTransformDef<T> transform) {
    return read(key, transform) as AV<T>;
  }

  AV<T?> read<T>(Object key, StorageTransform<T> transform) {
    if (StorageMixin._weekRef[key] case _Wrapper(
      value: WeakReference(target: ValueNotifier<T?> target),
    )) {
      return target.al;
    }

    final v = _read<T>(key, transform) ?? transform.defaultValue;
    ValueNotifier<T?> obx;
    if (v != null) {
      obx = ValueNotifier<T>(v);
    } else {
      obx = .new(v);
    }

    obx.addListener(() {
      _saveData(key, obx.value);
    });
    StorageMixin._wrap(key, obx);

    return obx.al;
  }

  T? _read<T>(Object key, StorageTransform<T> transform) {
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
