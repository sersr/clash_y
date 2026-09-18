// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// Generator: ServerEventGeneratorForAnnotation
// **************************************************************************

// ignore_for_file: annotate_overrides
// ignore_for_file: curly_braces_in_flow_control_structures
enum ConfigsEventMessage {
  getConfigsCurrent,
  addNewConfigUrl,
  removeConfigUrl,
  updateConfigsUrl,
  getConfig,
  setConfigDateTime;

  static ResolveItem getResolve({
    required ConfigsEvent configsEvent,
    TaskCallback? onInit,
    TaskCallback? onClose,
  }) {
    return ResolveItem(
      onInit: onInit,
      onClose: onClose,
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

  static IsolateRunner<ConfigsEventMessager> getMessage(
    RemoteServer remoteServer,
  ) {
    return IsolateRunner(
      remoteServer: remoteServer,
      messageItem: ConfigsEventMessager(),
    );
  }

  static ConfigsEventMessager getResolveMessage(IsolateResolve resolve) {
    final messager = ConfigsEventMessager();
    resolve.connectToMessager(messager);
    return messager;
  }
}

/// implements [ConfigsEvent]
final class ConfigsEventMessager extends MessageItem
    with ConfigsEventMessagerMixin
    implements ConfigsEvent {
  ConfigsEventMessager();
}

/// implements [ConfigsEvent]
mixin ConfigsEventMessagerMixin implements ConfigsEvent {
  final Type protocol = ConfigsEventMessage;
  Messager get messager;
  Stream<ConfigsCurrent> getConfigsCurrent() {
    return messager.sendMessageStream(
      ConfigsEventMessage.getConfigsCurrent,
      null,
      protocol: protocol,
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
