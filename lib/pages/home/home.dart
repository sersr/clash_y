import 'package:clashy/pages/home/widget/settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nop/router.dart';

import 'controller/clash_connection_controller.dart';
import 'controller/clash_controller.dart';
import 'widget/clash_config_url.dart';
import 'widget/clash_connections.dart';
import 'widget/clash_home.dart';

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
      clashMainNotifier.refreshOnResume();
      clashConnectionsNotifier.toggle(_notifier.value == 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      const ClashHome(),
      const ClashProfiles(),
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
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.menu_book_outlined),
                activeIcon: Icon(Icons.menu_book),
                label: 'Profiles',
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
                clashMainNotifier.refreshOnResume();
              }
              _notifier.value = index;

              clashConnectionsNotifier.toggle(_notifier.value == 2);
            },
          );
        },
      ),
    );
  }
}
