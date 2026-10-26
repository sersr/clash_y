import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../ext/screen_ext.dart';
import 'pop_dialog.dart';

String? _lastMsg;
Timer? _timer;

void showMsg(String text) {
  if (text.isEmpty) return;
  if (text == _lastMsg) return;

  _lastMsg = text;
  _timer?.cancel();
  _timer = Timer(const Duration(seconds: 1, milliseconds: 500), () {
    _lastMsg = null;
  });

  showMsgD(text);
}

void showMsgD(String info, {Alignment? alignment, String? icon}) {
  final child = Text(
    info,
    style: TextStyle(
      color: Colors.white,
      fontSize: 16.sp,
      fontWeight: FontWeight.w500,
    ),
    textAlign: TextAlign.center,
  );

  Widget body = Material(
    borderRadius: BorderRadius.circular(16.r),
    color: Colors.black.withValues(alpha: 0.7),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 30.w, vertical: 16.h),
      child: child,
    ),
  );
  body = Container(
    padding: EdgeInsets.symmetric(horizontal: 30.w),
    child: body,
  );

  popDialog(body, alignment: Alignment.center);
}
