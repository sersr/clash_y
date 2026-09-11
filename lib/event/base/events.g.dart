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
  reloadConfigs,
  getRules,
  getConfigs,
  getDelay,
  watchConnections,
}

enum ConfigsEventMessage {
  getConfigsCurrent,
  addNewConfigUrl,
  removeConfigUrl,
  updateConfigsUrl,
  getCurrentConfig,
  updateCurrentConfig,
}

/// 主入口
abstract class MultiEventDefaultMessagerMain
    with
        ListenMixin,
        SendEventMixin,
        SendMultiServerMixin,
        ClashEventMessager,
        ConfigsEventMessager {
  RemoteServer get eventDefaultRemoteServer;
  Map<String, RemoteServer> regRemoteServer() {
    return super.regRemoteServer()..['eventDefault'] = eventDefaultRemoteServer;
  }
}

/// eventDefault Server
abstract class MultiEventDefaultResolveMain
    with ListenMixin, Resolve, ClashEventResolve, ConfigsEventResolve {
  MultiEventDefaultResolveMain({required ServerConfigurations configurations})
    : remoteSendHandle = configurations.sendHandle;
  final SendHandle remoteSendHandle;
}

mixin ClashEventResolve on Resolve implements ClashEvent {
  Map<String, List<Type>> getResolveProtocols() {
    return super.getResolveProtocols()
      ..putIfAbsent('eventDefault', () => []).add(ClashEventMessage);
  }

  Map<Type, List<Function>> resolveFunctionIterable() {
    return super.resolveFunctionIterable()
      ..[ClashEventMessage] = [
        (args) => getProxies(),
        (args) => selectProxy(args.$1, args.$2),
        resetConfigs,
        (args) => reloadConfigs(args.$1, args.$2),
        (args) => getRules(),
        (args) => getConfigs(),
        (args) => getDelay(args.$1, args.$2, args.$3),
        (args) => watchConnections(),
      ];
  }
}

/// implements [ClashEvent]
mixin ClashEventMessager on SendEvent, Messager {
  String get eventDefault => 'eventDefault';
  Map<String, List<Type>> getProtocols() {
    return super.getProtocols()
      ..putIfAbsent(eventDefault, () => []).add(ClashEventMessage);
  }

  FutureOr<ProxiesData?> getProxies() {
    return sendMessage(
      ClashEventMessage.getProxies,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<void> selectProxy(String selector, String proxy) {
    return sendMessage(ClashEventMessage.selectProxy, (
      selector,
      proxy,
    ), serverName: eventDefault);
  }

  FutureOr<void> resetConfigs(ConfigsData data) {
    return sendMessage(
      ClashEventMessage.resetConfigs,
      data,
      serverName: eventDefault,
    );
  }

  FutureOr<void> reloadConfigs(bool force, String path) {
    return sendMessage(ClashEventMessage.reloadConfigs, (
      force,
      path,
    ), serverName: eventDefault);
  }

  FutureOr<void> getRules() {
    return sendMessage(
      ClashEventMessage.getRules,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<void> getConfigs() {
    return sendMessage(
      ClashEventMessage.getConfigs,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<Delay?> getDelay(String proxy, int timeout, String testUrl) {
    return sendMessage(ClashEventMessage.getDelay, (
      proxy,
      timeout,
      testUrl,
    ), serverName: eventDefault);
  }

  Stream<Connections> watchConnections() {
    return sendMessageStream(
      ClashEventMessage.watchConnections,
      null,
      serverName: eventDefault,
    );
  }
}
mixin ConfigsEventResolve on Resolve implements ConfigsEvent {
  Map<String, List<Type>> getResolveProtocols() {
    return super.getResolveProtocols()
      ..putIfAbsent('eventDefault', () => []).add(ConfigsEventMessage);
  }

  Map<Type, List<Function>> resolveFunctionIterable() {
    return super.resolveFunctionIterable()
      ..[ConfigsEventMessage] = [
        (args) => getConfigsCurrent(),
        (args) => addNewConfigUrl(args.$1, args.$2, args.$3),
        removeConfigUrl,
        (args) => updateConfigsUrl(args.$1, args.$2),
        (args) => getCurrentConfig(),
        updateCurrentConfig,
      ];
  }
}

/// implements [ConfigsEvent]
mixin ConfigsEventMessager on SendEvent, Messager {
  String get eventDefault => 'eventDefault';
  Map<String, List<Type>> getProtocols() {
    return super.getProtocols()
      ..putIfAbsent(eventDefault, () => []).add(ConfigsEventMessage);
  }

  Stream<ConfigsCurrent> getConfigsCurrent() {
    return sendMessageStream(
      ConfigsEventMessage.getConfigsCurrent,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<void> addNewConfigUrl(String url, int updateInterval, String? name) {
    return sendMessage(ConfigsEventMessage.addNewConfigUrl, (
      url,
      updateInterval,
      name,
    ), serverName: eventDefault);
  }

  FutureOr<void> removeConfigUrl(String url) {
    return sendMessage(
      ConfigsEventMessage.removeConfigUrl,
      url,
      serverName: eventDefault,
    );
  }

  FutureOr<void> updateConfigsUrl(String url, ConfigTable config) {
    return sendMessage(ConfigsEventMessage.updateConfigsUrl, (
      url,
      config,
    ), serverName: eventDefault);
  }

  FutureOr<String?> getCurrentConfig() {
    return sendMessage(
      ConfigsEventMessage.getCurrentConfig,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<void> updateCurrentConfig(String url) {
    return sendMessage(
      ConfigsEventMessage.updateCurrentConfig,
      url,
      serverName: eventDefault,
    );
  }
}
