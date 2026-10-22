import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:installed_apps/installed_apps.dart';

class InstalledApplication {
  const InstalledApplication({
    required this.packageName,
    required this.name,
    required this.isSystem,
    required this.icon,
  });

  final String packageName;
  final String name;
  final bool isSystem;
  final Uint8List? icon;
}

class ApplicationListController with NopLifecycle {
  final _applications = <InstalledApplication>[].al;
  List<InstalledApplication> get applications => _applications.value;

  final _selectedPackages = <String>[].al;
  List<String> get selectedPackages => _selectedPackages.value;

  final _showSystemApps = false.al;
  bool get showSystemApps => _showSystemApps.value;

  final _isAllowList = false.al;
  bool get isAllowList => _isAllowList.value;

  final _loading = true.al;
  bool get loading => _loading.value;

  final _searchText = ''.al;
  String get searchText => _searchText.value;

  final AV<String?> _loadError = .val(null);
  String? get loadError => _loadError.value;

  int _loadGeneration = 0;

  ApplicationListController() {
    _initializeSelection();
  }

  void _initializeSelection() {
    _isAllowList.value = SettingsHive.applicationListMode.value == 'whitelist';
    _selectedPackages.value = [
      ...(isAllowList
          ? SettingsHive.allowApplications.value
          : SettingsHive.disAllowApplications.value),
    ];
  }

  @override
  void nopInit() {
    super.nopInit();
    loadApplications();
  }

  List<InstalledApplication> get visibleApplications {
    final query = searchText.trim().toLowerCase();
    return applications.where((application) {
      if (!showSystemApps && application.isSystem) return false;
      return query.isEmpty ||
          application.name.toLowerCase().contains(query) ||
          application.packageName.toLowerCase().contains(query);
    }).toList();
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
      final result = await InstalledApps.getInstalledApps(
        excludeSystemApps: !showSystemApps,
        excludeNonLaunchableApps: true,
        withIcon: true,
        detectPlatformType: false,
      );
      if (generation != _loadGeneration) return;
      _applications.value = result
          .map(
            (app) => InstalledApplication(
              packageName: app.packageName,
              name: app.name,
              isSystem: app.isSystemApp,
              icon: app.icon,
            ),
          )
          .toList();
    } catch (_) {
      if (generation != _loadGeneration) return;
      _loadError.value = 'Could not load installed applications.';
    }
    if (generation != _loadGeneration) return;
    _loading.value = false;
  }

  void setShowSystemApps(bool value) {
    if (showSystemApps == value) return;
    _showSystemApps.value = value;
    loadApplications();
  }

  void setSearchText(String value) {
    _searchText.value = value;
  }

  void switchMode(bool allowList) {
    if (isAllowList == allowList) return;
    _isAllowList.value = allowList;
    _selectedPackages.value = [
      ...(allowList
          ? SettingsHive.allowApplications.value
          : SettingsHive.disAllowApplications.value),
    ];
    SettingsHive.applicationListMode.value = allowList
        ? 'whitelist'
        : 'blacklist';
  }

  void toggleApplication(String packageName) {
    final selected = [...selectedPackages];
    if (selected.contains(packageName)) {
      selected.remove(packageName);
    } else {
      selected.add(packageName);
    }
    _selectedPackages.value = selected;
    final selectedList = selected..sort();
    if (isAllowList) {
      SettingsHive.allowApplications.value = selectedList;
    } else {
      SettingsHive.disAllowApplications.value = selectedList;
    }
  }

  @override
  void nopDispose() {
    _loadGeneration++;
    super.nopDispose();
  }
}
