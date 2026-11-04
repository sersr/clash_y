import 'dart:math' as math;

import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';

final class CT {
  final Color light;
  final Color dark;

  const new({required this.light, required this.dark});

  const new color(Color color) : light = color, dark = color;

  Color get color {
    final context = GlobalContext.context;
    final mode = MediaQuery.platformBrightnessOf(context);
    if (mode == .dark) {
      return dark;
    }

    return light;
  }

  static const CT textFieldBorderColor = .new(
    light: .new(0x496B6B6B),
    dark: .new(0xFFDDDDDD),
  );

  static const CT textFieldBorderColorFocus = .new(
    light: .new(0xFF1D79E2),
    dark: .new(0xFF1D79E2),
  );
}

extension ColorString on String {
  Color get color {
    final value = replaceFirst('#', '').characters;
    Color? data;
    switch (value.length) {
      case 3:
        final colors = value
            .map((e) => int.tryParse('$e$e', radix: 16))
            .whereType<int>()
            .toList();
        if (colors.length == 3) {
          data = Color.fromARGB(255, colors[0], colors[1], colors[2]);
        }
        break;
      case 4:
        final colors = value
            .map((e) => int.tryParse('$e$e', radix: 16))
            .whereType<int>()
            .toList();
        if (colors.length == 4) {
          data = Color.fromARGB(colors[0], colors[1], colors[2], colors[3]);
        }
        break;
      case 6:
        final colors = List.filled(3, 0);
        for (var i = 0; i < value.length;) {
          final end = math.min(i + 2, value.length);
          colors[i ~/ 2] =
              int.tryParse(value.getRange(i, end).toString(), radix: 16) ?? 0;
          i = end;
        }
        if (colors.length == 3) {
          data = Color.fromARGB(255, colors[0], colors[1], colors[2]);
        }
        break;
      case 8:
        final colors = List.filled(4, 0);
        for (var i = 0; i < value.length;) {
          final end = math.min(i + 2, value.length);
          colors[i ~/ 2] =
              int.tryParse(value.getRange(i, end).toString(), radix: 16) ?? 0;
          i = end;
        }
        if (colors.length == 4) {
          data = Color.fromARGB(colors[0], colors[1], colors[2], colors[3]);
        }
        break;
      default:
    }

    return data!;
  }
}
