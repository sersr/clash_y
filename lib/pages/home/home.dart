import 'package:clashy/pages/home/widget/settings.dart';
import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:useful_tools/useful_tools.dart';

import '../../event/event.dart';
import 'controller/clash_connection_controller.dart';
import 'controller/clash_controller.dart';
import 'widget/clash_config_url.dart';
import 'widget/clash_connections.dart';
import 'widget/clash_list_item.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  late ClashController clashMainNotifier = getType();
  late ClashConnectionController clashConnectionsNotifier = getType();

  final _notifier = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台暂停 1s 连接轮询，回前台恢复。
    if (state == AppLifecycleState.paused) {
      clashConnectionsNotifier.toggle(false);
      clashMainNotifier.stopListen();
    } else if (state == AppLifecycleState.resumed) {
      clashMainNotifier.getData();
      clashConnectionsNotifier.toggle(_notifier.value == 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      clashPage(),
      const ClashConfigUrl(),
      const ClashConnections(),
      const Settings(),
    ];
    return Scaffold(
      body: AnimatedBuilder(
        animation: _notifier,
        builder: (context, _) {
          return IndexedStack(index: _notifier.value, children: children);
        },
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _notifier,
        builder: (context, _) {
          return BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            iconSize: 24,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            selectedItemColor: const Color.fromARGB(255, 1, 139, 194),
            unselectedItemColor: const Color.fromARGB(255, 129, 129, 129),
            unselectedLabelStyle: const TextStyle(
              color: Color.fromARGB(255, 73, 73, 73),
            ),
            selectedLabelStyle: const TextStyle(
              color: Color.fromARGB(255, 3, 3, 3),
            ),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'clash',
                tooltip: 'Clash',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.menu_book_outlined),
                activeIcon: Icon(Icons.menu_book),
                label: 'configs',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.device_hub_outlined),
                activeIcon: Icon(Icons.device_hub),
                label: 'connections',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings),
                label: 'settings',
              ),
            ],
            currentIndex: _notifier.value,
            onTap: (index) {
              if (index == 0) {
                clashMainNotifier.getData();
              }
              _notifier.value = index;

              clashConnectionsNotifier.toggle(_notifier.value == 2);
            },
          );
        },
      ),
      floatingActionButton: Cs(() {
        final running = clashMainNotifier.isRunning;
        final transitioning = clashMainNotifier.isTransitioning;
        return FloatingActionButton(
          onPressed: transitioning
              ? null
              : () {
                  if (running) {
                    clashMainNotifier.stop();
                  } else {
                    clashMainNotifier.start();
                  }
                },
          tooltip: transitioning
              ? 'Please wait'
              : running
              ? 'Stop Clash'
              : 'Start Clash',
          child: transitioning
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(running ? Icons.stop : Icons.play_arrow),
        );
      }),
    );
  }

  Widget actions() {
    return Wrap(
      spacing: 10,
      children: [
        InkButton(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          onPressed: () {
            clashMainNotifier.uninstall();
          },
          child: Text('unregister'),
        ),
        InkButton(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          onPressed: () {
            clashMainNotifier.startListen();
          },
          child: Text("start listen"),
        ),
        InkButton(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          onPressed: () {
            clashMainNotifier.stopListen();
          },
          child: Text("stop listen"),
        ),
      ],
    );
  }

  Widget clashPage() {
    return ColoredBox(
      color: Colors.grey.shade300,
      child: SafeArea(
        child: Cs(() {
          final data = clashMainNotifier.data;
          final proxies = data?.proxies;
          final hasData =
              proxies != null &&
              proxies.any((element) => proxyHasData(element));
          if (data == null) {
            return loadingIndicator();
          } else if (!hasData) {
            final child = reloadBotton(clashMainNotifier.getData);
            return Column(children: [actions(), child]);
          }
          return Column(
            children: [
              actions(),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    for (var item in proxies) ClashListItem(proxyItem: item),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

void calb() {}
