import 'package:flutter/services.dart';
import 'package:common/common.dart';

import '../widget/pop_msg.dart';

Future<void> copy(String data, {bool show = true}) async {
  await Clipboard.setData(ClipboardData(text: data));
  if (show) showMsg("Copy success.");
}
