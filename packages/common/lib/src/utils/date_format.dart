import 'dart:math' as math;


import 'package:common/src/navigator_observer.dart';
import 'package:intl/intl.dart';

String formatDate(DateTime date, {String format = 'yyyy-MM-dd'}) {
  try {
    final fm = DateFormat(format, Nav.locale?.toString());
    return fm.format(date);
  } catch (e) {
    final fm = DateFormat(format);
    return fm.format(date);
  }
}

String formatDateHmWMD(DateTime date) {
  return formatDate(date, format: 'HH:mm EEE,MMM d');
}

String formatDateYMd(DateTime date) {
  return formatDate(date, format: 'yyyy MM-dd');
}

String formatDateYM(DateTime date) {
  return formatDate(date, format: 'yyyyMM');
}

String formatDateDot(DateTime date) {
  return formatDate(date, format: 'yyyy.MM.dd');
}

String formatDateYMdHms(DateTime date) {
  return formatDate(date, format: 'yyyy-MM-dd HH:mm:ss');
}

String formatDateYMdHm(DateTime date) {
  return formatDate(date, format: 'yyyy-MM-dd HH:mm');
}

String formatDateYMdHmsDot(DateTime date) {
  return formatDate(date, format: 'yyyy.MM.dd HH:mm:ss');
}

// String formatDateMd(DateTime date) {
//   return formatDate(date, format: t.dateFormat.Md)!;
// }

String formatDateDMY(DateTime date) {
  return formatDate(date, format: 'dd-MM-yyyy');
}

String formatDateChart(DateTime date) {
  return formatDate(date, format: 'MM.dd');
}

String formatDateSelection(DateTime date) {
  return formatDate(date, format: 'MM-dd');
}

String formatDateWMD(DateTime date) {
  return formatDate(date, format: 'EEE,MMM d');
}

String formatColon(DateTime date) {
  return formatDate(date, format: 'HH:mm:ss');
}

String formatDateHm(DateTime date) {
  return formatDate(date, format: 'HH:mm');
}

String formatDateMdDot(DateTime date) {
  return formatDate(date, format: 'MM.dd');
}

String formatDateMdHm(DateTime date) {
  return formatDate(date, format: 'MM.dd HH:mm');
}

String formatDateMdDashHm(DateTime date) {
  return formatDate(date, format: 'MM-dd HH:mm');
}

String formatDuration(Duration duration) {
  final buffer = StringBuffer();
  if (duration.isNegative) {
    buffer.write('-');
    duration = duration.abs();
  }
  if (duration.inHours > 0) {
    final hour = duration.inHours.toString().padLeft(2, '0');
    buffer.write(hour);
    buffer.write(':');
  }
  final minutes = duration.inMicroseconds ~/ Duration.microsecondsPerMinute;
  final seconds = duration.inMicroseconds ~/ Duration.microsecondsPerSecond;
  buffer.write(minutes.remainder(60).toString().padLeft(2, '0'));
  buffer.write(':');
  buffer.write(seconds.remainder(60).toString().padLeft(2, '0'));
  return buffer.toString();
}

/// 如果以`.0`结尾，就去掉
String formatProgress(num value) {
  return formatDProgress(value);
}

// String formatNum(num value) {
//   if (value.abs() > 1000) {
//     final w = value / 10000;
//     final str = formatDProgress(w);
//     return '$str${t.w}';
//   }
//   return formatDProgress(value);
// }

// String formatDoubleNum(num value) {
//   if (value.abs() > 1000) {
//     final w = value / 10000;
//     final str = formatDProgress(w, fix: 2);
//     return '$str${t.w}';
//   }
//   return formatDProgress(value, fix: 2);
// }

String formatDProgress(num value, {int fix = 1}) {
  var str = value.toStringAsFixed(fix);
  return str.replaceAll(RegExp(r'[\.]*(0+)$'), '');
}

extension TimeZoneExt on DateTime {
  int get jsTimeZoneOffset {
    DateTime that = this;
    if (isUtc) {
      that = toLocal();
    }
    return -that.timeZoneOffset.inMinutes;
  }

  String get timeZone {
    DateTime that = this;
    if (isUtc) {
      that = toLocal();
    }
    var duration = that.timeZoneOffset;
    var sign = '+';
    if (duration.isNegative) {
      duration = -duration;
      sign = '-';
    }
    final buffer = StringBuffer();
    buffer.write(sign);
    final hour = duration.inMicroseconds ~/ Duration.microsecondsPerHour;
    buffer.write(hour.remainder(24).toString().padLeft(2, '0'));
    buffer.write(':');
    final minutes = duration.inMicroseconds ~/ Duration.microsecondsPerMinute;
    buffer.write(minutes.remainder(60).toString().padLeft(2, '0'));
    return buffer.toString();
  }
}

String formatLocalNum(String source) {
  // source = '113131311313.0001';
  final isDouble = double.tryParse(source) != null;

  var s = '';
  if (isDouble) {
    final split = source.split('.');
    if (split.length > 1) {
      source = split.first;
      var frac = split[1];
      frac = frac.substring(0, math.min(3, frac.length));
      if (!RegExp(r'0+$').hasMatch(frac)) {
        s = '.$frac';
      }
    }
  }
  final intPart =
      source.replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (match) {
    return ',';
  });
  assert(() {
    if (source != intPart.replaceAll(',', '')) {
      return false;
    }
    return true;
  }());

  // assert(Log.i('dxd $source => $intPart$s'));
  return '$intPart$s';
}
