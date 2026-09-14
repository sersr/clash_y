// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routes.dart';

// **************************************************************************
// RouterGenerator
// **************************************************************************

// ignore_for_file: prefer_const_constructors

class Routes {
  Routes._();

  static Routes? _instance;

  static Routes init({
    bool newInstance = false,
    Map<String, dynamic> params = const {},
    Map<String, dynamic>? extra,
    Object? groupId,
    bool updateLocation = false,
    List<NavigatorObserver> observers = const [],
  }) {
    if (!newInstance && _instance != null) {
      return _instance!;
    }
    final instance = _instance = Routes._();
    instance._init(params, extra, groupId, observers, updateLocation);
    return instance;
  }

  void _init(
    Map<String, dynamic> params,
    Map<String, dynamic>? extra,
    Object? groupId,
    List<NavigatorObserver> observers,
    bool updateLocation,
  ) {
    _home = NPageMain(
      path: '/',
      pageBuilder: (entry) {
        return MaterialIgnorePage(
          key: entry.pageKey,
          entry: entry,
          child: const Home(),
        );
      },
    );

    _router = NRouter(
      rootPage: _home,
      params: params,
      extra: extra,
      groupId: groupId,
      observers: observers,
      updateLocation: updateLocation,
    );
  }

  late final NRouter _router;
  static NRouter get router => _instance!._router;
  late final NPageMain _home;
  static NPageMain get home => _instance!._home;
}

class NavRoutes {
  NavRoutes._();

  /// [groupId]
  /// see: [NPage.newGroupKey]
  static RouterAction home({dynamic groupId}) {
    return RouterAction(Routes.home, Routes.router, groupId: groupId);
  }
}
