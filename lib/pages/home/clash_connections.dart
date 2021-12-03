import 'package:flutter/material.dart';
import '../../providers/clash_conections.dart';
import 'package:provider/provider.dart';
import 'package:useful_tools/useful_tools.dart';

class ClashConnections extends StatefulWidget {
  const ClashConnections({Key? key}) : super(key: key);

  @override
  _ClashConnectionsState createState() => _ClashConnectionsState();
}

class _ClashConnectionsState extends State<ClashConnections> {
  late ClashConnectionsNotifier clashConnectionsNotifier;
  late ScrollController controller;

  @override
  void initState() {
    super.initState();
    controller = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    clashConnectionsNotifier = context.read();
    if (!clashConnectionsNotifier.listening) {
      clashConnectionsNotifier.watchConnections();
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = AnimatedBuilder(
        animation: clashConnectionsNotifier,
        builder: (context, _) {
          final data = clashConnectionsNotifier.connections;
          final connections = data?.connections;
          if (data == null) {
            return loadingIndicator();
          } else if (connections == null) {
            return reloadBotton(clashConnectionsNotifier.watchConnections);
          }

          return ListViewBuilder(
              scrollController: controller,
              itemCount: connections.length,
              itemBuilder: (context, index) {
                final item = connections[index];
                var download = 0;
                var upload = 0;
                var lastChain = '';
                if (item?.chains?.isNotEmpty == true) {
                  lastChain = '${item?.chains?.first}';
                }
                if (item?.download != null) {
                  download = item!.download! ~/ 1000;
                }
                if (item?.upload != null) {
                  upload = item!.upload! ~/ 1000;
                }
                return ListItem(
                    bgColor: const Color.fromARGB(255, 214, 214, 214),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item?.metadata?.host}',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        btn1(
                            radius: 3,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 4),
                            bgColor: Colors.blue,
                            child: Text(
                              lastChain,
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade100),
                            )),
                        const SizedBox(width: 6),
                        btn1(
                            radius: 3,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 4),
                            bgColor: const Color.fromARGB(255, 27, 156, 15),
                            child: Text(
                              '$download kb | $upload kb',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade100),
                            ))
                      ],
                    ));
              });
        });
    return child;
  }
}
