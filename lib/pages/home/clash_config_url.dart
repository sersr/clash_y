import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:useful_tools/useful_tools.dart';

import '../../providers/clash_configs.dart';

class ClashConfigUrl extends StatefulWidget {
  const ClashConfigUrl({Key? key}) : super(key: key);

  @override
  _ClashConfigUrlState createState() => _ClashConfigUrlState();
}

class _ClashConfigUrlState extends State<ClashConfigUrl> {
  late ClashConfigNotifier clashConfigNotifier;

  late TextEditingController textEditingController;
  late FocusNode focusNode;
  late ScrollController controller;

  @override
  void initState() {
    super.initState();
    textEditingController = TextEditingController();
    focusNode = FocusNode();
    controller = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    clashConfigNotifier = context.read();
    if (!clashConfigNotifier.listening) {
      clashConfigNotifier.getConfigs();
    }
  }

  @override
  void didUpdateWidget(covariant ClashConfigUrl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!clashConfigNotifier.listening) {
      clashConfigNotifier.getConfigs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
                color: Color.fromARGB(255, 67, 166, 247),
                boxShadow: [
                  BoxShadow(color: Colors.grey, offset: Offset(0, 1))
                ]),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Center(
                      child: Container(
                        decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 244, 245, 245),
                            borderRadius: BorderRadius.circular(100)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: TextField(
                          smartQuotesType: SmartQuotesType.disabled,
                          decoration: const InputDecoration.collapsed(hintText: 'url'),
                          showCursor: true,
                          controller: textEditingController,
                          focusNode: focusNode,
                          smartDashesType: SmartDashesType.disabled,
                          style: TextStyle(color: Colors.grey.shade900),
                          cursorColor: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
                MaterialButton(
                    onPressed: () {
                      final text = textEditingController.text;
                      final url = Uri.tryParse(text);
                      if (url != null && url.scheme.contains('http')) {
                        clashConfigNotifier.addNewConfigUrl(text, null, 0);
                      }
                    },
                    child: const Text(
                      'download',
                      style: TextStyle(color: Colors.white),
                    ))
              ],
            ),
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
              animation: clashConfigNotifier,
              builder: (context, _) {
                final tables = clashConfigNotifier.tables;
                if (tables == null) {
                  return loadingIndicator();
                } else if (tables.isEmpty) {
                  return reloadBotton(clashConfigNotifier.getConfigs);
                }
                return ListViewBuilder(
                  scrollController: controller,
                  color: Colors.grey.shade200,
                  itemCount: tables.length,
                  itemBuilder: (context, index) {
                    final item = tables[index];
                    final url = item.url ?? '';
                    final name = item.name ?? url;
                    final updateInterval = item.updateInterval ?? 0;
                    final updateTime = item.updateTime ?? DateTime.now();
                    return ListItem(
                        bgColor: clashConfigNotifier.current == url
                            ? Color.fromARGB(255, 179, 192, 192)
                            : null,
                        onTap: () {
                          clashConfigNotifier.reloadConfig(url);
                        },
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(name)),
                            Text(updateTime.difference(DateTime.now()).ago),
                            TextButton(
                                onPressed: () {
                                  clashConfigNotifier.updateConfigData(url);
                                },
                                child: const Text('update'))
                          ],
                        ));
                  },
                );
              }),
        ),
      ],
    );
  }
}
