import 'package:clashy/pages/home/controller/configs_controller.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:material_ui/material_ui.dart';

class ProfileItem extends StatelessWidget {
  const new({super.key, required this.item});
  final Profile item;

  @override
  Widget build(BuildContext context) {
    final name = item.showName;
    final clashConfigNotifier = context.getType<ConfigsController>();

    final updateTime = item.updateTime ?? DateTime.now();

    final popMenuButton = PopMenuButton(
      buildMenu: (context, state) {
        return _Menu(state: state, item: item);
      },
      builder: (context, state) {
        return InkButton(
          padding: .symmetric(horizontal: 10.w, vertical: 6.h),
          backgroundColor: Colors.transparent,
          overlayColor: const Color(0x449E9E9E),
          onPressed: () {
            state.show();
          },
          child: Icon(Icons.more_vert_rounded, size: 18),
        );
      },
    );

    return Padding(
      padding: .symmetric(horizontal: 12.w, vertical: 5.h),
      child: Cs(() {
        Widget body = Column(
          crossAxisAlignment: .start,
          children: [
            Text(
              item.used,
              style: .new(
                color: Color(0xFF333333),
                fontSize: 14.sp,
                fontWeight: .w500,
              ),
            ),
            6.verticalSpace,
            Text(
              updateTime.difference(DateTime.now()).ago,
              style: .new(
                color: Color(0xFF666666),
                fontSize: 13.sp,
                fontWeight: .w400,
              ),
            ),
          ],
        );

        final title = Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: .ellipsis,
                style: .new(
                  color: Color(0xFF333333),
                  fontSize: 16.sp,
                  fontWeight: .w500,
                ),
              ),
            ),
            if (item.expire case var e?)
              Text(
                'expired: ${formatDate(DateTime.fromMillisecondsSinceEpoch(e * 1000))}',
                style: .new(
                  color: Color.fromARGB(255, 80, 80, 80),
                  fontSize: 14.sp,
                  fontWeight: .w500,
                ),
              ),
            12.horizontalSpace,
          ],
        );

        return InkButton(
          backgroundColor: const Color.fromARGB(255, 242, 242, 242),
          overlayColor: const Color(0x2EA1A0A0),
          onPressed: () {
            clashConfigNotifier.reloadConfig(item);
          },
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          side: clashConfigNotifier.isCurrent(item)
              ? .new(width: 1.5.r, color: Colors.blue)
              : null,
          child: Column(
            children: [
              title,
              5.verticalSpace,
              Row(
                children: [
                  Expanded(child: body),
                  12.horizontalSpace,
                  popMenuButton,
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Menu extends StatefulWidget {
  const new({required this.state, required this.item});
  final PopMenuButtonState state;
  final Profile item;
  @override
  State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> {
  late final configs = getType<ConfigsController>();

  @override
  Widget build(BuildContext context) {
    Widget child = Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        custom(Icons.sync, "Update", () {
          configs.updateConfigData(widget.item);
        }),
        custom(Icons.copy, "Copy Url", () {
          copy(widget.item.url ?? '');
        }),
        deleteItem(),
      ],
    );

    child = Container(
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 245, 245, 245),
        borderRadius: .circular(12),
        boxShadow: [
          .new(color: Color(0x30666666), spreadRadius: 2, blurRadius: 5),
        ],
      ),
      clipBehavior: .hardEdge,
      constraints: .new(minWidth: 140.w),
      child: child,
    );

    return IntrinsicWidth(child: child);
  }

  void hide() {
    widget.state.hide();
  }

  Widget deleteItem() {
    return InkButton(
      onPressed: () {
        configs.profiles.remove(widget.item.id);
        hide();
      },
      backgroundColor: const Color.fromARGB(255, 235, 152, 152),
      overlayColor: const Color.fromARGB(84, 255, 24, 24),
      borderRadius: .zero,
      padding: .symmetric(horizontal: 8.w, vertical: 10.h),
      child: Row(
        children: [
          Icon(Icons.delete_outline_outlined, color: Colors.white, size: 16),
          12.horizontalSpace,
          Text(
            "Delete",
            style: .new(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: .w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget custom(IconData icon, String label, VoidCallback onTap) {
    return InkButton(
      onPressed: () {
        onTap();
        hide();
      },
      backgroundColor: Colors.transparent,
      overlayColor: const Color.fromARGB(82, 189, 189, 189),
      borderRadius: .zero,
      padding: .symmetric(horizontal: 8.w, vertical: 10.h),
      child: Row(
        children: [
          Icon(icon, size: 16),
          12.horizontalSpace,
          Text(
            label,
            style: .new(
              color: .new(0xFF333333),
              fontSize: 14.sp,
              fontWeight: .w500,
            ),
          ),
        ],
      ),
    );
  }
}
