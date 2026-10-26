import 'dart:async';

import 'package:common/src/navigator_observer.dart';
import 'package:material_ui/material_ui.dart';

void popDialog(
  Widget body, {
  Duration duration = const Duration(milliseconds: 2000),
  Alignment? alignment = const Alignment(0, -0.2),
}) {
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return _PopMessageEntry(
        body: Container(alignment: alignment, child: body),
        entry: entry,
        duration: duration,
      );
    },
  );
  final overlay = globalObserver.navigator?.overlay;
  if (overlay == null) return;
  overlay.insert(entry);
}

class _PopMessageEntry extends StatefulWidget {
  const _PopMessageEntry({
    required this.body,
    required this.entry,
    required this.duration,
  });

  final Widget body;
  final Duration duration;
  final OverlayEntry entry;

  @override
  State<_PopMessageEntry> createState() => __PopMessageEntryState();
}

class __PopMessageEntryState extends State<_PopMessageEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late Animation<double> fade;
  late Animation<double> scale;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    final curve = CurveTween(curve: Curves.easeInOut);
    fade = curve.animate(controller);
    scale = Tween(begin: 0.8, end: 1.0).chain(curve).animate(controller);

    start();
  }

  void start() {
    controller.forward().whenComplete(closing);
  }

  void closing() {
    Timer(widget.duration, () {
      controller.reverse().whenComplete(() => widget.entry.remove());
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: scale,
      child: FadeTransition(opacity: fade, child: widget.body),
    );
  }
}
