import 'package:clashy/_route/routes.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';

class ClashApp extends StatefulWidget {
  const ClashApp({super.key});

  @override
  State<ClashApp> createState() => _ClashAppState();
}

class _ClashAppState extends State<ClashApp> {
  Widget _build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      restorationScopeId: 'clashy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        extensions: [AppColorsType.light.colors],
      ),
      darkTheme: ThemeData.dark().copyWith(
        extensions: [AppColorsType.dark.colors],
      ),
      themeMode: AppSettings.themeMode.value,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        return UnFocus(child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _build.cs;
  }
}
