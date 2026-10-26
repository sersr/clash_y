import 'package:intl/intl.dart';

final usdFromat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
final usdFromat4 = NumberFormat.currency(symbol: '\$', decimalDigits: 4);
final usdFromatZero = NumberFormat.currency(symbol: '\$');
final fromatZero = NumberFormat.currency(symbol: '');

extension NumberFormatExt on num? {
  String get price {
    final price = usdFromat.format(this ?? 0);
    return price;
  }

  String fix(int length) {
    final format = NumberFormat.decimalPatternDigits(decimalDigits: length);

    return format.format(this ?? 0);
  }

  String fixStr(int length) {
    return _removeZero(fix(length));
  }

  int get manLength {
    final v = '${this ?? 0}'.split('.');
    if (v case [var _, ..., var last]) {
      return last.length;
    }
    return 0;
  }

  int get man2Length {
    final v = '${this ?? 0}'.split('.');
    if (v case [var _, ..., var last]) {
      if (last.length < 2) return 2;
      return last.length;
    }
    return 2;
  }

  String get priceZero {
    final price = usdFromatZero.format(this ?? 0);
    return _removeZero(price);
  }

  String get price4Zero {
    final price = usdFromat4.format(this ?? 0);
    return _removeZero(price);
  }

  String get k {
    if (this case var value?) {
      if (value == 1000) return '1000';
      final kv = value ~/ 1000;
      if (kv > 0) {
        return '${kv}k';
      }
      return '$value';
    }
    return '';
  }

  String get kd {
    if (this case var value?) {
      if (value == 1000) return '1000';
      final kv = value / 1000;
      if (kv > 0) {
        return '${kv.toStringAsFixed(1)}k';
      }
      return '$value';
    }
    return '';
  }

  String get per {
    if (this case var per?) {
      return '${(per * 100).priceBase}%';
    }

    return '';
  }

  static String _removeZero(String text) {
    return text.replaceAllMapped(RegExp('\\.([0-9]*?)0+\$'), (match) {
      final value = match[1] ?? '';
      if (value.isEmpty) {
        return '';
      }

      return '.$value';
    });
  }

  String get priceBase {
    final price = fromatZero.format(this ?? 0);
    return _removeZero(price);
  }
}

final numberReg = RegExp('^[0-9]*\$');

extension PriceStringExt on String? {
  String get price {
    if (this case String v) {
      return '\$$v';
    }

    return '\$0';
  }

  bool get isNumberOrEmpty {
    if (this case var v?) {
      if (numberReg.hasMatch(v)) return true;
    }
    return false;
  }

  String get privacyName {
    return this ?? '';
    // if (this case var v? when v.isNotEmpty) {
    //   final cs = v.characters;
    //   if (cs.length < 7) {
    //     return v;
    //   }

    //   final prefix = cs.getRange(0, 7);
    //   return '$prefix***';
    // }
    // return '';
  }
}
