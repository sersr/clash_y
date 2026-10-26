import 'package:material_ui/material_ui.dart';

///
class SafeUI extends StatelessWidget {
  const SafeUI({
    super.key,
    required this.child,
    this.bottom = true,
    this.top = true,
  });

  final Widget child;
  final bool bottom;
  final bool top;
  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    var padding = EdgeInsets.fromViewPadding(
      view.padding,
      view.devicePixelRatio,
    );
    if (padding == EdgeInsets.zero) {
      final ges = EdgeInsets.fromViewPadding(
        view.systemGestureInsets,
        view.devicePixelRatio,
      );
      padding = ges;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: padding.left,
        top: top ? padding.top : 0.0,
        right: padding.right,
        bottom: bottom ? padding.bottom : 0.0,
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: top,
        removeBottom: bottom,
        removeLeft: true,
        removeRight: true,
        child: child,
      ),
    );
  }
}
