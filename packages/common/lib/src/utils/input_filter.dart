import 'package:flutter/services.dart';

import 'number_format.dart';

class NumberPrefixFormater extends TextInputFormatter {
  const NumberPrefixFormater({
    this.prefix = '^\\\$',
    this.iPrefix = '\$',
    this.length = 2,
    this.max = double.maxFinite,
  });
  final String prefix;
  final String iPrefix;
  final double max;
  final int length;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final t = text.replaceFirst(RegExp(prefix), '').replaceAll(',', '');
    if (double.tryParse(t) case var value?) {
      if (value > max) {
        final nv = '$iPrefix${max.fixStr(length)}';

        return TextEditingValue(
          text: nv,
          composing: TextRange.empty,
          selection: TextSelection.collapsed(offset: nv.length),
        );
      }

      if (!text.startsWith(RegExp(prefix))) {
        final nv = '$iPrefix${value.fixStr(length)}';
        return newValue.copyWith(
          text: nv,
          composing: TextRange.empty,
          selection: TextSelection.collapsed(offset: nv.length),
        );
      } else {
        final v = t.split('.');
        if (v case [var _, ..., var last]) {
          if (last.length > length) {
            return oldValue;
          }
        }
      }
      return newValue;
    } else if (text == iPrefix || text.isEmpty) {
      return newValue;
    }
    return oldValue;
  }
}

class NumberFormater extends TextInputFormatter {
  const NumberFormater({this.isDouble = true});
  final bool isDouble;
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (!isDouble && int.tryParse(text) != null ||
        isDouble && double.tryParse(text) != null) {
      return newValue;
    } else if (text.isEmpty) {
      return newValue;
    }
    return oldValue;
  }
}

const intMax = 1 << 63 - 1;

class IntPrefixFormater extends TextInputFormatter {
  const IntPrefixFormater({
    this.prefix = r'^\$',
    this.iPrefix = r'$',
    this.max = intMax,
  });
  final String prefix;
  final String iPrefix;
  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final t = text.replaceFirst(RegExp(prefix), '');
    if (int.tryParse(t) case var value?) {
      if (value > max) {
        final nv = '$iPrefix$max';

        return TextEditingValue(
          text: nv,
          composing: TextRange.empty,
          selection: TextSelection.collapsed(offset: nv.length),
        );
      }

      if (!text.startsWith(RegExp(prefix))) {
        final nv = '$iPrefix$value';
        return newValue.copyWith(
          text: nv,
          composing: TextRange.empty,
          selection: TextSelection.collapsed(offset: nv.length),
        );
      }
      return newValue;
    } else if (text == iPrefix || text.isEmpty) {
      return newValue;
    }
    return oldValue;
  }
}
