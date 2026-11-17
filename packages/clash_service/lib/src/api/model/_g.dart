import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part '_g.g.dart';
part 'connections.dart';
part 'delay.dart';
part 'history.dart';
part 'profile.dart';
part 'proxy_item.dart';
part 'traffic.dart';


class ProxiesData {
  const ProxiesData({required this.history, required this.proxies});
  final List<History> history;
  final List<ProxyItem> proxies;
}


bool proxyHasData(ProxyItem data) {
  return data.all != null && data.name != null && data.type != null;
}