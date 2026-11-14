import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';

class BottomNavBar extends StatefulWidget {
  const BottomNavBar({
    super.key,
    required this.items,
    required this.index,
    this.initIndex = 0,
    required this.onTap,
  });
  final List<BottomNavigationBarItem> items;

  final int index;
  final int initIndex;

  final ValueChanged<int> onTap;

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  @override
  void initState() {
    super.initState();
  }

  void onChanged(int index) {
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < widget.items.length; i++)
          Expanded(
            child: _ItemWidget(
              item: widget.items[i],
              index: i,
              indexNotifier: widget.index,
              onChanged: onChanged,
            ),
          ),
      ],
    );
  }
}

class _ItemWidget extends StatelessWidget {
  const _ItemWidget({
    required this.item,
    required this.indexNotifier,
    required this.index,
    required this.onChanged,
  });
  final BottomNavigationBarItem item;
  final int indexNotifier;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isActive = indexNotifier == index;
    final icon = Stack(
      children: [
        Offstage(offstage: !isActive, child: item.activeIcon),
        Offstage(offstage: isActive, child: item.icon),
      ],
    );

    final body = InkButton.text(
      onPressed: () => onChanged(index),
      overlayColor: const Color.fromARGB(60, 216, 216, 216),
      padding: EdgeInsets.all(10.r),
      shape: const CircleBorder(),
      child: Center(child: icon),
    );

    final child = Container(
      padding: EdgeInsets.symmetric(horizontal: 5.w),
      alignment: Alignment.center,
      child: body,
    );

    return child;
  }
}
