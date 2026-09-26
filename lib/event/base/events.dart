import 'dart:async';

import 'package:common/common.dart';
import 'package:nop/nop.dart';

import 'data.dart';
import 'database.dart';
export 'database.dart';
part 'events.g.dart';

@NopServerEvent()
abstract mixin class ClashEvent {
  FutureOr<ProxiesData?> getProxies();
  FutureOr<void> selectProxy(String selector, String proxy);
  FutureOr<void> resetConfigs(ConfigsData data);
  FutureOr<void> getRules();
  FutureOr<void> getConfigs();
  FutureOr<Delay?> getDelay(String proxy, int timeout, String testUrl);

  Stream<TrafficModel> watchTraffic();

  Stream<LogModel> watchLogs(String level);
  @NopServerMethod(unique: true)
  Stream<Connections> watchConnections(Duration interval);

  FutureOr<void> updateCurrentConfig(String url);
}

@NopServerEvent()
abstract mixin class ConfigsEvent {
  Stream<ConfigsCurrent> getConfigsCurrent();
  FutureOr<void> addNewConfigUrl(String url, int updateInterval, String? name);
  FutureOr<void> removeConfigUrl(String url);
  FutureOr<void> updateConfigsUrl(String url, ConfigTable config);
  FutureOr<ConfigTable?> getConfig(String url);

  FutureOr<void> setConfigDateTime(String url, String info);
}
