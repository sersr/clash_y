import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class SystemUI extends StatelessWidget {
  const SystemUI({
    super.key,
    required this.child,
    this.statusBgLight = true,
    this.navBgLight = true,
    this.navBarColor,
  });

  final Widget child;
  final bool statusBgLight;
  final bool navBgLight;
  final Color? navBarColor;
  @override
  Widget build(BuildContext context) {
    final style = SystemUiOverlayStyle(
      statusBarBrightness: statusBgLight ? Brightness.light : Brightness.dark,
      statusBarIconBrightness:
          statusBgLight ? Brightness.dark : Brightness.light,
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: navBarColor ?? Colors.white,
      systemNavigationBarIconBrightness:
          navBgLight ? Brightness.dark : Brightness.light,
    );

    return AnnotatedRegion(value: style, child: child);
  }
}
