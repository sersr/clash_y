import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';

import 'impl/dio/clash_request.dart';

class Repository with NopLifecycle {
  static Paths? _paths;
  static Paths get paths => _paths ??= .g();

  late final ClashRequest clashEvent = .new(paths: paths, repo: this);
  Future<void> closeConnection(String id) => clashEvent.closeConnection(id);
}
