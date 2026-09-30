part of '_g.dart';

@JsonSerializable(explicitToJson: true)
class WindowRect {
  const WindowRect({
    this.top = 0,
    this.left = 0,
    this.right = 0,
    this.bottom = 0,
  });
  final double top;
  final double left;
  final double right;
  final double bottom;

  static const WindowRect zero = .new();

  Rect get rect => .fromLTRB(left, top, right, bottom);

  factory fromRect(Rect rect) {
    return .new(
      top: rect.top,
      left: rect.left,
      right: rect.right,
      bottom: rect.bottom,
    );
  }

  factory WindowRect.fromJson(Map<String, dynamic> json) =>
      _$WindowRectFromJson(json);
  Map<String, dynamic> toJson() => _$WindowRectToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (runtimeType != other.runtimeType) {
      return false;
    }
    return other is WindowRect &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}
