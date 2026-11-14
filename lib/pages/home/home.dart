import 'package:clashy/pages/home/widget/home_bottom_padding.dart';
import 'package:clashy/pages/home/widget/settings.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:material_ui/material_ui.dart';

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

  final index = 0.al;

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
      clashConnectionsNotifier.toggle(index.value == 2);
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

    var items = const [
      BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home),
        label: 'Proxies',
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
    ];

    final tabbar = Cs(() {
      return DefaultTabController(
        initialIndex: index.value,
        length: items.length,
        child: TabBar(
          dividerHeight: 0,
          tabs: items.map((e) => e.icon).toList(),
          labelPadding: .all(8),
          splashBorderRadius: .circular(1000),
          overlayColor: WidgetStatePropertyAll(
            const Color.fromARGB(73, 216, 216, 216),
          ),
          indicator: ShapeDecoration(
            color: const Color.fromARGB(255, 229, 229, 229),
            shape: StadiumBorder(),
          ),
          indicatorSize: .tab,
          labelStyle: .new(color: const Color.fromARGB(255, 30, 110, 223)),
          unselectedLabelStyle: .new(
            color: const Color.fromARGB(255, 88, 88, 88),
          ),
          onTap: (index) {
            if (index == 0) {
              clashMainNotifier.refreshOnResume();
            }
            this.index.value = index;
            clashConnectionsNotifier.toggle(index == 2);
          },
        ),
      );
    });

    var bottomNav = Container(
      alignment: .center,
      child: Container(
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: .new(color: Colors.white, width: 2.r),
          ),
        ),
        child: Container(
          constraints: .new(maxWidth: 600.w),
          decoration: ShapeDecoration(
            color: const Color.fromARGB(255, 249, 248, 248),
            shape: StadiumBorder(),
          ),
          clipBehavior: .hardEdge,
          child: tabbar,
        ),
      ),
    );

    final homePadding = 20.h + Nav.bottomHeight;
    return Scaffold(
      body: Stack(
        children: [
          HomeBottomPadding(
            padding: homePadding + 50.h,
            child: Cs(() {
              return IndexedStack(index: index.value, children: children);
            }),
          ),
          Positioned(
            left: 20.w,
            right: 20.w,
            bottom: homePadding,
            child: bottomNav,
          ),
        ],
      ),
    );
  }
}
