import 'package:flutter/material.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:useful_tools/useful_tools.dart';

import '../../event/event.dart';
import '../../event/repository.dart';
import 'controller/clash_connection_controller.dart';
import 'controller/clash_controller.dart';
import 'controller/configs_controller.dart';
import 'widget/clash_config_url.dart';
import 'widget/clash_connections.dart';
import 'widget/clash_list_item.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late Repository repository = getType();
  late ClashController clashMainNotifier = getType();
  late ConfigsController clashConfigNotifier = getType();
  late ClashConnectionController clashConnectionsNotifier = getType();

  final open = ValueNotifier(true);
  final _notifier = ValueNotifier(0);
  @override
  Widget build(BuildContext context) {
    final children = [
      clashPage(),
      const ClashConfigUrl(),
      const ClashConnections(),
      win32(),
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
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedFontSize: 14,
            unselectedFontSize: 14,
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
                icon: Icon(Icons.air_sharp),
                label: 'clash',
                tooltip: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.confirmation_number_outlined),
                label: 'configs',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.cloud_download_rounded),
                label: 'connections',
              ),
              BottomNavigationBarItem(icon: Icon(Icons.window), label: 'win32'),
            ],
            currentIndex: _notifier.value,
            onTap: (index) {
              if (_notifier.value == 0 && index == 0) {
                clashMainNotifier.getData();
              }
              _notifier.value = index;

              clashConnectionsNotifier.toggle(_notifier.value == 2);
            },
          );
        },
      ),
      floatingActionButton: AnimatedBuilder(
        animation: open,
        builder: (context, _) {
          return FloatingActionButton(
            onPressed: () {
              if (open.value) {
                repository.close();
              } else {
                repository.init();
              }
              setState(() {
                open.value = !open.value;
                if (open.value) {
                  clashConfigNotifier.getConfigs();
                  clashConnectionsNotifier.watchConnections();
                  clashConnectionsNotifier.toggle(_notifier.value == 2);
                }
              });
            },
            child: Text('${open.value}'),
          );
        },
      ),
    );
  }

  final hideOnClose = ValueNotifier(true);
  Widget win32() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Wrap(
          children: [
            const SizedBox(height: 10),
            Center(
              child: btn1(
                bgColor: const Color.fromARGB(255, 43, 121, 97),
                radius: 5,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                child: AnimatedBuilder(
                  animation: hideOnClose,
                  builder: (context, _) {
                    return Text(
                      hideOnClose.value ? 'status: 缩小到托盘' : 'status: 关闭应用',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: const Color.fromARGB(255, 226, 226, 226),
                          ),
                    );
                  },
                ),
                onTap: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget actions() {
    return Wrap(
      spacing: 10,
      children: [
        btn1(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          onTap: () {
            clashMainNotifier.stop();
          },
          child: Text('stop'),
        ),

        btn1(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          onTap: () {
            clashMainNotifier.stop();
          },
          child: Text('unregister'),
        ),
        btn1(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          onTap: () async {
            clashMainNotifier.start();
          },
          child: Text("start"),
        ),

        btn1(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          onTap: () {
            clashMainNotifier.stopListen();
          },
          child: Text("stop listen"),
        ),

        btn1(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          onTap: () {
            clashMainNotifier.logConfig();
          },
          child: Text("configs"),
        ),
        btn1(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          onTap: () {
            clashMainNotifier.startListen();
          },
          child: Text("start listen"),
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
            return Column(
              children: [
                actions(),
                GestureDetector(
                  onTap: () async {
                    clashMainNotifier.stop();
                  },
                  child: Text("unregister"),
                ),
                child,
              ],
            );
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
