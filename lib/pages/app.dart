import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../event/repository.dart';
import '../providers/providers.dart';
import 'home/home.dart';

class MultiProviders extends StatelessWidget {
  const MultiProviders({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => Repository()),
        ChangeNotifierProvider(
            create: (context) => ClashMainNotifier(context.read())),
        ChangeNotifierProvider(
            create: (context) =>
                ClashConfigNotifier(context.read(), context.read())),
        ChangeNotifierProvider(
            create: (context) => ClashConnectionsNotifier(context.read())),
      ],
      child: const ClashApp(),
    );
  }
}

class ClashApp extends StatefulWidget {
  const ClashApp({Key? key}) : super(key: key);

  @override
  _ClashAppState createState() => _ClashAppState();
}

class _ClashAppState extends State<ClashApp> {
  @override
  Widget build(BuildContext context) {
    return const   DefaultTextStyle(
      style: TextStyle(fontFamily: '微软雅黑'),
      child: MaterialApp(
        home:  Home(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
