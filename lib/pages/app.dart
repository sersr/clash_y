import 'package:clash_y/_route/routes.dart';
import 'package:flutter/material.dart';

class ClashApp extends StatefulWidget {
  const ClashApp({super.key});

  @override
  State<ClashApp> createState() => _ClashAppState();
}

class _ClashAppState extends State<ClashApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      restorationScopeId: 'clashy',
      debugShowCheckedModeBanner: false,
    );
  }
}
