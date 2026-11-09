///
/// @AppColorsReg({
/// "textColor": Color(0xFF343434),
/// })
///
class AppColorsReg<T> {
  final Map<String, T> colors;
  final String? className;
  const AppColorsReg(this.colors, [this.className]);
}
