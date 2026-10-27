import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';

/// 返回按钮
class BaseBackButton extends StatelessWidget {
  const BaseBackButton({super.key, this.onBack, this.iconData})
      : color = Colors.white,
        overlayColor = const Color.fromARGB(67, 236, 236, 236);
  const BaseBackButton.black({super.key, this.onBack, this.iconData})
      : color = Colors.black,
        overlayColor = const Color.fromARGB(161, 203, 203, 203);

  final VoidCallback? onBack;
  final Color color;
  final Color overlayColor;
  final IconData? iconData;

  @override
  Widget build(BuildContext context) {
    final size = 42.r;
    return SizedBox(
      height: size,
      width: size,
      child: OverflowBox(
        maxHeight: size,
        maxWidth: size,
        minHeight: size,
        minWidth: size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBack ?? Nav.back,
          child: Container(
            padding: EdgeInsets.fromLTRB(12.w, 0, 8.w, 0),
            child: Icon(iconData ?? Icons.arrow_back_ios_rounded,color: color, size: 20.r),
          ),
        ),
        // InkButton(
        //   onPressed: onBack ?? Get.back,
        //   backgroundColor: Colors.transparent,
        //   overlayColor: overlayColor,
        //   isStadium: true,
        //   child: Icon(iconData ?? Icons.arrow_back_ios_rounded,
        //       color: color, size: 20.r),
        // ),
      ),
    );
  }
}

/// 按钮范围比较小

class BaseBackClosedButton extends StatelessWidget {
  const BaseBackClosedButton({super.key})
      : color = Colors.white,
        overlayColor = const Color.fromARGB(67, 236, 236, 236);
  const BaseBackClosedButton.black({super.key})
      : color = Colors.black,
        overlayColor = const Color.fromARGB(161, 203, 203, 203);

  final Color color;
  final Color overlayColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: 8.w),
      height: 40.h,
      width: 40.h,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: InkButton(
          onPressed: () {
            Nav.back();
          },
          backgroundColor: Colors.transparent,
          overlayColor: overlayColor,
          isStadium: true,
          child: Icon(Icons.arrow_back_ios, color: color, size: 20.r),
        ),
      ),
    );
  }
}

class BgBackButton extends StatelessWidget {
  const BgBackButton({super.key, this.left})
      : color = Colors.black,
        overlayColor = const Color.fromARGB(161, 203, 203, 203);

  final Color color;
  final Color overlayColor;
  final double? left;

  @override
  Widget build(BuildContext context) {
    final canBack = Navigator.canPop(context);
    if (!canBack) return const SizedBox();

    return Container(
      margin: EdgeInsets.only(left: left ?? 14.w),
      child: GestureDetector(
        onTap: () {
          Nav.back();
        },
        child: Icon(Icons.arrow_back_ios_new, size: 30.r, color: color),
      ),
    );
  }
}
