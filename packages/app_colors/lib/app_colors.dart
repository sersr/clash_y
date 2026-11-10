

/// 
/// @_colors
/// library;
/// 
/// final class _Colors {
///   final Color light;
///   final Color dark;
///   const new({required this.light, required this.dark});
/// }
/// 
/// const _colors = AppColorsReg<_Colors>({
///   "textFieldBorderColor": .new(light: .new(0x496B6B6B), dark: .new(0xFFDDDDDD)),
///   "textFieldBorderColorFocus": .new(
///     light: .new(0xFF1D79E2),
///     dark: .new(0xFF1D79E2),
///   ),
/// });
/// 
class AppColorsReg<T> {
  final Map<String, T> colors;
  final String? className;
  const AppColorsReg(this.colors, [this.className]);
}
