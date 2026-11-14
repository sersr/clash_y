import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';

class BaseScaffold extends StatelessWidget {
  const new({
    super.key,
    required this.appbar,
    required this.body,
    this.statusBgLight = true,
    this.navBgLight = true,
    this.navBarColor,
    this.backgroundColor,
  });
  final Widget appbar;

  final Widget body;

  final bool statusBgLight;
  final bool navBgLight;
  final Color? navBarColor;
  final Color? backgroundColor;
  @override
  Widget build(BuildContext context) {
    return SystemUI(
      statusBgLight: statusBgLight,
      navBarColor: navBarColor,
      navBgLight: navBgLight,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Column(
          children: [
            appbar,
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
