import 'package:clashy/event/base/data.dart';
import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';

import '../controller/clash_controller.dart';
import 'clash_list_item.dart';

class ClashHome extends StatefulWidget {
  const new({super.key});

  @override
  State<ClashHome> createState() => _ClashHomeState();
}

class _ClashHomeState extends State<ClashHome> {
  late final ClashController clashMainNotifier = getType();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade300,
      child: SafeArea(
        child: Cs(() {
          final data = clashMainNotifier.data;
          final proxies = data?.proxies;
          final hasData =
              proxies != null &&
              proxies.any((element) => proxyHasData(element));
          if (data == null || proxies == null) {
            return Loading();
          }

          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Refresh(
                      isEmpty: !hasData,
                      refresh: buildDefaultRefresh(clashMainNotifier.getData),
                      emptyWidget: Center(
                        child: Text(
                          "Empty",
                          style: .new(
                            color: Colors.grey.shade200,
                            fontSize: 13.sp,
                          ),
                        ),
                      ),
                      slivers: [
                        for (var item in proxies)
                          ClashListItem(proxyItem: item),
                        SliverToBoxAdapter(child: 70.verticalSpace),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(right: 10.w, bottom: 10.h, child: _action.cs),
            ],
          );
        }),
      ),
    );
  }

  Widget _action() {
    final running = clashMainNotifier.isRunning;
    final loading = clashMainNotifier.isStarting;
    return FloatingActionButton(
      onPressed: loading
          ? null
          : () {
              if (running) {
                clashMainNotifier.stop();
              } else {
                clashMainNotifier.start();
              }
            },
      tooltip: loading
          ? 'Starting Clash'
          : running
          ? 'Stop Clash'
          : 'Start Clash',
      child: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(running ? Icons.stop : Icons.play_arrow),
    );
  }
}
