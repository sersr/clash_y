import 'dart:async';
import 'dart:isolate';

import 'package:nop_db/nop_db.dart';
import 'package:utils/utils.dart';

import '../../data/data.dart';
import 'data.dart';
import 'database.dart';
export 'database.dart';
part 'events.g.dart';

@NopIsolateEvent()
abstract class Event with ClashEvent, ConfigsEvent {
  ClashEvent get clashEvent => this;
}

abstract class ClashEvent {
  FutureOr<ProxiesData?> getProxies();
  FutureOr<void> selectProxy(String selector, String proxy);
  FutureOr<void> resetConfigs(ConfigsData data);
  FutureOr<void> reloadConfigs(bool force, String path);
  FutureOr<void> getRules();
  FutureOr<void> getConfigs();
  FutureOr<Delay?> getDelay(String proxy, int timeout, String testUrl);
  Stream<Connections> watchConnections();
}

abstract class ConfigsEvent {
  Stream<ConfigsCurrent> getConfigsCurrent();
  FutureOr<void> addNewConfigUrl(String url, int updateInterval, String? name);
  FutureOr<void> removeConfigUrl(String url);
  FutureOr<void> updateConfigsUrl(String url, ConfigTable config);
  FutureOr<String?> getCurrentConfig();
  FutureOr<void> updateCurrentConfig(String url);
}
