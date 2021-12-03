// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// Generator: IsolateEventGeneratorForAnnotation
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
  watchConnections
}
enum ConfigsEventMessage {
  getConfigsCurrent,
  addNewConfigUrl,
  removeConfigUrl,
  updateConfigsUrl,
  getCurrentConfig,
  updateCurrentConfig
}

abstract class EventResolveMain extends Event
    with ListenMixin, Resolve, ClashEventResolve, ConfigsEventResolve {}

abstract class EventMessagerMain extends Event
    with SendEvent, ClashEventMessager, ConfigsEventMessager {}

mixin ClashEventResolve on Resolve implements ClashEvent {
  late final _clashEventResolveFuncList = List<DynamicCallback>.unmodifiable([
    _getProxies_0,
    _selectProxy_1,
    _resetConfigs_2,
    _reloadConfigs_3,
    _getRules_4,
    _getConfigs_5,
    _getDelay_6,
    _watchConnections_7
  ]);
  bool onClashEventResolve(message) => false;
  @override
  bool resolve(resolveMessage) {
    if (resolveMessage is IsolateSendMessage) {
      final type = resolveMessage.type;
      if (type is ClashEventMessage) {
        dynamic result;
        try {
          if (onClashEventResolve(resolveMessage)) return true;
          result = _clashEventResolveFuncList
              .elementAt(type.index)(resolveMessage.args);
          receipt(result, resolveMessage);
        } catch (e) {
          receipt(result, resolveMessage, e);
        }
        return true;
      }
    }
    return super.resolve(resolveMessage);
  }

  FutureOr<ProxiesData?> _getProxies_0(args) => getProxies();
  FutureOr<void> _selectProxy_1(args) => selectProxy(args[0], args[1]);
  FutureOr<void> _resetConfigs_2(args) => resetConfigs(args);
  FutureOr<void> _reloadConfigs_3(args) => reloadConfigs(args[0], args[1]);
  FutureOr<void> _getRules_4(args) => getRules();
  FutureOr<void> _getConfigs_5(args) => getConfigs();
  FutureOr<Delay?> _getDelay_6(args) => getDelay(args[0], args[1], args[2]);
  Stream<Connections> _watchConnections_7(args) => watchConnections();
}

/// implements [ClashEvent]
mixin ClashEventMessager on SendEvent {
  SendEvent get sendEvent;
  String get eventDefault => 'eventDefault';
  Iterable<Type> getProtocols(String name) sync* {
    if (name == eventDefault) yield ClashEventMessage;
    yield* super.getProtocols(name);
  }

  FutureOr<ProxiesData?> getProxies() {
    return sendEvent.sendMessage(ClashEventMessage.getProxies, null,
        isolateName: eventDefault);
  }

  FutureOr<void> selectProxy(String selector, String proxy) {
    return sendEvent.sendMessage(
        ClashEventMessage.selectProxy, [selector, proxy],
        isolateName: eventDefault);
  }

  FutureOr<void> resetConfigs(ConfigsData data) {
    return sendEvent.sendMessage(ClashEventMessage.resetConfigs, data,
        isolateName: eventDefault);
  }

  FutureOr<void> reloadConfigs(bool force, String path) {
    return sendEvent.sendMessage(ClashEventMessage.reloadConfigs, [force, path],
        isolateName: eventDefault);
  }

  FutureOr<void> getRules() {
    return sendEvent.sendMessage(ClashEventMessage.getRules, null,
        isolateName: eventDefault);
  }

  FutureOr<void> getConfigs() {
    return sendEvent.sendMessage(ClashEventMessage.getConfigs, null,
        isolateName: eventDefault);
  }

  FutureOr<Delay?> getDelay(String proxy, int timeout, String testUrl) {
    return sendEvent.sendMessage(
        ClashEventMessage.getDelay, [proxy, timeout, testUrl],
        isolateName: eventDefault);
  }

  Stream<Connections> watchConnections() {
    return sendEvent.sendMessageStream(ClashEventMessage.watchConnections, null,
        isolateName: eventDefault);
  }
}
mixin ConfigsEventResolve on Resolve implements ConfigsEvent {
  late final _configsEventResolveFuncList = List<DynamicCallback>.unmodifiable([
    _getConfigsCurrent_0,
    _addNewConfigUrl_1,
    _removeConfigUrl_2,
    _updateConfigsUrl_3,
    _getCurrentConfig_4,
    _updateCurrentConfig_5
  ]);
  bool onConfigsEventResolve(message) => false;
  @override
  bool resolve(resolveMessage) {
    if (resolveMessage is IsolateSendMessage) {
      final type = resolveMessage.type;
      if (type is ConfigsEventMessage) {
        dynamic result;
        try {
          if (onConfigsEventResolve(resolveMessage)) return true;
          result = _configsEventResolveFuncList
              .elementAt(type.index)(resolveMessage.args);
          receipt(result, resolveMessage);
        } catch (e) {
          receipt(result, resolveMessage, e);
        }
        return true;
      }
    }
    return super.resolve(resolveMessage);
  }

  Stream<ConfigsCurrent> _getConfigsCurrent_0(args) => getConfigsCurrent();
  FutureOr<void> _addNewConfigUrl_1(args) =>
      addNewConfigUrl(args[0], args[1], args[2]);
  FutureOr<void> _removeConfigUrl_2(args) => removeConfigUrl(args);
  FutureOr<void> _updateConfigsUrl_3(args) =>
      updateConfigsUrl(args[0], args[1]);
  FutureOr<String?> _getCurrentConfig_4(args) => getCurrentConfig();
  FutureOr<void> _updateCurrentConfig_5(args) => updateCurrentConfig(args);
}

