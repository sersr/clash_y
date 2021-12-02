import 'package:json_annotation/json_annotation.dart';

part 'proxy_item.g.dart';

@JsonSerializable(explicitToJson: true)
class ProxyItem {
  const ProxyItem({
    this.all,
    this.history,
    this.name,
    this.now,
    this.type,
    this.udp,
  });
  @JsonKey(name: 'all')
  final List<dynamic>? all;
  @JsonKey(name: 'history')
  final List<dynamic>? history;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'now')
  final String? now;
  @JsonKey(name: 'type')
  final String? type;
  @JsonKey(name: 'udp')
  final bool? udp;

  factory ProxyItem.fromJson(Map<String,dynamic> json) => _$ProxyItemFromJson(json);
  Map<String,dynamic> toJson() => _$ProxyItemToJson(this);
}

