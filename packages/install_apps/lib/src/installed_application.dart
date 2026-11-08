/// Basic information for an application visible to Android's PackageManager.
class InstalledApplication {
  InstalledApplication({
    required this.appName,
    required this.packageName,
    required this.systemApp,
    required this.hasInternetPermission,
  }) : appNameLow = appName.toLowerCase(),
       packageNameLow = packageName.toLowerCase();

  final String appName;
  final String appNameLow;
  final String packageName;
  final String packageNameLow;
  final bool systemApp;
  final bool hasInternetPermission;
}
