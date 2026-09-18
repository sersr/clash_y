import 'package:flutter/material.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:useful_tools/useful_tools.dart';

import '../../../data/data.dart';
import '../controller/clash_main_provider.dart';

class ClashListItem extends StatefulWidget {
  const ClashListItem({super.key, required this.proxyItem});
  final ProxyItem proxyItem;
  @override
  State<ClashListItem> createState() => _ClashListItemState();
}

class _ClashListItemState extends State<ClashListItem> {
  late final ClashMainNotifier clashMainNotifier = context.getType();

  final _showBody = ValueNotifier(false);
  @override
  Widget build(BuildContext context) {
    var header = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: btn1(
        bgColor: const Color.fromARGB(255, 79, 181, 228),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onTap: () {
          _showBody.value = !_showBody.value;
        },
        child: Text(
          '${widget.proxyItem.name}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            fontFamily: '微软雅黑',
          ),
        ),
      ),
    );
    var body = AnimatedBuilder(
      animation: _showBody,
      builder: (context, _) {
        final proxyItem = widget.proxyItem;
        final items = proxyItem.all;
        if (_showBody.value && items != null) {
          return SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = items[index];
              return ProxyCard(
                itemName: '$item',
                proxyGroupName: '${proxyItem.name}',
                type: '${proxyItem.type}',
                selected: proxyItem.now != null && proxyItem.now == item,
              );
            }, childCount: items.length),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              mainAxisExtent: 60,
              crossAxisCount: 2,
            ),
          );
        }
        return const SliverToBoxAdapter(child: SizedBox());
      },
    );

    return SliverMainAxisGroup(
      slivers: [
        PinnedHeaderSliver(child: header),
        body,
      ],
    );
  }
}

class ProxyCard extends StatelessWidget {
  const ProxyCard({
    super.key,
    required this.itemName,
    required this.selected,
    required this.type,
    required this.proxyGroupName,
    this.left,
  });
  final String type;
  final String proxyGroupName;
  final String itemName;
  final bool selected;
  final bool? left;
  @override
  Widget build(BuildContext context) {
    final clashMainNotifier = context.getType<ClashMainNotifier>();
    final select = clashMainNotifier.getSelector(itemName);

    return ListItem(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      outPadding: EdgeInsets.only(
        left: left == true ? 8 : 4,
        right: left == false ? 8 : 4,
        top: 3,
        bottom: 3,
      ),
      onTap: () {
        if (type == 'Selector') {
          clashMainNotifier.selectProxy(proxyGroupName, itemName);
        }
      },
      bgColor: selected ? Colors.grey.shade400 : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Cs(() {
                return Text(
                  clashMainNotifier.getName(itemName),
                  maxLines: 2,
                  style: const TextStyle(
                    overflow: TextOverflow.ellipsis,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFamily: '微软雅黑',
                  ),
                );
              }
            ),
          ),
          RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.only(left: 5),
              child: btn1(
                onTap: () {
                  clashMainNotifier.getDelay(itemName);
                },
                radius: 3,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                bgColor: Colors.transparent,
                child: AnimatedBuilder(
                  animation: select,
                  builder: (context, _) {
                    final timeout = select.value == 0;
                    final test = select.value == -1;
                    var delayStr = timeout
                        ? 'timeout'
                        : test
                        ? 'testing'
                        : '${select.value} ms';

                    return Text(
                      delayStr,
                      style: TextStyle(
                        color: timeout
                            ? const Color.fromARGB(255, 247, 88, 76)
                            : Colors.green.shade600,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProxyListItem extends StatefulWidget {
  const ProxyListItem({super.key});

  @override
  State<ProxyListItem> createState() => _ProxyListItemState();
}

class _ProxyListItemState extends State<ProxyListItem> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
