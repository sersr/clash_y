import 'dart:io' show Platform;

import 'package:clashy/pages/home/controller/clash_controller.dart';
import 'package:common/common.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:install_apps/install_apps.dart';

class ApplicationListController with NopLifecycle, AlScopeManager {
  final _applications = <InstalledApplication>[].al;
  List<InstalledApplication> get applications => _applications.value;

  final whiteList = SettingsHive.allowApplications.value.toList().al;
  final blackList = SettingsHive.disAllowApplications.value.toList().al;
  final mode = SettingsHive.applicationListMode.value.al;

  final showSystemApps = false.al;
  final showNoInternetApps = false.al;

  late final _isSellectAll = () {
    final list = selectedPackages;
    if (list.isEmpty) {
      return false;
    }
    final va = _filtedApplications.value.every(
      (e) => list.contains(e.packageName),
    );
    return va;
  }.mount(this);

  bool get isSellectAll => _isSellectAll.value;

  late final _selectedPackages = () {
    final v = mode.value;
    final list = switch (v) {
      .none => const <String>[],
      .blackList => blackList,
      .whiteList => whiteList,
    };

    return list;
  }.mount(this);

  List<String> get selectedPackages => _selectedPackages.value;

  late final _filtedApplications = () {
    final query = searchText.trim().toLowerCase();
    var showSys = showSystemApps.value;
    var showNo = showNoInternetApps.value;
    var isEmpty = query.isEmpty;

    return applications.where((application) {
      if (!showSys && application.systemApp) return false;
      if (!showNo && !application.hasInternetPermission) {
        return false;
      }
      return isEmpty ||
          application.appNameLow.contains(query) ||
          application.packageNameLow.contains(query);
    }).toList();
  }.mount(this);

  List<InstalledApplication> get visibleApplications =>
      _filtedApplications.value;

  final _loading = true.al;
  bool get loading => _loading.value;

  final _searchText = ''.al;
  String get searchText => _searchText.value;

  final AV<String?> _loadError = .val(null);
  String? get loadError => _loadError.value;

  late final hasChanged = () {
    final cacheBlack = SettingsHive.disAllowApplications.value;
    if (!equal.equals(cacheBlack, blackList.value)) {
      return true;
    }
    final cacheWhite = SettingsHive.allowApplications.value;
    if (!equal.equals(cacheWhite, whiteList)) {
      return true;
    }
    return mode.value != SettingsHive.applicationListMode.value;
  }.mount(this);

  int _loadGeneration = 0;

  late final AppLifecycleListener listener;

  @override
  void nopInit() {
    super.nopInit();
    listener = .new(
      onResume: () {
        if (applications.length < 2) {
          loadApplications();
        }
      },
    );
    loadApplications();
  }

  Future<void> loadApplications() async {
    final generation = ++_loadGeneration;
    _loading.value = true;
    _loadError.value = null;

    if (!Platform.isAndroid) {
      if (generation != _loadGeneration) return;
      _loading.value = false;
      _loadError.value = 'Application routing is available on Android only.';
      return;
    }

    try {
      final result = await InstallApps.getInstalledApps(
        includeSystemApps: true,
      );

      if (generation != _loadGeneration) return;
      _applications.value = result.toList();
    } catch (_) {
      if (generation != _loadGeneration) return;
      _loadError.value = 'Could not load installed applications.';
    }
    if (generation != _loadGeneration) return;
    _loading.value = false;
  }

  void selectAll() {
    switch (mode.value) {
      case .whiteList:
        final list = whiteList.value;
        final newList = {
          ...list,
          ...visibleApplications.map((e) => e.packageName),
        }.toList();
        newList.sort();
        whiteList.value = newList;
      case .blackList:
        final list = blackList.value;
        final newList = {
          ...list,
          ...visibleApplications.map((e) => e.packageName),
        }.toList();
        newList.sort();
        blackList.value = newList;
      case .none:
    }
  }

  void saveAndReload() {
    if (!hasChanged.value) return;
    SettingsHive.allowApplications.value = whiteList.value.toList();
    SettingsHive.disAllowApplications.value = blackList.value.toList();
    SettingsHive.applicationListMode.value = mode.value;

    final controller = getType<ClashController>();
    controller.restart();
  }

  bool get _clearable {
    return searchText.trim().isEmpty &&
        showSystemApps.value &&
        showNoInternetApps.value;
  }

  void removeSelectApps() {
    switch (mode.value) {
      case .whiteList:
        final list = whiteList;
        if (_clearable) {
          list.clear();
        } else {
          final removed = visibleApplications.map((e) => e.packageName);
          list.removeWhere((e) => removed.contains(e));
        }
        list.sort();
      case .blackList:
        final list = blackList;
        if (_clearable) {
          list.clear();
        } else {
          final removed = visibleApplications.map((e) => e.packageName);
          list.removeWhere((e) => removed.contains(e));
        }
        list.sort();
      case .none:
    }
  }

  void setShowSystemApps(bool value) {
    if (showSystemApps.value == value) return;
    showSystemApps.value = value;
  }

  void setSearchText(String value) {
    _searchText.value = value;
  }

  void switchMode(ApplicationListMode mode) {
    this.mode.value = mode;
  }

  void toggleApplication(String packageName) {
    switch (mode.value) {
      case .whiteList:
        if (whiteList.contains(packageName)) {
          whiteList.remove(packageName);
        } else {
          whiteList.add(packageName);
        }
      case .blackList:
        if (blackList.contains(packageName)) {
          blackList.remove(packageName);
        } else {
          blackList.add(packageName);
        }
      case .none:
    }
  }

  @override
  void nopDispose() {
    _loadGeneration++;
    listener.dispose();
    super.nopDispose();
  }
}
