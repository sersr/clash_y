import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';

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

    if (img != null) {
      list.add(AImage(img!, fit: BoxFit.fitWidth));
    }
    if (title is String) {
      list.add(
        Padding(
          padding: EdgeInsets.only(top: 6.h),
          child: Text(
            title!,
            style: TextStyle(
              color: Colors.black,
              fontSize: 21.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (message is String) {
      list.add(
        Padding(
          padding: EdgeInsets.only(top: 14.h, left: 30.w, right: 30.w),
          child: Text(
            message!,
            style: TextStyle(
              color: Colors.black,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (center != null) {
      list.add(center!);
    }

    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: Column(mainAxisSize: MainAxisSize.min, children: list),
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
                  fontWeight: FontWeight.w500,
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
                  fontWeight: FontWeight.w500,
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
          ],
        ),
      ),
    );
  }
}
