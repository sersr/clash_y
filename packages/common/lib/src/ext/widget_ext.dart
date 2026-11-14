import 'package:material_ui/material_ui.dart';

extension WidgetExt on Widget {
  Expanded get expanded {
    return .new(child: this);
  }
}