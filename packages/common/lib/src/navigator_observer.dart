import 'package:material_ui/material_ui.dart';
import 'package:flutter/widgets.dart';

BuildContext? get currentContext => globalObserver.navigator?.context;
BuildContext? get overlayContext => globalObserver.navigator?.overlay?.context;

final NavigatorObserver globalObserver = RouteObserver();

abstract final class Nav {
  static Locale? get locale {
    if (currentContext case var currentContext?) {
      return Localizations.maybeLocaleOf(currentContext);
    }
    return null;
  }

  static void back([dynamic result]) {
    globalObserver.navigator?.pop(result);
  }

  static double get screenWidth {
    return MediaQuery.sizeOf(currentContext!).width;
  }

  static double get screenHeight {
    return MediaQuery.sizeOf(currentContext!).height;
  }

  static double get statusBarHeight {
    return MediaQuery.paddingOf(currentContext!).top;
  }
}
