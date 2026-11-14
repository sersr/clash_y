import 'package:material_ui/material_ui.dart';

class HomeBottomPadding extends InheritedWidget {
  const new({super.key, required super.child, required this.padding});
  final double padding;

  static double homePadding(BuildContext context) {
    final widget = context
        .dependOnInheritedWidgetOfExactType<HomeBottomPadding>();
    return widget?.padding ?? 0.0;
  }

  @override
  bool updateShouldNotify(covariant HomeBottomPadding oldWidget) {
    return padding != oldWidget.padding;
  }
}
