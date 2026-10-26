import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../ext/screen_ext.dart';
import '../navigator_observer.dart';
import 'loading_dialog.dart';

RunningDelegate buildDefaultRefresh(
  FutureOr<void> Function()? onRunning, {
  double? maxExtent,
  Alignment alignment = const Alignment(0, 0),
  Color? backgroundColor,
  Color? color,
  bool white = false,
}) {
  return RunningDelegate(
    maxExtent: maxExtent ?? 80.h,
    onRunning: onRunning,
    triggerMode: RefreshIndicatorTriggerMode.anywhere,
    builder: (context, offset, maxExtent, mode, running, success) {
      if (mode == RefreshLoadingMode.idle) return Container(color: color);
      // String text = '';
      // if (success) {
      //   text = 'refresh_success'.tr;
      // } else if (running) {
      //   text = 'refreshing'.tr;
      // } else {
      //   switch (mode) {
      //     case RefreshLoadingMode.running:
      //       text = 'refreshing'.tr;
      //       break;
      //     case RefreshLoadingMode.done:
      //       text = 'refresh_done'.tr;
      //       break;
      //     case RefreshLoadingMode.ignore:
      //       text = 'refresh_cancel'.tr;
      //       break;
      //     case RefreshLoadingMode.dragEnd:
      //       text = 'refresh_release'.tr;
      //       break;
      //     case RefreshLoadingMode.dragStart:
      //     case RefreshLoadingMode.idle:
      //       text = 'refresh_drag'.tr;
      //       break;
      //     case RefreshLoadingMode.failed:
      //       text = 'refresh_failed'.tr;
      //       break;
      //     default:
      //   }
      // }

      // final child = Text(text, style: TextStyle(color: color));
      final stop =
          !running &&
          !success &&
          (mode.index < RefreshLoadingMode.running.index ||
              mode == RefreshLoadingMode.ignore);
      Widget loading;
      if (white) {
        loading = LoadingWidget.white(
          stop: stop,
          progress: (maxExtent - offset) / 3 / maxExtent,
        );
      } else {
        loading = LoadingWidget(
          stop: stop,
          progress: (maxExtent - offset) / 3 / maxExtent,
        );
      }

      return RepaintBoundary(
        child: Stack(
          children: [
            if (backgroundColor != null)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxHeight = constraints.maxHeight + 2.h;
                    return OverflowBox(
                      minHeight: maxHeight,
                      maxHeight: maxHeight,
                      child: ColoredBox(color: backgroundColor),
                    );
                  },
                ),
              ),
            Align(
              alignment: alignment,
              child: ClipRect(
                child: OverflowBar(
                  overflowAlignment: OverflowBarAlignment.center,
                  children: [
                    SizedBox(width: Nav.screenWidth, child: loading),
                    // child,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

RunningDelegate buildDefaultLoading(
  void Function()? onDragStart, {
  Future<void> Function()? onRunning,
  bool white = false,
  Color? color,
}) {
  return RunningDelegate(
    maxExtent: 60.h,
    onDragStart: onDragStart,
    onRunning: onRunning,
    triggerMode: RefreshIndicatorTriggerMode.onEdge,
    builder: (context, offset, maxExtent, mode, running, success) {
      if (mode == RefreshLoadingMode.idle) return const SizedBox();
      // ignore: unused_local_variable
      // late String text;
      // if (success) {
      //   text = 'load_done'.tr;
      // } else if (running) {
      //   text = 'loading'.tr;
      // } else {
      //   switch (mode) {
      //     case RefreshLoadingMode.done:
      //       text = 'load_done'.tr;
      //       break;
      //     case RefreshLoadingMode.running:
      //     // child = Text('loading'.tr);
      //     // break;
      //     case RefreshLoadingMode.ignore:
      //     // child = Text('load_cancel'.tr);
      //     // break;
      //     case RefreshLoadingMode.dragEnd:
      //     // child = Text('load_release'.tr);
      //     // break;
      //     case RefreshLoadingMode.dragStart:
      //     case RefreshLoadingMode.idle:
      //       text = 'loading'.tr;
      //       break;
      //     case RefreshLoadingMode.failed:
      //       text = 'load_failed'.tr;
      //       break;
      //     default:
      //   }
      // }

      // text = '';
      return RepaintBoundary(
        child: Align(
          alignment: const Alignment(0, -0.5),
          child: ClipRect(
            child: Center(
              child: OverflowBar(
                overflowAlignment: OverflowBarAlignment.center,
                children: [
                  SizedBox(
                    width: Nav.screenWidth,
                    child: white
                        ? const LoadingWidget.white(stop: false)
                        : const LoadingWidget(
                            stop: false,
                            // progress: (maxExtent - 36 - offset) / (maxExtent * 2),
                          ),
                  ),
                  // Text(
                  //   text,
                  //   style: TextStyle(color: color),
                  // ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class Refresh extends StatefulWidget {
  const Refresh({
    super.key,
    this.refresh,
    this.loading,
    required this.slivers,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.scrollController,
    this.primary,
    this.center,
    this.anchor = 0.0,
    this.cacheExtent,
    this.semanticChildCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.emptyWidget,
    this.preLoad,
    this.handles,
    this.isEmpty = false,
  });

  final List<Widget> slivers;
  final RunningDelegate? refresh;
  final RunningDelegate? loading;
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? scrollController;
  final bool? primary;
  final Key? center;
  final double anchor;
  final ScrollCacheExtent? cacheExtent;
  final int? semanticChildCount;
  final DragStartBehavior dragStartBehavior;
  final Widget? emptyWidget;
  final Future<void> Function()? preLoad;
  final List<SliverOverlapAbsorberHandle>? handles;
  final bool isEmpty;

  @override
  State<Refresh> createState() => _RefreshState();
}

class _RefreshState extends State<Refresh> {
  late _RefreshBase refresh;
  late _RefreshBase loading;
  final _spaceKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    refresh = _Refresh().._setDelegate(widget.refresh);
    loading = _Loading().._setDelegate(widget.loading);
  }

  @override
  void didUpdateWidget(covariant Refresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    refresh._setDelegate(widget.refresh);
    loading._setDelegate(widget.loading);
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
      final render = _spaceKey.currentContext?.findRenderObject();
      if (render is RenderSliverFillRemaining) {
        if (render.geometry?.hasVisualOverflow == true) {
          final position = Scrollable.maybeOf(_spaceKey.currentContext!)
              ?.position;
          position?.jumpTo(position.maxScrollExtent);
        }
      }
    });
  }

  Future<void>? _task;

  void _update(ScrollMetrics metrics) {
    if (widget.preLoad is Future<void> Function()) {
      if (metrics.maxScrollExtent <= metrics.pixels + 80) {
        if (_task == null) {
          _task = widget.preLoad!();
          _task!.whenComplete(() {
            Future.delayed(
              const Duration(milliseconds: 600),
              () => _task = null,
            );
          });
        }
      }
    }
  }

  @override
  void dispose() {
    refresh._setDelegate(null);
    loading._setDelegate(null);
    // controller?.removeListener(_listen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: buildView);
  }

  Widget buildView(BuildContext context, BoxConstraints constraints) {
    final slivers = <Widget>[];

    int start = 0;
    if (widget.handles is List<SliverOverlapAbsorberHandle>) {
      for (var handle in widget.handles!) {
        slivers.add(SliverOverlapInjector(handle: handle));
      }
      start = widget.handles!.length;
    }

    slivers.addAll(widget.slivers);

    if (slivers.isEmpty || widget.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: ConstrainedBox(
            constraints: constraints,
            child: widget.emptyWidget,
          ),
        ),
      );
    }
    if (refresh.runningDelegate != null) {
      slivers.insert(
        start,
        SliverToBoxAdapter(
          child: RepaintBoundary(
            child: _RefreshLoadingWidget(refreshBase: refresh),
          ),
        ),
      );
    }
    if (loading.runningDelegate != null) {
      /// 自动填充空白区域
      slivers.add(
        SliverFillRemaining(
          key: _spaceKey,
          hasScrollBody: false,
          child: const SizedBox(),
        ),
      );
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: RepaintBoundary(
            child: _RefreshLoadingWidget(refreshBase: loading),
          ),
        ),
      );
    }

    final behavior = ScrollConfiguration.of(context);
    final physics = ClampingScrollPhysics(
      parent: behavior
          .getScrollPhysics(context)
          .applyTo(const AlwaysScrollableScrollPhysics()),
    );
    var child = NotificationListener(
      onNotification: _onNotification,
      child: CustomScrollView(
        slivers: slivers,
        dragStartBehavior: widget.dragStartBehavior,
        scrollDirection: widget.scrollDirection,
        reverse: widget.reverse,
        controller: widget.scrollController,
        primary: widget.primary,
        center: widget.center,
        anchor: widget.anchor,
        physics: physics,
        scrollCacheExtent: widget.cacheExtent,
        semanticChildCount: widget.semanticChildCount,
        // emptyWidget: widget.emptyWidget,
      ),
    );
    return ScrollConfiguration(
      behavior: behavior.copyWith(physics: physics),
      child: child,
    );
  }

  bool _onNotification(Notification n) {
    if (n is ScrollNotification) {
      _update(n.metrics);
    }
    if (n is OverscrollIndicatorNotification) {
      if (refresh.value > 0 || loading.value > 0) {
        n.disallowIndicator();
      }
    }
    if (refresh._value == 0 && loading.onNotifition(n)) {
      if (n is OverscrollIndicatorNotification) {
        if (n.leading) n.disallowIndicator();
      }
      return false;
    }
    if (loading._value == 0) refresh.onNotifition(n);
    return false;
  }
}

/// 所有状态都是临时状态
/// 永久性的状态 [running], [success]会额外给出，如在回调的参数中
enum RefreshLoadingMode {
  // --- 空闲状态
  idle,
  // --- 拖动过程
  dragStart,
  draging,
  dragEnd,
  // --- 释放刷新
  running,
  // --- 完成刷新
  done,
  // --- 拖动取消
  ignore,
  // --- 动画
  animatedIgnore,
  animatedDone,
  // --- 失败
  failed, // 如果用户还在接管手势，则可能还会调用onRunning;
}

extension RefreshLoadingModeActive on RefreshLoadingMode {
  bool get active {
    return this == RefreshLoadingMode.running ||
        this == RefreshLoadingMode.done ||
        this == RefreshLoadingMode.animatedDone;
  }

  RefreshLoadingMode get outerMode {
    RefreshLoadingMode mode = this;
    switch (this) {
      case RefreshLoadingMode.animatedDone:
        mode = RefreshLoadingMode.done;
        break;
      case RefreshLoadingMode.animatedIgnore:
        mode = RefreshLoadingMode.ignore;
        break;
      case RefreshLoadingMode.draging:
        mode = RefreshLoadingMode.dragStart;
        break;
      case RefreshLoadingMode.idle:
      case RefreshLoadingMode.dragStart:
      case RefreshLoadingMode.dragEnd:
      case RefreshLoadingMode.running:
      case RefreshLoadingMode.done:
      case RefreshLoadingMode.ignore:
      case RefreshLoadingMode.failed:
        mode = this;
        break;
    }
    return mode;
  }
}

typedef OnRunning = FutureOr<void> Function();

typedef RefreshLoadingBuilder = Widget Function(
  BuildContext context,
  double offset,
  double maxExtent,
  RefreshLoadingMode mode,
  bool running,
  bool success,
);

class RunningDelegate {
  RunningDelegate({
    this.onDragStart,
    this.onDragEnd,
    this.onDragIgnore,
    this.onDone,
    this.onRunning,
    this.waitingOnDone = const Duration(milliseconds: 800),
    this.maxDurationOnRunning = const Duration(milliseconds: 1500),
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
    required this.maxExtent,
    required this.builder,
  }) : assert(maxExtent > 0.0);
  final VoidCallback? onDragStart;

  /// 当拖动距离达到[maxExtent]调用
  final VoidCallback? onDragEnd;
  final VoidCallback? onDragIgnore;
  final VoidCallback? onDone;
  final OnRunning? onRunning;
  final RefreshLoadingBuilder builder;
  final double maxExtent;
  final RefreshIndicatorTriggerMode triggerMode;
  final Duration waitingOnDone;
  final Duration maxDurationOnRunning;

  /// 生命周期自动设置
  _RefreshBase? _refresh;
  BuildContext? _context;

  void show() {
    if (_context != null && _refresh != null) {
      final position = Scrollable.of(_context!).position;
      position.jumpTo(position.minScrollExtent);
      _refresh!
        .._setValue(maxExtent)
        .._setMode(RefreshLoadingMode.running);
    }
  }

  void hide() {
    _refresh?._setValue(0.0);
  }

  void refreshLoadingFailed() {
    _refresh?._setMode(RefreshLoadingMode.failed);
  }
}

class _Refresh extends _RefreshBase {
  @override
  bool get isLoading => false;

  @override
  bool getCanLoading(ScrollStartNotification n) {
    return n.metrics.extentBefore == 0;
  }

  @override
  void onOverScroll(OverscrollNotification n) {
    final mes = n.metrics;

    final isAtEdge = mes.extentBefore == 0.0;
    final overscroll = n.overscroll;
    //logDev.w('...... $overscroll | $isAtEdge | $value');
    if (overscroll < 0 || (isAtEdge && value > 0.0)) {
      final newValue = (value - overscroll).clamp(0.0, maxExtent);

      _setValue(newValue);
    }
  }

  @override
  void onScrollUpdate(ScrollUpdateNotification n) {
    final scrollDelta = n.scrollDelta;
    if (scrollDelta != null) {
      final mes = n.metrics;
      if (n.dragDetails == null) {
        // return;
      }
      if ((value > 0.0) && (scrollDelta > 0 || mes.extentBefore == 0.0)) {
        final newValue = (value - scrollDelta).clamp(0.0, maxExtent);
        Scrollable.of(n.context!).position.correctBy(-scrollDelta);
        _setValue(newValue);
      }
    }
  }

  @override
  void onOverScrollIndicator(OverscrollIndicatorNotification n) {
    if (n.leading) {
      n.disallowIndicator();
    }
  }
}

class _Loading extends _RefreshBase {
  @override
  bool get isLoading => true;

  @override
  bool getCanLoading(ScrollStartNotification n) {
    return n.metrics.extentAfter == 0 && n.dragDetails != null;
  }

  @override
  void onOverScroll(OverscrollNotification n) {
    final mes = n.metrics;
    // if (n.dragDetails == null) return;
    final isAtEdge = mes.extentAfter == 0.0;
    final overscroll = n.overscroll;
    //logDev.w('......onOverScroll $overscroll | $isAtEdge | $value');
    if (overscroll > 0 || (isAtEdge && value > 0.0)) {
      final oldValue = value;
      final newValue = (value + overscroll).clamp(0.0, maxExtent);
      _setValue(newValue);
      // assert(() {
      //   // 在帧后回调中检查
      //   SchedulerBinding.instance?.addPostFrameCallback((timeStamp) {
      //     final position = Scrollable.of(n.context!)?.position;
      //    logDev.w('.... ${position?.pixels}  ${position?.maxScrollExtent}');
      //   });
      //   return true;
      // }());
      final delta = value - oldValue;
      // loading widget 的高度增加，pixels 并没有增加, 调用下面的方法校准
      Scrollable.of(n.context!).position.correctBy(delta);
    }
  }

  @override
  void onScrollUpdate(ScrollUpdateNotification n) {
    final scrollDelta = n.scrollDelta;
    if (scrollDelta != null) {
      final mes = n.metrics;
      if (n.dragDetails == null) {
        // return;
      }
      if ((value > 0.0) && (scrollDelta < 0 || mes.extentAfter == 0.0)) {
        final newValue = (value + scrollDelta).clamp(0.0, maxExtent);
        _setValue(newValue);
      }
    }
  }

  @override
  void onOverScrollIndicator(OverscrollIndicatorNotification n) {
    if (!n.leading) {
      n.disallowIndicator();
    }
  }
}

abstract class _RefreshBase extends ChangeNotifier {
  _RefreshBase();
  RunningDelegate? runningDelegate;
  void _setDelegate(RunningDelegate? delegate) {
    runningDelegate?._refresh = null;
    runningDelegate = delegate;
    runningDelegate?._refresh = this;
  }

  bool get isLoading;

  double get maxExtent => runningDelegate?.maxExtent ?? 0.0;

  double get fac => maxExtent == 0.0 ? 0.0 : value / maxExtent;
  double _value = 0.0;

  double get value => _value;
  bool canLoading = false;

  bool getCanLoading(ScrollStartNotification n);

  void reset(ScrollStartNotification n) {
    canLoading =
        getCanLoading(n) ||
        runningDelegate?.triggerMode == RefreshIndicatorTriggerMode.anywhere;
    if (!canLoading) return;
    _setMode(RefreshLoadingMode.dragStart);
  }

  void _setValue(double v, [bool animated = false]) {
    final clampedV = v.clamp(0.0, maxExtent);
    if (clampedV == _value) return;

    _value = clampedV;
    if (_value == 0.0) {
      _setMode(RefreshLoadingMode.idle);
    } else if (!animated) {
      if ((_value - maxExtent).abs() < 0.1) {
        if (mode == RefreshLoadingMode.dragStart) {
          _setMode(RefreshLoadingMode.draging);
        }
        _setMode(RefreshLoadingMode.dragEnd);
      } else {
        _setMode(RefreshLoadingMode.draging);
      }
    }

    notifyListeners();
  }

  final ValueNotifier<RefreshLoadingMode> _mode = ValueNotifier(
    RefreshLoadingMode.idle,
  );
  RefreshLoadingMode get mode => _mode.value;

  void addModeListener(VoidCallback listener) {
    _mode.addListener(listener);
  }

  void removeModeListener(VoidCallback listener) {
    _mode.removeListener(listener);
  }

  void _setMode(RefreshLoadingMode m) {
    _mode.value = m;
  }

  bool get _active => runningDelegate != null;

  bool onNotifition(Notification notification) {
    if (!_active) return false;
    var short = false;
    if (notification is ViewportNotificationMixin) {
      if (notification.depth > 0) return false;
    }
    if (notification is ScrollMetricsNotification) {
      short =
          notification.metrics.maxScrollExtent <=
          notification.metrics.viewportDimension;
    }

    if (notification is OverscrollIndicatorNotification) {
      onOverScrollIndicator(notification);
    } else if (notification is ScrollStartNotification) {
      reset(notification);
    } else if (notification is ScrollUpdateNotification) {
      goScrollUpdate(notification);
    } else if (notification is OverscrollNotification) {
      goOverScroll(notification);
    } else if (notification is ScrollEndNotification) {
      goScrollEnd(notification);
    }
    return canLoading && value > 0 && short;
  }

  void goScrollUpdate(ScrollUpdateNotification n) {
    if (!canLoading) return;
    onScrollUpdate(n);
  }

  void onScrollUpdate(ScrollUpdateNotification n);

  void goOverScroll(OverscrollNotification n) {
    if (!canLoading) return;
    onOverScroll(n);
  }

  void onOverScroll(OverscrollNotification n);

  void onOverScrollIndicator(OverscrollIndicatorNotification n);
  void goScrollEnd(ScrollEndNotification n) {
    if (!canLoading) return;

    if ((value - maxExtent).abs() < 0.5) {
      _setValue(maxExtent);
      _setMode(RefreshLoadingMode.running);
    } else if (mode != RefreshLoadingMode.animatedIgnore) {
      if (value != 0) {
        _setMode(RefreshLoadingMode.ignore);
      }
    }
  }
}

class _RefreshLoadingWidget extends StatefulWidget {
  const _RefreshLoadingWidget({required this.refreshBase});

  final _RefreshBase refreshBase;
  @override
  _RefreshLoadingWidgetState createState() => _RefreshLoadingWidgetState();
}

class _RefreshLoadingWidgetState extends State<_RefreshLoadingWidget>
    with TickerProviderStateMixin {
  late _RefreshBase refreshBase;
  late AnimationController animationController;
  @override
  void initState() {
    super.initState();
    refreshBase = widget.refreshBase;
    animationController = AnimationController.unbounded(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    animationController.addListener(_tick);
    refreshBase.addModeListener(_updateMode);
    refreshBase.runningDelegate!._context = context;
  }

  void _tick() {
    final controller = refreshBase;
    final value = animationController.value;
    controller._setValue(value, true);
  }

  Timer? waitAnimated;
  Future<void>? _runningWork;

  /// onRunning 如果成功，不再调用
  bool? _success;
  bool get success => _success ?? false;
  bool _isRunOnce = false;
  RefreshLoadingMode _lastMode = RefreshLoadingMode.idle;
  void _updateMode() {
    final controller = refreshBase;
    waitAnimated?.cancel();

    void startAnimated() {
      animationController.value = controller.value;
      animationController.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.ease,
      );
    }

    final running = controller.runningDelegate;
    final mode = controller.mode;

    if (running == null) return;

    switch (mode) {
      case RefreshLoadingMode.dragStart:
        _isRunOnce = false;
        if (_lastMode == RefreshLoadingMode.idle) {
          _lastMode = mode;
          return;
        }
        break;
      case RefreshLoadingMode.draging:
        if (_isRunOnce) {
          break;
        }
        _isRunOnce = true;
        running.onDragStart?.call();
        break;
      case RefreshLoadingMode.dragEnd:
        _isRunOnce = false;
        running.onDragEnd?.call();
        break;
      // 刷新事件
      case RefreshLoadingMode.running:
        final onRunning = running.onRunning;
        if (success || onRunning == null) {
          controller._setMode(RefreshLoadingMode.done);
          return;
        }
        _success = false;
        Future<void>? local;

        local = _runningWork = _runningWork.waitThen(() async {
          if (!mounted) return;
          bool refreshCondition() {
            return controller == refreshBase &&
                refreshBase.runningDelegate == controller.runningDelegate &&
                refreshBase.runningDelegate?.onRunning == onRunning;
          }

          var failed = false;
          if (refreshCondition()) {
            try {
              final stop = Stopwatch()..start();
              await onRunning();
              final useTime = stop.elapsedMilliseconds;
              final max = running.maxDurationOnRunning.inMilliseconds;
              if (useTime < max) {
                await Future.delayed(Duration(milliseconds: max - useTime));
              }
            } catch (e) {
              failed = true;
            }
          }
          if (_success != null) {
            _success = _success! | !failed;
          }
          if (refreshCondition() &&
              controller.mode == RefreshLoadingMode.running) {
            if (success) {
              controller._setMode(RefreshLoadingMode.done);
            } else {
              controller._setMode(RefreshLoadingMode.failed);
            }
          } else {
            controller._setMode(RefreshLoadingMode.done);
          }
          if (local == _runningWork) {
            _runningWork = null;
          }
        });

        break;

      // 动画事件
      case RefreshLoadingMode.ignore:
        running.onDragIgnore?.call();

        startAnimated();
        controller._setMode(RefreshLoadingMode.animatedIgnore);
        return;
      case RefreshLoadingMode.done:
      case RefreshLoadingMode.failed:
        running.onDone?.call();
        waitAnimated?.cancel();
        waitAnimated = Timer(running.waitingOnDone, () {
          if (mounted) {
            startAnimated();
            refreshBase._setMode(RefreshLoadingMode.animatedDone);
          }
        });
        break;

      case RefreshLoadingMode.idle:
        _success = null;
        _runningWork = null;
        break;
      default:
    }
    switch (mode) {
      case RefreshLoadingMode.idle:
      // 用户行为
      case RefreshLoadingMode.dragStart:
      case RefreshLoadingMode.draging:
      case RefreshLoadingMode.dragEnd:
        if (animationController.isAnimating) {
          animationController.stop(canceled: true);
        }
        break;
      default:
    }
    if (_secheduled) return;
    final scheduler = SchedulerBinding.instance;
    // assert(() {
    //   // ignore: avoid_print
    //  logDev.w(scheduler.schedulerPhase.name.padRight(30, '.').padLeft(60, '.'));
    //   return true;
    // }());
    switch (scheduler.schedulerPhase) {
      case SchedulerPhase.persistentCallbacks:
        // 添加到帧后回调
        scheduler.addPostFrameCallback((timeStamp) {
          _secheduled = false;
          _update();
        });
        _secheduled = true;
        break;
      default:
        _update();
    }

    _lastMode = mode;
  }

  void _update() {
    if (mounted) setState(() {});
  }

  bool _secheduled = false;

  @override
  void didUpdateWidget(covariant _RefreshLoadingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (refreshBase != widget.refreshBase) {
      refreshBase.removeListener(_updateMode);
      refreshBase = widget.refreshBase;
      refreshBase.addListener(_updateMode);
    }
    refreshBase.runningDelegate!._context = context;
  }

  @override
  void dispose() {
    animationController.dispose();
    refreshBase.removeModeListener(_updateMode);
    refreshBase.runningDelegate?._context = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.of(context).position;
    return AnimatedBuilder(
      animation: refreshBase,
      builder: (context, _) {
        assert(refreshBase.runningDelegate != null);
        final builder = refreshBase.runningDelegate!.builder;
        final isVertical = position.axis == Axis.vertical;

        return SizedBox(
          height: isVertical ? refreshBase.value : 0.0,
          width: isVertical ? 0.0 : refreshBase.value,
          child: builder(
            context,
            refreshBase.maxExtent - refreshBase._value,
            refreshBase.maxExtent,
            refreshBase.mode.outerMode,
            _runningWork != null,
            success,
          ),
        );
      },
    );
  }
}

extension on Future? {
  Future<T> waitThen<T>(Future<T> Function() action) {
    final that = this;
    if (that is Future) {
      return that.then((_) => action(), onError: (_) => action());
    }
    return action();
  }
}

// /// 滚动位移约束在[minScrollExtent]-[maxScrollExtent]之间
// ///
// /// 不会出现 outOfRange 的情况
// class _ClampBouncingScrollPhysics extends ScrollPhysics {
//   const _ClampBouncingScrollPhysics(this.refresh, this.loading,
//       {ScrollPhysics? parent})
//       : super(parent: parent);
//   final _RefreshBase refresh;
//   final _RefreshBase loading;
//   @override
//   _ClampBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
//     return _ClampBouncingScrollPhysics(refresh, loading,
//         parent: buildParent(ancestor));
//   }

//   @override
//   double applyBoundaryConditions(ScrollMetrics position, double value) {
//     if (value < position.pixels &&
//         position.pixels <= position.minScrollExtent) {
//       return value - position.pixels;
//     }
//     if (position.maxScrollExtent <= position.pixels &&
//         position.pixels < value) {
//       return value - position.pixels;
//     }
//     if (value < position.minScrollExtent &&
//         position.minScrollExtent < position.pixels) {
//       return value - position.minScrollExtent;
//     }
//     if (position.pixels < position.maxScrollExtent &&
//         position.maxScrollExtent < value) {
//       return value - position.maxScrollExtent;
//     }
//     return 0.0;
//   }

//   @override
//   Simulation? createBallisticSimulation(
//       ScrollMetrics position, double velocity) {
//     final simulation = super.createBallisticSimulation(position, velocity);
//     if (simulation == null) return null;

//     double max = position.maxScrollExtent;
//     double min = position.minScrollExtent;

//     // 处于边界时不需要有动画，否则会有停顿的情况发生
//     if (position.outOfRange || position.atEdge) {
//       if (velocity == 0) return null;
//     }
//     if (position.pixels <= position.minScrollExtent) {
//       if (refresh.value != 0) {
//         if (velocity < 0) {
//           return null;
//         }
//       }
//       min = position.minScrollExtent - refresh.value;
//       return null;
//     } else if (position.pixels >= position.maxScrollExtent) {
//       if (loading.value != 0) {
//         if (velocity > 0) {
//           return null;
//         }
//       }
//       max = position.maxScrollExtent + refresh.value;
//       return null;
//     }
//     logger.w('end... ${position.pixels} ${simulation}');
//     return ClampedSimulation(simulation, xMax: max, xMin: min);
//   }
// }

// class DefaultClampBouncingScrollPhysics extends ScrollPhysics {
//   const DefaultClampBouncingScrollPhysics({ScrollPhysics? parent})
//       : super(parent: parent);

//   @override
//   DefaultClampBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
//     return DefaultClampBouncingScrollPhysics(parent: buildParent(ancestor));
//   }

//   @override
//   double applyBoundaryConditions(ScrollMetrics position, double value) {
//     if (value < position.pixels &&
//         position.pixels <= position.minScrollExtent) {
//       return value - position.pixels;
//     }
//     if (position.maxScrollExtent <= position.pixels &&
//         position.pixels < value) {
//       return value - position.pixels;
//     }
//     if (value < position.minScrollExtent &&
//         position.minScrollExtent < position.pixels) {
//       return value - position.minScrollExtent;
//     }
//     if (position.pixels < position.maxScrollExtent &&
//         position.maxScrollExtent < value) {
//       return value - position.maxScrollExtent;
//     }
//     return 0.0;
//   }
// }
