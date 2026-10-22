import 'dart:async';
import 'dart:math' as math;

import 'package:common/src/navigator_observer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ext/screen_ext.dart';

Future<void> showLoadingDialog({
  bool barrierDismissible = false,
  Alignment? alignment,
  Color barrierColor = Colors.transparent,
  Duration duration = Duration.zero,
  String? routeName,
}) {
  return showDialog(
    context: currentContext!,
    builder: (context) =>
        LoadingDialog(alignment: alignment, duration: duration),
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    routeSettings: routeName == null ? null : RouteSettings(name: routeName),
  );
}

Future<T> showLoadingDialogScope<T>(
  Future<T> Function(VoidCallback back) task, {
  bool barrierDismissible = false,
  Alignment? alignment,
  Color barrierColor = Colors.transparent,
  Duration duration = Duration.zero,
}) {
  return showDialogScope(
    task,
    dialog: () {
      return showLoadingDialog(
        barrierDismissible: barrierDismissible,
        alignment: alignment,
        duration: duration,
        barrierColor: barrierColor,
      );
    },
  );
}

/// 支持[SynchronousFuture]
Future<T> showDialogScope<T>(
  Future<T> Function(VoidCallback back) task, {
  bool barrierDismissible = false,
  Alignment? alignment,
  Color barrierColor = Colors.transparent,
  required Future<void> Function() dialog,
}) {
  var backed = false;
  var isInit = false;

  void back() {
    if (backed) return;
    backed = true;
    if (isInit) Nav.back();
  }

  // 无操作
  void innerBack() {}

  if (dialogScopeBack case var fn?) {
    fn();
  }

  return runZoned(() {
    final result = task(back);
    result.whenComplete(back);
    if (backed) return result;
    isInit = true;

    runZoned(
      () => dialog().whenComplete(() => backed = true),
      zoneValues: {_dialogScopeZone: innerBack},
    );

    return result;
  }, zoneValues: {_dialogScopeZone: back});
}

VoidCallback? get dialogScopeBack {
  if (Zone.current[_dialogScopeZone] case VoidCallback fn) {
    return fn;
  }
  return null;
}

final _dialogScopeZone = Object();

class LoadingDialog extends StatefulWidget {
  const LoadingDialog({super.key, this.alignment, required this.duration});

  final Alignment? alignment;

  /// 在[duration]时间范围内阻止返回事件
  final Duration duration;

  @override
  State<LoadingDialog> createState() => _LoadingDialogState();
}

class _LoadingDialogState extends State<LoadingDialog> {
  bool canPop = true;

  @override
  void initState() {
    super.initState();
    updatePopState();
  }

  void updatePopState() {
    if (widget.duration > Duration.zero) {
      canPop = false;
      Timer(widget.duration, () {
        if (mounted) {
          canPop = true;
          setState(() {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      child: Loading(alignment: widget.alignment),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key, this.alignment});
  final Alignment? alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment ?? Alignment.center,
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6.r),
          color: Colors.grey.shade800,
        ),
        child: const LoadingWidget.white(stop: false),
      ),
    );
  }
}

final _greyColors = [
  Colors.grey.shade100,
  Colors.grey.shade200,
  Colors.grey.shade300,
  Colors.grey.shade400,
  Colors.grey.shade500,
  Colors.grey.shade600,
  Colors.grey.shade700,
  Colors.grey.shade800,
  Colors.grey.shade900,
];

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({
    super.key,
    required this.stop,
    this.progress = 0,
    this.radius = 18,
    this.childRadius = 5,
    this.colors,
  });
  final bool stop;
  final double progress;
  final double radius;
  final double childRadius;
  final List<Color>? colors;
  const LoadingWidget.white({
    super.key,
    required this.stop,
    this.progress = 0,
    this.radius = 18,
    this.childRadius = 5,
  }) : colors = const [
         Color.fromRGBO(255, 255, 255, 0.1),
         Color.fromRGBO(255, 255, 255, 0.2),
         Color.fromRGBO(255, 255, 255, 0.3),
         Color.fromRGBO(255, 255, 255, 0.42),
         Color.fromRGBO(255, 255, 255, 0.54),
         Color.fromRGBO(255, 255, 255, 0.66),
         Color.fromRGBO(255, 255, 255, 0.78),
         Color.fromRGBO(255, 255, 255, 0.90),
         Colors.white,
       ];
  @override
  Widget build(BuildContext context) {
    final indColors = colors ?? _greyColors;
    return RepaintBoundary(
      child: CircleIndicator(
        stop: stop,
        radius: radius,
        childRadius: childRadius,
        progress: progress,
        duration: const Duration(seconds: 1),
        colors: indColors,

        // ? buildLoading()
        // : Image(
        //     image: const OneFrameAssetProvider(
        //       'assets/images/ic_loading.gif',
        //     ),
        //     height: 64.w,
        //     width: 64.w,
      ),
    );
  }
}

class CircleIndicator extends StatefulWidget {
  const CircleIndicator({
    super.key,
    this.stop = false,
    this.stopAnyTime = false,
    required this.colors,
    this.radius = 10,
    this.progress = 0.0,
    this.duration = const Duration(milliseconds: 800),
    double? childRadius,
  }) : childRadius = childRadius ?? radius / 3;
  final bool stop;
  final Duration duration;

  final List<Color> colors;
  final double radius;
  final double childRadius;
  final double progress;

  /// 当[stop]切换为 true 时, 是否停止动画
  final bool stopAnyTime;
  @override
  State<CircleIndicator> createState() => _CircleIndicatorState();
}

class _CircleIndicatorState extends State<CircleIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController animationController;
  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    updateState();
  }

  @override
  void didUpdateWidget(covariant CircleIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateState();
  }

  void updateState() {
    if (!widget.stop) {
      animationController.repeat();
    } else if (widget.stopAnyTime) {
      animationController.stop();
    }
    if (!animationController.isAnimating) {
      animationController.value = widget.progress.clamp(0.0, 1.0);
    }
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.radius * 2,
      width: widget.radius * 2,
      child: CustomPaint(
        painter: _CircleIndicatorPainter(
          value: animationController,
          radius: widget.radius,
          colors: widget.colors,
          childRadius: widget.childRadius,
        ),
      ),
    );
  }
}

class _CircleIndicatorPainter extends CustomPainter {
  _CircleIndicatorPainter({
    required this.value,
    required double radius,
    required this.colors,
    required double childRadius,
  }) : super(repaint: value) {
    rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        -childRadius,
        -radius + childRadius,
        childRadius,
        childRadius,
      ),
      Radius.circular(childRadius),
    );
  }
  final Animation<double> value;
  late RRect rrect;
  final List<Color> colors;
  static const _twoPi = math.pi * 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2.0, size.height / 2.0);
    final tickCount = colors.length;

    final paint = Paint();
    // final current = (tickCount * value.value).floor();
    final deg = _twoPi / tickCount;
    // 对齐
    canvas.rotate(_twoPi * value.value);
    canvas.rotate(deg);
    for (var i = 0; i < tickCount; i++) {
      final index = i;
      paint.color = colors[index];
      canvas.drawRRect(rrect, paint);
      canvas.rotate(deg);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CircleIndicatorPainter oldDelegate) {
    return value != oldDelegate.value ||
        rrect != oldDelegate.rrect ||
        colors.length != oldDelegate.colors.length ||
        colors.any((e) => !oldDelegate.colors.contains(e));
  }
}
