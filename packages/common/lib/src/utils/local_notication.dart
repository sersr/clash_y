import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void requestNotification() async {
  final initializationSettingsAndroid = const AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );

  final DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

  final initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    macOS: initializationSettingsDarwin,
    windows: .new(
      appName: "Clashy",
      appUserModelId: 'com.aote.clashy',
      guid: '122c1b20-ea61-4695-87f1-79b206d91ff5',
    ),
  );

  await FlutterLocalNotificationsPlugin().initialize(
    settings: initializationSettings,
  );

  FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
}
