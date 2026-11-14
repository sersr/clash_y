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
    __applicationList = NPage(
      path: 'applicationList',
      pageBuilder: (entry) {
        return MaterialIgnorePage(
          key: entry.pageKey,
          entry: entry,
          child: const ApplicationListPage(),
        );
      },
    );

    __profileScriptPage = NPage(
      path: 'profileScriptPage',
      pageBuilder: (entry) {
        return MaterialIgnorePage(
          key: entry.pageKey,
          entry: entry,
          child: const ProfileScriptPage(),
        );
      },
    );

    __scriptEdit = NPage(
      path: 'scriptEdit',
      pageBuilder: (entry) {
        var item = entry.queryParams['item'];
        if (item is! ProfileScriptModel?) {
          item = ProfileScriptModel.fromJson(item);
        }
        var id = entry.queryParams['id'];
        return MaterialIgnorePage(
          key: entry.pageKey,
          entry: entry,
          child: ScriptEdit(item: item, id: id),
        );
      },
    );

    __scriptSelect = NPage(
      path: 'scriptSelect',
      pageBuilder: (entry) {
        var current = entry.queryParams['current'];
        if (current is! ProfileScriptModel?) {
          current = ProfileScriptModel.fromJson(current);
        }
        return MaterialIgnorePage(
          key: entry.pageKey,
          entry: entry,
          child: ScriptSelect(current: current),
        );
      },
    );

    __clashSettings = NPage(
      path: 'clashSettings',
      pageBuilder: (entry) {
        return MaterialIgnorePage(
          key: entry.pageKey,
          entry: entry,
          child: const ClashSettings(),
        );
      },
    );

    _home = NPageMain(
      pages: [
        __applicationList,
        __profileScriptPage,
        __scriptEdit,
        __scriptSelect,
        __clashSettings,
      ],
      path: '/',
      pageBuilder: (entry) {
        return MaterialIgnorePage(
          key: entry.pageKey,
          entry: entry,
          child: const Home(),
        );
      },
    );

    NRouterJsonTransfrom.putToJsonFn<ProfileScriptModel>((null,));
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
  late final NPage __applicationList;
  static NPage get _applicationList => _instance!.__applicationList;
  late final NPage __profileScriptPage;
  static NPage get _profileScriptPage => _instance!.__profileScriptPage;
  late final NPage __scriptEdit;
  static NPage get _scriptEdit => _instance!.__scriptEdit;
  late final NPage __scriptSelect;
  static NPage get _scriptSelect => _instance!.__scriptSelect;
  late final NPage __clashSettings;
  static NPage get _clashSettings => _instance!.__clashSettings;
  late final NPageMain _home;
  static NPageMain get home => _instance!._home;
}

class NavRoutes {
  NavRoutes._();

  /// [groupId]
  /// see: [NPage.newGroupKey]
  static RouterAction applicationList({dynamic groupId}) {
    return RouterAction(
      Routes._applicationList,
      Routes.router,
      groupId: groupId,
    );
  }

  /// [groupId]
  /// see: [NPage.newGroupKey]
  static RouterAction profileScriptPage({dynamic groupId}) {
    return RouterAction(
      Routes._profileScriptPage,
      Routes.router,
      groupId: groupId,
    );
  }

  /// [groupId]
  /// see: [NPage.newGroupKey]
  static RouterAction scriptEdit({
    required ProfileScriptModel? item,
    required String? id,
    dynamic groupId,
  }) {
    return RouterAction(
      Routes._scriptEdit,
      Routes.router,
      extra: {'item': item, 'id': id},
      groupId: groupId,
    );
  }

  /// [groupId]
  /// see: [NPage.newGroupKey]
  static RouterAction scriptSelect({
    ProfileScriptModel? current,
    dynamic groupId,
  }) {
    return RouterAction(
      Routes._scriptSelect,
      Routes.router,
      extra: {'current': current},
      groupId: groupId,
    );
  }

  /// [groupId]
  /// see: [NPage.newGroupKey]
  static RouterAction clashSettings({dynamic groupId}) {
    return RouterAction(Routes._clashSettings, Routes.router, groupId: groupId);
  }

  /// [groupId]
  /// see: [NPage.newGroupKey]
  static RouterAction home({dynamic groupId}) {
    return RouterAction(Routes.home, Routes.router, groupId: groupId);
  }
}
