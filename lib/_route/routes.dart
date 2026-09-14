import 'package:flutter/widgets.dart';
import 'package:flutter_nop/router.dart';
import 'package:nop_annotations/nop_annotations.dart';

import '../pages/home/home.dart';

part 'routes.g.dart';

@RouterMain(page: Home)
// ignore: unused_element
abstract final class _Routes {}

NRouter get router => Routes.router;
