import 'package:clash_window_dll/clash_window_dll.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:useful_tools/useful_tools.dart';

import '../../event/event.dart';
import '../../event/repository.dart';

import '../../providers/providers.dart';
import 'clash_config_url.dart';
import 'clash_connections.dart';
import 'clash_list_item.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late Repository repository;
  late ClashMainNotifier clashMainNotifier;
  late ClashConfigNotifier clashConfigNotifier;
  late ClashConnectionsNotifier clashConnectionsNotifier;
  @override
  void initState() {
    super.initState();
    ClashWindowDll.onShowWindow = _onShowWindow;
  }

  @override
  void dispose() {
    ClashWindowDll.onShowWindow = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    repository = context.read();
    clashMainNotifier = context.read();
    clashConfigNotifier = context.read();
    clashConnectionsNotifier = context.read();
    repository.init();
    clashMainNotifier.getData();
    EventQueue.runOneTaskOnQueue(hideOnClose, () async {
      hideOnClose.value = await ClashWindowDll.hideOnClose;
    });
  }

  void _onShowWindow() {
    setState(() {});
  }

  final open = ValueNotifier(true);
  final _notifier = ValueNotifier(0);
  @override
  Widget build(BuildContext context) {
    final children = [
      clashPage(),
      const ClashConfigUrl(),
      const ClashConnections(),
      win32()
    ];
    return Scaffold(
      body: AnimatedBuilder(
          animation: _notifier,
          builder: (context, _) {
            return IndexedStack(
              children: children,
              index: _notifier.value,
            );
          }),
      bottomNavigationBar: AnimatedBuilder(
        animation: _notifier,
        builder: (context, _) {
          return BottomNavigationBar(
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedFontSize: 14,
            unselectedFontSize: 14,
            selectedItemColor: const Color.fromARGB(255, 51, 51, 51),
            unselectedItemColor: const Color.fromARGB(255, 182, 182, 182),
            unselectedLabelStyle:
                const TextStyle(color: Color.fromARGB(255, 126, 126, 126)),
            selectedLabelStyle:
                const TextStyle(color: Color.fromARGB(255, 3, 3, 3)),
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.air_sharp), label: 'clash', tooltip: ''),
              BottomNavigationBarItem(
                  icon: Icon(Icons.confirmation_number_outlined),
                  label: 'configs'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.cloud_download_rounded),
                  label: 'connections'),
              BottomNavigationBarItem(icon: Icon(Icons.window), label: 'win32')
            ],
            currentIndex: _notifier.value,
            onTap: (index) {
              if(_notifier.value == 0 && index == 0) {
                clashMainNotifier.getData();
              }
              _notifier.value = index;

              clashConnectionsNotifier.pauseOrResume(_notifier.value != 2);
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
                    clashConnectionsNotifier
                        .pauseOrResume(_notifier.value != 2);
                  }
                });
              },
              child: Text('${open.value}'),
            );
          }),
    );
  }

  final hideOnClose = ValueNotifier(true);
  Widget win32() {
    return Container(
        color: Colors.grey.shade200,
        child: Center(
          child: Wrap(children: [
            const SizedBox(height: 10),
            Center(
              child: btn1(
                  bgColor: const Color.fromARGB(255, 43, 121, 97),
                  radius: 5,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  child: AnimatedBuilder(
                      animation: hideOnClose,
                      builder: (context, _) {
                        return Text(
                          hideOnClose.value ? 'status: 缩小到托盘' : 'status: 关闭应用',
                          style: Theme.of(context)
                              .textTheme
                              .headline6
                              ?.copyWith(
                                  color:
                                      const Color.fromARGB(255, 226, 226, 226)),
                        );
                      }),
                  onTap: () {
                    EventQueue.runOneTaskOnQueue(hideOnClose, () {
                      hideOnClose.value = !hideOnClose.value;
                      ClashWindowDll.setHideOnClose(hideOnClose.value);
                    });
                  }),
            ),
          ]),
        ));
  }

  Widget clashPage() {
    return ColoredBox(
      color: Colors.grey.shade300,
      child: AnimatedBuilder(
          animation: clashMainNotifier,
          builder: (context, _) {
            final data = clashMainNotifier.data;
            final proxies = data?.proxies;
            final hasData = proxies != null &&
                proxies.any((element) => proxyHasData(element));
            if (data == null) {
              return loadingIndicator();
            } else if (!hasData) {
              return reloadBotton(clashMainNotifier.getData);
            }
            return CustomScrollView(
              slivers: [
                for (var item in proxies) ClashListItem(proxyItem: item)
              ],
            );
          }),
    );
  }
}
