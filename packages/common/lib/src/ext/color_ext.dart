// ignore_for_file: library_private_types_in_public_api

// @_colorsMap
@_colors
library;

import 'dart:math' as math;

import 'package:app_colors/app_colors.dart';
import 'package:material_ui/material_ui.dart';

import 'colors.dart';

part 'color_ext.g.dart';

const _colors = AppColorsReg(ColorsFields(), genAnother: true);
// const _colorsMap = AppColorsReg(colorsMap, genAnother: true);

extension ColorWidgetState on Color {
  WidgetStatePropertyAll<Color> get state {
    return .new(this);
  }
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
