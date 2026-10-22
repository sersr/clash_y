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
}
