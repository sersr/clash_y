/// Basic information for an application visible to Android's PackageManager.
class InstalledApplication {
  const InstalledApplication({
    required this.appName,
    required this.packageName,
    required this.systemApp,
    required this.hasInternetPermission,
  });

  final String appName;
  final String packageName;
  final bool systemApp;
  final bool hasInternetPermission;
}
