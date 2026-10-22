import 'dart:io';

import 'package:common/common.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class SettingItem extends StatelessWidget {
  const SettingItem({
    super.key,
    this.icon,
    required this.label,
    this.enabled,
    this.info,
    this.onTap,
    this.value,
  });
  final String label;
  final bool? enabled;
  final String? info;
  final VoidCallback? onTap;
  final String? value;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    late Widget end = const ArrowIcon();

    if (enabled case var enabled?) {
      end = CupertinoSwitch(
        value: enabled,
        inactiveTrackColor: const Color(0xFFC9CDD4),
        activeTrackColor: const Color(0xFF2854F5),
        onChanged: (_) => onTap?.call(),
      );
    } else if (value case var value?) {
      end = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(color: const Color(0xFF999999), fontSize: 12.sp),
          ),
          if (onTap != null) ...[2.horizontalSpace, end],
        ],
      );
    }

    Widget content = Text(
      label,
      style: TextStyle(
        color: const Color(0xFF333333),
        fontSize: 13.sp,
        fontWeight: Platform.isIOS ? FontWeight.w500 : FontWeight.w600,
        height: 1.0,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (info case var info?) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          4.verticalSpace,
          Text(
            info,
            style: TextStyle(
              fontSize: 12.sp,
              color: const Color(0xFF999999),
              fontWeight: FontWeight.w400,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    content = Container(
      constraints: BoxConstraints(minHeight: 52.h),
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        children: [
          if (icon case var icon?)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: AImage(icon, width: 20.h, fit: BoxFit.fitHeight),
            ),
          Expanded(child: content),
          end,
        ],
      ),
    );

    if (enabled == null && onTap != null) {
      content = InkButton.text(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.zero,
        overlayColor: const Color.fromARGB(66, 180, 180, 180),
        onPressed: onTap,
        child: content,
      );
    }
    return content;
  }
}

class ArrowIcon extends StatelessWidget {
  const ArrowIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.arrow_forward_ios_sharp,
      size: 16.sp,
      color: const Color(0xFF878787),
    );
  }
}

class SettingDecoration extends StatelessWidget {
  const SettingDecoration({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // margin: EdgeInsets.symmetric(horizontal: 14.w),
      color: Colors.white,
      // padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
      // decoration: BoxDecoration(
      //   color: Colors.white,
      //   borderRadius: BorderRadius.circular(6.r),
      // ),
      // clipBehavior: Clip.hardEdge,
      child: child,
    );
  }
}

class SettingDiv extends StatelessWidget {
  const SettingDiv({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5.h,
      thickness: 0.5.h,
      indent: 20.w,
      endIndent: 20.w,
      color: const Color(0xFFEDEDED),
    );
  }
}
