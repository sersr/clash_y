import 'package:flutter/material.dart';

import '../ext/screen_ext.dart';
import 'buttons.dart';
import 'image.dart';
import 'loading_dialog.dart';

/// 弹窗动画
///
/// NOTE: [PageRouteBuilder], 如果不是 [PageRoute]，[Get].toNamed 会出现问题
Future<T?> showCenterDialog<T>(
  BuildContext context,
  Widget child, {
  Alignment alignment = Alignment.center,
  bool useSafeArea = true,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  if (dialogScopeBack case var back?) {
    back();
  }
  return Navigator.push(
    context,
    PageRouteBuilder(
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? Colors.black54,
      opaque: false,
      maintainState: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        Widget body = child;
        if (useSafeArea) {
          body = SafeArea(child: child);
        }
        return _AnimatedDialog(
            animation: animation, alignment: alignment, child: body);
      },
    ),
  );
}

class _AnimatedDialog extends StatefulWidget {
  const _AnimatedDialog(
      {required this.animation, required this.child, required this.alignment});
  final Animation<double> animation;
  final Widget child;
  final Alignment alignment;
  @override
  State<_AnimatedDialog> createState() => _AnimatedDialogState();
}

class _AnimatedDialogState extends State<_AnimatedDialog> {
  late CurvedAnimation curvedAnimation;

  late Animation<double> scale;

  @override
  void initState() {
    super.initState();
    update();
  }

  void update() {
    curvedAnimation =
        CurvedAnimation(parent: widget.animation, curve: Curves.easeInOut);
    scale = Tween(begin: 0.8, end: 1.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(widget.animation);
  }

  @override
  void didUpdateWidget(covariant _AnimatedDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      curvedAnimation.dispose();
      update();
    }
  }

  @override
  void dispose() {
    curvedAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = ScaleTransition(
        scale: scale,
        child: FadeTransition(opacity: curvedAnimation, child: widget.child));
    return Align(alignment: widget.alignment, child: body);
  }
}

class BaseDialog extends StatelessWidget {
  const BaseDialog({
    super.key,
    this.img,
    this.title,
    this.message,
    this.leftLabel,
    this.rightLabel,
    this.leftVoidCallback,
    this.rightVoidCallback,
    this.center,
    this.showCloseBtn = true,
  });

  final String? img;
  final String? title;
  final String? message;
  final String? leftLabel;
  final String? rightLabel;
  final VoidCallback? leftVoidCallback;
  final VoidCallback? rightVoidCallback;
  final Widget? center;
  final bool showCloseBtn;

  @override
  Widget build(BuildContext context) {
    final list = <Widget>[];

    if (img case String img) {
      list.add(getImage(img, fit: BoxFit.fitWidth));
    }
    if (title case String title) {
      list.add(
        Padding(
          padding: EdgeInsets.only(top: 6.h),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.black,
              fontSize: 21.sp,
            ),
          ),
        ),
      );
    }

    if (message case String message) {
      list.add(
        Padding(
          padding: EdgeInsets.only(top: 14.h, left: 30.w, right: 30.w),
          child: Text(
            message,
            style: TextStyle(
              color: Colors.black,
              fontSize: 14.sp,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (center case Widget child) {
      list.add(child);
    }

    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: list,
      ),
    );

    final buttons = Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        children: [
          InkButton(
            onPressed: () {
              rightVoidCallback?.call();
            },
            padding: EdgeInsets.symmetric(vertical: 14.h),
            borderRadius: BorderRadius.circular(8.r),
            backgroundColor: const Color(0xFF3573FC),
            overlayColor: const Color.fromARGB(44, 255, 255, 255),
            child: Center(
              child: Text(
                rightLabel ?? '',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.sp,
                ),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          InkButton(
            onPressed: () {
              leftVoidCallback?.call();
            },
            padding: EdgeInsets.symmetric(vertical: 14.h),
            borderRadius: BorderRadius.circular(8.r),
            backgroundColor: Colors.transparent,
            overlayColor: const Color.fromARGB(44, 211, 211, 211),
            side: BorderSide(color: const Color(0xFFDDDDDD), width: 1.r),
            child: Center(
              child: Text(
                leftLabel ?? '',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16.sp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w),
      child: Material(
        borderRadius: BorderRadius.circular(20.r),
        clipBehavior: Clip.hardEdge,
        color: Colors.white,
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 10.h),
                content,
                SizedBox(height: 24.h),
                buttons,
                SizedBox(height: 24.h),
              ],
            ),
            // Positioned(
            //   right: 20.w,
            //   top: 20.w,
            //   child: SizedBox(
            //     width: 24.w,
            //     height: 24.w,
            //     child: OverflowBox(
            //       maxHeight: 32.w,
            //       maxWidth: 32.w,
            //       minHeight: 32.w,
            //       minWidth: 32.w,
            //       child: InkButton.text(
            //         onPressed: () {
            //           Get.back();
            //         },
            //         padding: EdgeInsets.zero,
            //         child: getImage(
            //           'btn_close',
            //           width: 24.w,
            //           fit: BoxFit.fitWidth,
            //         ),
            //       ),
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
