@_colors
library;

import 'dart:math' as math;

import 'package:app_colors/app_colors.dart';
import 'package:material_ui/material_ui.dart';

part 'color_ext.g.dart';

final class _Colors {
  final Color light;
  final Color dark;
  const new({required this.light, required this.dark});
}

const _colors = AppColorsReg<_Colors>({
  "textFieldBorderColor": .new(light: .new(0x496B6B6B), dark: .new(0xFFDDDDDD)),
  "textFieldBorderColorFocus": .new(
    light: .new(0xFF1D79E2),
    dark: .new(0xFF1D79E2),
  ),
  "editTextColor": .new(light: .new(0xFF333333), dark: .new(0xFFDDDDDD)),
  "editTextHintColor": .new(
    light: .fromARGB(255, 160, 160, 160),
    dark: .fromARGB(100, 100, 100, 100),
  ),
  "inkOverlayColor": .new(light: Color(0x35FFFFFF), dark: Color(0x35FFFFFF)),
  "inkBackgroundColor": .new(light: Colors.blue, dark: Colors.blue),
  "inkTextColor": .new(light: .new(0xFFFFFFFF), dark: .new(0xFF333333)),
  "inkCancelOverlayColor": .new(
    light: Color(0x35A0A0A0),
    dark: Color(0x35A0A0A0),
  ),
});

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
