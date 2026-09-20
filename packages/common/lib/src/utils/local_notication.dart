import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void requestNotification() async {
  final initializationSettingsAndroid = const AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );

  final initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

 await  FlutterLocalNotificationsPlugin().initialize(
    settings: initializationSettings,
  );

  FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
}
