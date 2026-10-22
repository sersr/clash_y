import 'package:flutter/widgets.dart';

extension ScreenExt on num {
  double get h => toDouble();
  double get w => toDouble();
  double get sp => toDouble();
  double get r => toDouble();

  Widget get horizontalSpace => SizedBox(width: toDouble());
  Widget get verticalSpace => SizedBox(height: toDouble());
}

extension Tr on String {
  String get tr => this;
}
