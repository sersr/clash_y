// ignore_for_file: library_private_types_in_public_api

import 'package:material_ui/material_ui.dart';

final class _ColorGroup {
  final Color light;
  final Color dark;
  const new({required this.light, required this.dark});
}

/// 1
const colorsMap = <String, _ColorGroup>{
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
};

/// 2
final class ColorsFields {
  const new();

  final _ColorGroup textFieldBorderColor = const .new(
    light: .new(0x496B6B6B),
    dark: .new(0xFFDDDDDD),
  );

  final _ColorGroup textFieldBorderColorFocus = const .new(
    light: .new(0xFF1D79E2),
    dark: .new(0xFF1D79E2),
  );

  final _ColorGroup editTextColor = const .new(
    light: .new(0xFF333333),
    dark: .new(0xFFDDDDDD),
  );
  final _ColorGroup editTextHintColor = const .new(
    light: .fromARGB(255, 160, 160, 160),
    dark: .fromARGB(100, 100, 100, 100),
  );

  final _ColorGroup inkOverlayColor = const .new(
    light: Color(0x35FFFFFF),
    dark: Color(0x35FFFFFF),
  );

  final _ColorGroup inkBackgroundColor = const .new(
    light: Colors.blue,
    dark: Colors.blue,
  );
  final _ColorGroup inkTextColor = const .new(
    light: .new(0xFFFFFFFF),
    dark: .new(0xFF333333),
  );
  final _ColorGroup inkCancelOverlayColor = const .new(
    light: Color(0x35A0A0A0),
    dark: Color(0x35A0A0A0),
  );
}
