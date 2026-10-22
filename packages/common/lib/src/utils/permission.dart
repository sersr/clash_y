import 'package:permission_handler/permission_handler.dart';

class PermissionChecker {
  static Future<bool> requestAll() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.camera,
      Permission.microphone
    ].request();

    return !statuses.values.any((element) => !element.isGranted);
  }

  static Future<bool> requireCamera() {
    return _request(Permission.camera);
  }

  static Future<bool> requireIDFA() {
    return _request(Permission.appTrackingTransparency);
  }

  static Future<bool> requireStorage() {
    return _request(Permission.storage);
  }

  static Future<bool> requireLocation() {
    return _request(Permission.location);
  }

  static Future<bool> openSettings() {
    return openAppSettings();
  }

  static Future<bool> requireNotification() {
    return _request(Permission.notification);
  }

  static Future<bool> requireContacts() {
    return _request(Permission.contacts);
  }

  static Future<bool> _request(Permission permission) async {
    final isGranted = await permission.isGranted;
    if (!isGranted) {
      final status = await permission.request();
      return status == PermissionStatus.granted;
    }
    return true;
  }
}
