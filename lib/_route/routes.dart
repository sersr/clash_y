import 'package:flutter/widgets.dart';
import 'package:flutter_nop/router.dart';
import 'package:nop/nop.dart';

import '../pages/application_list/application_list.dart';
import '../pages/home/home.dart';

part 'routes.g.dart';

@RouterMain(
  page: Home,
  pages: [RouterPage(name: 'applicationList', page: ApplicationListPage)],
)
// ignore: unused_element
abstract final class _Routes {}

NRouter get router => Routes.router;
