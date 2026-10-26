import 'package:flutter/widgets.dart';

/// 使用场景：隐藏虚拟键盘
class UnFocus extends StatelessWidget {
  const UnFocus({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (context) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (_) {
              Focus.of(context).requestFocus();
            },
            child: child,
          );
        },
      ),
    );
  }
}
