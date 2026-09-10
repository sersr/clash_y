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

mixin ClashEventResolve implements ClashEvent {
  Type get protocol => ClashEventMessage;
  Map<Type, List<Function>> functionMap() {
    return {
      ClashEventMessage: [
        (args) => getProxies(),
        (args) => selectProxy(args[0], args[1]),
        resetConfigs,
        (args) => reloadConfigs(args[0], args[1]),
        (args) => getRules(),
        (args) => getConfigs(),
        (args) => getDelay(args[0], args[1], args[2]),
        (args) => watchConnections(),
      ],
    };
  }
}

/// implements [ClashEvent]
mixin ClashEventMessager {
  Messager get messager;
  String get eventDefault => 'eventDefault';
  Type get protocol => ClashEventMessage;
  Map<String, List<Type>> get protocolMap => {
    'eventDefault': [ClashEventMessage],
  };
  FutureOr<ProxiesData?> getProxies() {
    return messager.sendMessage(
      ClashEventMessage.getProxies,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<void> selectProxy(String selector, String proxy) {
    return messager.sendMessage(ClashEventMessage.selectProxy, [
      selector,
      proxy,
    ], serverName: eventDefault);
  }

  FutureOr<void> resetConfigs(ConfigsData data) {
    return messager.sendMessage(
      ClashEventMessage.resetConfigs,
      data,
      serverName: eventDefault,
    );
  }

  FutureOr<void> reloadConfigs(bool force, String path) {
    return messager.sendMessage(ClashEventMessage.reloadConfigs, [
      force,
      path,
    ], serverName: eventDefault);
  }

  FutureOr<void> getRules() {
    return messager.sendMessage(
      ClashEventMessage.getRules,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<void> getConfigs() {
    return messager.sendMessage(
      ClashEventMessage.getConfigs,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<Delay?> getDelay(String proxy, int timeout, String testUrl) {
    return messager.sendMessage(ClashEventMessage.getDelay, [
      proxy,
      timeout,
      testUrl,
    ], serverName: eventDefault);
  }

  Stream<Connections> watchConnections() {
    return messager.sendMessageStream(
      ClashEventMessage.watchConnections,
      null,
      serverName: eventDefault,
    );
  }
}
mixin ConfigsEventResolve implements ConfigsEvent {
  Type get protocol => ConfigsEventMessage;
  Map<Type, List<Function>> functionMap() {
    return {
      ConfigsEventMessage: [
        (args) => getConfigsCurrent(),
        (args) => addNewConfigUrl(args[0], args[1], args[2]),
        removeConfigUrl,
        (args) => updateConfigsUrl(args[0], args[1]),
        (args) => getCurrentConfig(),
        updateCurrentConfig,
      ],
    };
  }
}

/// implements [ConfigsEvent]
mixin ConfigsEventMessager {
  Messager get messager;
  String get eventDefault => 'eventDefault';
  Type get protocol => ConfigsEventMessage;
  Map<String, List<Type>> get protocolMap => {
    'eventDefault': [ConfigsEventMessage],
  };
  Stream<ConfigsCurrent> getConfigsCurrent() {
    return messager.sendMessageStream(
      ConfigsEventMessage.getConfigsCurrent,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<void> addNewConfigUrl(String url, int updateInterval, String? name) {
    return messager.sendMessage(ConfigsEventMessage.addNewConfigUrl, [
      url,
      updateInterval,
      name,
    ], serverName: eventDefault);
  }

  FutureOr<void> removeConfigUrl(String url) {
    return messager.sendMessage(
      ConfigsEventMessage.removeConfigUrl,
      url,
      serverName: eventDefault,
    );
  }

  FutureOr<void> updateConfigsUrl(String url, ConfigTable config) {
    return messager.sendMessage(ConfigsEventMessage.updateConfigsUrl, [
      url,
      config,
    ], serverName: eventDefault);
  }

  FutureOr<String?> getCurrentConfig() {
    return messager.sendMessage(
      ConfigsEventMessage.getCurrentConfig,
      null,
      serverName: eventDefault,
    );
  }

  FutureOr<void> updateCurrentConfig(String url) {
    return messager.sendMessage(
      ConfigsEventMessage.updateCurrentConfig,
      url,
      serverName: eventDefault,
    );
  }
}
