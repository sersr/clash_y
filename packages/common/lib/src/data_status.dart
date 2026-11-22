import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_nop/change_notifier.dart';
import 'package:nop/nop.dart';

typedef DataStatusDy<T> = DataStatus<T, dynamic>;

typedef DataIdleDy<T> = DataIdle<T, dynamic>;
typedef DataSuccessDy<T> = DataSuccess<T, dynamic>;
typedef DataLoadingDy<T> = DataLoading<T, dynamic>;
typedef DataFailureDy<T> = DataFailure<T, dynamic>;

sealed class DataStatus<T, R> {
  const DataStatus();

  T? get data;

  const factory DataStatus.idle({T? initData}) = DataIdle;
  const factory DataStatus.loading(T? lastData) = DataLoading;
  const factory DataStatus.success(T data, [T? lastData]) = DataSuccess;
  const factory DataStatus.failure(
    T? lastData, [
    R? error,
    StackTrace? stackTrace,
  ]) = DataFailure;

  DataLoading<T, R> loading();
  DataSuccess<T, R> success(T data);
  DataFailure<T, R> failure([R? error, StackTrace? stackTrace]);
}

class DataIdle<T, R> extends DataStatus<T, R> {
  const DataIdle({this.initData});

  final T? initData;
  @override
  T? get data => initData;

  @override
  int get hashCode => Object.hash(DataIdle<T, R>, null);

  @override
  bool operator ==(Object other) {
    if (other is! DataIdle<T, R>) {
      return false;
    }
    return true;
  }

  @override
  DataFailure<T, R> failure([R? error, StackTrace? stackTrace]) {
    return DataFailure(initData, error, stackTrace);
  }

  @override
  DataLoading<T, R> loading() {
    return DataLoading(initData);
  }

  @override
  DataSuccess<T, R> success(T data) {
    return DataSuccess(data, initData);
  }
}

class DataLoading<T, R> extends DataStatus<T, R> {
  const DataLoading(this.lastData);

  final T? lastData;

  @override
  T? get data => lastData;

  @override
  int get hashCode => Object.hash(lastData, null);

  @override
  bool operator ==(Object other) {
    if (other is! DataLoading<T, R>) {
      return false;
    }
    return true;
  }

  @override
  DataFailure<T, R> failure([R? error, StackTrace? stackTrace]) {
    return DataFailure(lastData, error, stackTrace);
  }

  @override
  DataLoading<T, R> loading() {
    return this;
  }

  @override
  DataSuccess<T, R> success(T data) {
    return DataSuccess(data, lastData);
  }
}

class DataSuccess<T, R> extends DataStatus<T, R> {
  const DataSuccess(this.data, [this.lastData]);
  @override
  final T data;
  final T? lastData;

  @override
  int get hashCode => Object.hash(data, lastData);

  @override
  bool operator ==(Object other) {
    if (other is! DataSuccess<T, R>) {
      return false;
    }
    return data == other.data && lastData == other.lastData;
  }

  @override
  DataFailure<T, R> failure([R? error, StackTrace? stackTrace]) {
    return DataFailure(data, error, stackTrace);
  }

  @override
  DataLoading<T, R> loading() {
    return DataLoading(data);
  }

  @override
  DataSuccess<T, R> success(T data) {
    return DataSuccess(data, this.data);
  }
}

class DataFailure<T, R> extends DataStatus<T, R> {
  const DataFailure(this.lastData, [this.error, this.stackTrace]);
  final R? error;
  final T? lastData;
  final StackTrace? stackTrace;

  @override
  T? get data => lastData;

  @override
  int get hashCode => Object.hash(error, lastData);

  @override
  bool operator ==(Object other) {
    if (other is! DataFailure<T, R>) {
      return false;
    }
    return error == other.error && lastData == other.lastData;
  }

  @override
  DataFailure<T, R> failure([R? error, StackTrace? stackTrace]) {
    return DataFailure(lastData, error, stackTrace);
  }

  @override
  DataLoading<T, R> loading() {
    return DataLoading(lastData);
  }

  @override
  DataSuccess<T, R> success(T data) {
    return DataSuccess(data, lastData);
  }
}

typedef DataCache<T, R> = ({DataStatus<T, R> lastData, int key});
typedef DataStatusScopeDy<T> = DataStatusScope<T, dynamic>;

class DataStatusScope<T, R> {
  DataStatusScope.idle() : _data = .val(.idle());
  DataStatusScope.loading([T? data]) : _data = .val(.loading(data));
  DataStatusScope.success(T data, [T? lastData])
    : _data = .val(.success(data, lastData));
  DataStatusScope.failure(T? data, [R? error, StackTrace? stackTrace])
    : _data = .val(.failure(data, error, stackTrace));

  final AV<DataStatus<T, R>> _data;

  DataStatus<T, R> get data => _data.value;

  void addListener(VoidCallback listener) {
    _data.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    _data.removeListener(listener);
  }

  DataCache<T, R> idle(T? data) {
    final lastData = _data.value;
    _data.value = .idle(initData: data);
    return (lastData: lastData, key: _newKey);
  }

  var _key = 0;

  int get _newKey => _key += 1;

  bool restore(DataCache<T, R> cache) {
    if (cache.key != _key) return false;
    _data.value = cache.lastData;
    return true;
  }

  DataCache<T, R> loading() {
    final lastData = _data.value;
    _data.value = lastData.loading();
    return (lastData: lastData, key: _newKey);
  }

  DataCache<T, R> success(T data) {
    final lastData = _data.value;
    _data.value = lastData.success(data);
    return (lastData: lastData, key: _newKey);
  }

  DataCache<T, R> failure([R? error, StackTrace? stackTrace]) {
    final lastData = _data.value;
    _data.value = lastData..failure(error, stackTrace);
    return (lastData: lastData, key: _newKey);
  }

  static DataStatusScopeDy<T>? getCurrent<T>() {
    if (Zone.current[_Type<T>] case DataStatusScopeDy<T> v) {
      return v;
    }
    return null;
  }

  static DataCache<T, dynamic>? succ<T>(T data) {
    return getCurrent<T>()?.success(data);
  }

  static DataCache<T, dynamic>? fail<T>(dynamic error) {
    return getCurrent<T>()?.failure(error);
  }

  Future<D> load<D>(Future<D> Function() task) {
    final cache = loading();

    return runZoned(() {
      return task()..whenComplete(() {
        if (restore(cache)) {
          assert(Log.w("warning: data unchanged."));
        }
      });
    }, zoneValues: {_Type<T>: this});
  }
}

final class _Type<T>;