/// implements [ConfigsEvent]
mixin ConfigsEventMessager on SendEvent {
  SendEvent get sendEvent;
  String get eventDefault => 'eventDefault';
  Iterable<Type> getProtocols(String name) sync* {
    if (name == eventDefault) yield ConfigsEventMessage;
    yield* super.getProtocols(name);
  }

  Stream<ConfigsCurrent> getConfigsCurrent() {
    return sendEvent.sendMessageStream(
        ConfigsEventMessage.getConfigsCurrent, null,
        isolateName: eventDefault);
  }

  FutureOr<void> addNewConfigUrl(String url, int updateInterval, String? name) {
    return sendEvent.sendMessage(
        ConfigsEventMessage.addNewConfigUrl, [url, updateInterval, name],
        isolateName: eventDefault);
  }

  FutureOr<void> removeConfigUrl(String url) {
    return sendEvent.sendMessage(ConfigsEventMessage.removeConfigUrl, url,
        isolateName: eventDefault);
  }

  FutureOr<void> updateConfigsUrl(String url, ConfigTable config) {
    return sendEvent.sendMessage(
        ConfigsEventMessage.updateConfigsUrl, [url, config],
        isolateName: eventDefault);
  }

  FutureOr<String?> getCurrentConfig() {
    return sendEvent.sendMessage(ConfigsEventMessage.getCurrentConfig, null,
        isolateName: eventDefault);
  }

  FutureOr<void> updateCurrentConfig(String url) {
    return sendEvent.sendMessage(ConfigsEventMessage.updateCurrentConfig, url,
        isolateName: eventDefault);
  }
}
mixin MultiEventDefaultMessagerMixin
    on SendEvent, ListenMixin, SendMultiServerMixin /*impl*/ {
  String get defaultSendPortOwnerName => 'eventDefault';
  Future<RemoteServer> createRemoteServerEventDefault();

  Iterable<MapEntry<String, CreateRemoteServer>>
      createRemoteServerIterable() sync* {
    yield MapEntry('eventDefault', createRemoteServerEventDefault);
    yield* super.createRemoteServerIterable();
  }

  Iterable<MapEntry<String, List<Type>>> allProtocolsItreable() sync* {
    yield const MapEntry(
        'eventDefault', [ClashEventMessage, ConfigsEventMessage]);
    yield* super.allProtocolsItreable();
  }
}

abstract class MultiEventDefaultResolveMain
    with
        ListenMixin,
        Resolve,
        MultiEventDefaultMixin,
        ClashEventResolve,
        ConfigsEventResolve {}

mixin MultiEventDefaultMixin on Resolve {
  void onResumeListen() {
    if (remoteSendPort != null)
      remoteSendPort!.send(SendPortName(
        'eventDefault',
        localSendPort,
        protocols: [ClashEventMessage, ConfigsEventMessage],
      ));
    super.onResumeListen();
  }
}
