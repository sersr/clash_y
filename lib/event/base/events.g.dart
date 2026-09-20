// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// Generator: ServerEventGeneratorForAnnotation
// **************************************************************************

// ignore_for_file: annotate_overrides
// ignore_for_file: curly_braces_in_flow_control_structures
enum ClashEventMessage {
  getProxies,
  selectProxy,
  resetConfigs,
  getRules,
  getConfigs,
  getDelay,
  watchTraffic,
  watchLogs,
  watchConnections,
  updateCurrentConfig,
  getCurrentConfig;

  static ResolveItem getResolve({required ClashEvent clashEvent}) {
    return ResolveItem(
      protocol: ClashEventMessage,
      protocolFns: [
        (args) => clashEvent.getProxies(),
        (args) => clashEvent.selectProxy(args.$1, args.$2),
        clashEvent.resetConfigs,
        (args) => clashEvent.getRules(),
        (args) => clashEvent.getConfigs(),
        (args) => clashEvent.getDelay(args.$1, args.$2, args.$3),
        (args) => clashEvent.watchTraffic(),
        clashEvent.watchLogs,
        clashEvent.watchConnections,
        clashEvent.updateCurrentConfig,
        (args) => clashEvent.getCurrentConfig(),
      ],
    );
  }

  static IsolateRunner<ClashEventMessager> getMessage<T>(
    RemoteServer<T> remoteServer,
  ) {
    return IsolateRunner(
      remoteServer: remoteServer,
      messageItem: ClashEventMessager(),
    );
  }

  static ClashEventMessager getResolveMessage() => ClashEventMessager();
}

final class ClashEventMessager extends MessageItem
    with ClashEventMessagerMixin
    implements ClashEvent {
  ClashEventMessager();
}

mixin ClashEventMessagerMixin implements ClashEvent {
  final Type protocol = ClashEventMessage;
  Messager get messager;
  FutureOr<ProxiesData?> getProxies() {
    return messager.sendMessage(
      ClashEventMessage.getProxies,
      null,
      protocol: ClashEventMessage,
    );
  }

  FutureOr<void> selectProxy(String selector, String proxy) {
    return messager.sendMessage(ClashEventMessage.selectProxy, (
      selector,
      proxy,
    ), protocol: ClashEventMessage);
  }

  FutureOr<void> resetConfigs(ConfigsData data) {
    return messager.sendMessage(
      ClashEventMessage.resetConfigs,
      data,
      protocol: ClashEventMessage,
    );
  }

  FutureOr<void> getRules() {
    return messager.sendMessage(
      ClashEventMessage.getRules,
      null,
      protocol: ClashEventMessage,
    );
  }

  FutureOr<void> getConfigs() {
    return messager.sendMessage(
      ClashEventMessage.getConfigs,
      null,
      protocol: ClashEventMessage,
    );
  }

  FutureOr<Delay?> getDelay(String proxy, int timeout, String testUrl) {
    return messager.sendMessage(ClashEventMessage.getDelay, (
      proxy,
      timeout,
      testUrl,
    ), protocol: ClashEventMessage);
  }

  Stream<TrafficModel> watchTraffic() {
    return messager.sendMessageStream(
      ClashEventMessage.watchTraffic,
      null,
      protocol: ClashEventMessage,
    );
  }

  Stream<LogModel> watchLogs(String level) {
    return messager.sendMessageStream(
      ClashEventMessage.watchLogs,
      level,
      protocol: ClashEventMessage,
    );
  }

  Stream<Connections> watchConnections(Duration interval) {
    return messager.sendMessageStream(
      ClashEventMessage.watchConnections,
      interval,
      unique: true,
      protocol: ClashEventMessage,
    );
  }

  FutureOr<void> updateCurrentConfig(String url) {
    return messager.sendMessage(
      ClashEventMessage.updateCurrentConfig,
      url,
      protocol: ClashEventMessage,
    );
  }

  Future<String?> getCurrentConfig() {
    return messager.sendMessage(
      ClashEventMessage.getCurrentConfig,
      null,
      protocol: ClashEventMessage,
    );
  }
}

// ignore_for_file: annotate_overrides
// ignore_for_file: curly_braces_in_flow_control_structures
enum ConfigsEventMessage {
  getConfigsCurrent,
  addNewConfigUrl,
  removeConfigUrl,
  updateConfigsUrl,
  getConfig,
  setConfigDateTime;

  static ResolveItem getResolve({required ConfigsEvent configsEvent}) {
    return ResolveItem(
      protocol: ConfigsEventMessage,
      protocolFns: [
        (args) => configsEvent.getConfigsCurrent(),
        (args) => configsEvent.addNewConfigUrl(args.$1, args.$2, args.$3),
        configsEvent.removeConfigUrl,
        (args) => configsEvent.updateConfigsUrl(args.$1, args.$2),
        configsEvent.getConfig,
        (args) => configsEvent.setConfigDateTime(args.$1, args.$2),
      ],
    );
  }

  static IsolateRunner<ConfigsEventMessager> getMessage<T>(
    RemoteServer<T> remoteServer,
  ) {
    return IsolateRunner(
      remoteServer: remoteServer,
      messageItem: ConfigsEventMessager(),
    );
  }

  static ConfigsEventMessager getResolveMessage() => ConfigsEventMessager();
}

final class ConfigsEventMessager extends MessageItem
    with ConfigsEventMessagerMixin
    implements ConfigsEvent {
  ConfigsEventMessager();
}

mixin ConfigsEventMessagerMixin implements ConfigsEvent {
  final Type protocol = ConfigsEventMessage;
  Messager get messager;
  Stream<ConfigsCurrent> getConfigsCurrent() {
    return messager.sendMessageStream(
      ConfigsEventMessage.getConfigsCurrent,
      null,
      protocol: ConfigsEventMessage,
    );
  }

  FutureOr<void> addNewConfigUrl(String url, int updateInterval, String? name) {
    return messager.sendMessage(ConfigsEventMessage.addNewConfigUrl, (
      url,
      updateInterval,
      name,
    ), protocol: ConfigsEventMessage);
  }

  FutureOr<void> removeConfigUrl(String url) {
    return messager.sendMessage(
      ConfigsEventMessage.removeConfigUrl,
      url,
      protocol: ConfigsEventMessage,
    );
  }

  FutureOr<void> updateConfigsUrl(String url, ConfigTable config) {
    return messager.sendMessage(ConfigsEventMessage.updateConfigsUrl, (
      url,
      config,
    ), protocol: ConfigsEventMessage);
  }

  FutureOr<ConfigTable?> getConfig(String url) {
    return messager.sendMessage(
      ConfigsEventMessage.getConfig,
      url,
      protocol: ConfigsEventMessage,
    );
  }

  FutureOr<void> setConfigDateTime(String url, String info) {
    return messager.sendMessage(ConfigsEventMessage.setConfigDateTime, (
      url,
      info,
    ), protocol: ConfigsEventMessage);
  }
}
