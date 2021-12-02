import 'package:json_annotation/json_annotation.dart';

part 'history.g.dart';

@JsonSerializable(explicitToJson: true)
class History {
  const History({
    this.history,
    this.name,
    this.type,
    this.udp,
  });
  @JsonKey(name: 'history')
  final List<HistoryHistory?>? history;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'type')
  final String? type;
  @JsonKey(name: 'udp')
  final bool? udp;

  factory History.fromJson(Map<String,dynamic> json) => _$HistoryFromJson(json);
  Map<String,dynamic> toJson() => _$HistoryToJson(this);
}

@JsonSerializable(explicitToJson: true)
class HistoryHistory {
  const HistoryHistory({
    this.time,
    this.delay,
  });
  @JsonKey(name: 'time')
  final String? time;
  @JsonKey(name: 'delay')
  final int? delay;

  factory HistoryHistory.fromJson(Map<String,dynamic> json) => _$HistoryHistoryFromJson(json);
  Map<String,dynamic> toJson() => _$HistoryHistoryToJson(this);
}

