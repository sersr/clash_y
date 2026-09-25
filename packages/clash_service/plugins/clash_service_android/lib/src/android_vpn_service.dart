import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';

import 'android_api.dart';

/// Drives `io.aote.vpnService.ClashVpnService` from Dart.
///
/// The whole flow runs through `package:jni`, with the application
/// [android.content.Context] and the current `Activity` taken from
/// `package:jni_flutter`:
///
/// 1. read the application context,
/// 2. make sure the user granted the VPN consent (`VpnService.prepare`),
/// 3. ask `ClashVpnService` to bring mihomo up by starting it as a foreground
///    service with the configuration directory attached.
///
/// No method channel and no Java/Kotlin bridge class is involved; the only
/// Kotlin left in the plugin is the service itself and the native `ClashCore`
/// binding it owns.
///
/// Every failure is reported through [debugPrint] with the
/// `clash_service_android` tag, so `flutter run` and logcat show which step
/// failed instead of the call quietly returning `false`.
abstract final class AndroidVpnService {
  /// How often the VPN consent dialog is re-checked.
  static const Duration permissionPollInterval = Duration(milliseconds: 500);

  /// How long to wait for the user to accept the VPN consent dialog.
  static const Duration permissionTimeout = Duration(seconds: 60);

  /// `Build.VERSION_CODES.O`, the first release with
  /// `Context.startForegroundService`.
  static const int _androidO = 26;

  /// Request code for the system VPN consent dialog.
  ///
  /// `com.android.vpndialogs.ConfirmDialog` only learns which package to
  /// authorize from a result request, so this must be passed to
  /// `Activity.startActivityForResult`.
  static const int _consentRequestCode = 0x5650;

  /// Whether the plugin can run on the current platform.
  static bool get isSupported => Platform.isAndroid;

  /// Starts the VPN service for [configDir].
  ///
  /// Returns `false` when the platform is not Android, when [configDir] is
  /// empty, when the user rejects (or never answers) the VPN consent dialog, or
  /// when the foreground service could not be started.
  ///
  /// A `true` result means "the service was asked to start", not "mihomo is
  /// up": the service loads the configuration asynchronously, so callers that
  /// need mihomo itself should poll its API. This matches `ClashVpnService`,
  /// which deliberately keeps no runtime status object.
  static Future<bool> start(
    String configDir, {
    List<String> allowedApplications = const <String>[],
    List<String> disallowedApplications = const <String>[],
  }) async {
    if (!isSupported) {
      _log('Not running on Android');
      return false;
    }

    final directory = configDir.trim();
    if (directory.isEmpty) {
      _log('Refusing to start: the configuration directory is empty');
      return false;
    }

    final context = _applicationContext();
    if (context == null) {
      return false;
    }

    try {
      if (!await _ensureVpnConsent(context)) {
        return false;
      }

      final intent = _serviceIntent(context, _Contract.actionStart);
      try {
        _putString(intent, _Contract.extraConfigDir, directory);
        _putStringList(
          intent,
          _Contract.extraAllowedApplications,
          allowedApplications,
        );
        _putStringList(
          intent,
          _Contract.extraDisallowedApplications,
          disallowedApplications,
        );
        _startService(context, intent);
      } finally {
        intent.release();
      }

      _log('Asked ClashVpnService to start with configDir=$directory');
      return true;
    } catch (error, stackTrace) {
      _log('Failed to start the VPN service', error, stackTrace);
      return false;
    } finally {
      context.release();
    }
  }

  /// Stops the VPN service and releases the TUN device it owns.
  ///
  /// The service is asked to stop and then stopped outright, so a service that
  /// is already gone (or that never finished starting) is still torn down.
  static Future<bool> close() async {
    if (!isSupported) {
      _log('Not running on Android');
      return false;
    }

    final context = _applicationContext();
    if (context == null) {
      return false;
    }

    try {
      final intent = _serviceIntent(context, _Contract.actionStop);
      try {
        try {
          _startService(context, intent);
        } catch (error, stackTrace) {
          // The service may already be gone; stopService below still applies.
          _log('Failed to signal the VPN service to stop', error, stackTrace);
        }
        final stopped = AndroidApi.contextStopService.call<jboolean, bool>(
          context,
          jboolean.type,
          [intent],
        );
        _log('stopService returned $stopped');
      } finally {
        intent.release();
      }
      return true;
    } catch (error, stackTrace) {
      _log('Failed to stop the VPN service', error, stackTrace);
      return false;
    } finally {
      context.release();
    }
  }

  /// Whether the user already granted this app the VPN consent.
  ///
  /// Diagnostics helper: call it before [start] to tell "the consent dialog
  /// never appeared" apart from "the dialog appeared but was not accepted".
  static bool hasVpnConsent() {
    if (!isSupported) {
      return false;
    }

    final context = _applicationContext();
    if (context == null) {
      return false;
    }

    try {
      return _hasVpnConsent(context);
    } catch (error, stackTrace) {
      _log('Failed to read the VPN consent state', error, stackTrace);
      return false;
    } finally {
      context.release();
    }
  }

  // ---------------------------------------------------------------------------
  // Context and activity.
  // ---------------------------------------------------------------------------

  /// The long-lived application context, or `null` when `jni_flutter` is not
  /// attached to this engine.
  static JObject? _applicationContext() {
    try {
      return androidApplicationContext;
    } catch (error, stackTrace) {
      _log(
        'No Android application context: is jni_flutter registered?',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// The current `Activity`, or `null` when it is unavailable.
  ///
  /// `jni_flutter` hands out a volatile reference that is only valid on the
  /// platform thread and must be used synchronously, which is exactly how it is
  /// used here.
  static JObject? _currentActivity() {
    final engineId = PlatformDispatcher.instance.engineId;
    if (engineId == null) {
      _log('PlatformDispatcher has no engineId, so no activity is available');
      return null;
    }

    try {
      return androidActivity(engineId);
    } catch (error, stackTrace) {
      _log('No Android activity for engine $engineId', error, stackTrace);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // VPN consent.
  // ---------------------------------------------------------------------------

  /// Makes sure the app holds the VPN consent, showing the system dialog when
  /// it does not.
  static Future<bool> _ensureVpnConsent(JObject context) async {
    if (_hasVpnConsent(context)) {
      _log('VPN consent already granted');
      return true;
    }

    if (!_openConsentDialog(context, _consentRequestCode)) {
      _log(
        'Could not open the VPN consent dialog, so there is nothing to wait '
        'for; aborting instead of polling for a dialog that is not on screen',
      );
      return false;
    }

    _log(
      'Waiting up to ${permissionTimeout.inSeconds}s for the consent dialog to '
      'be answered',
    );
    if (await _waitForVpnConsent(context)) {
      return true;
    }

    _log(
      'The VPN consent dialog was not accepted within '
      '${permissionTimeout.inSeconds}s',
    );
    return false;
  }

  /// Whether the app already holds the VPN consent.
  static bool _hasVpnConsent(JObject context) {
    final intent = _prepareIntent(context);
    if (intent == null) {
      return true;
    }

    intent.release();
    return false;
  }

  /// Opens the system VPN consent dialog.
  ///
  /// Returns `true` when the dialog was handed to the system, or when consent
  /// turned out to be granted already.
  ///
  /// The dialog **must** be started from an activity with a result request.
  /// `com.android.vpndialogs.ConfirmDialog` identifies the app to authorize
  /// through `Activity.getCallingPackage()`, which Android only populates when
  /// the caller passed a request code. Starting it with plain `startActivity`
  /// — or from the application context — leaves that package `null`, and the
  /// dialog then finishes on the spot without showing anything or recording
  /// consent.
  static bool _openConsentDialog(JObject context, int requestCode) {
    JObject? intent;
    try {
      intent = _prepareIntent(context);
      if (intent == null) {
        // Consent was granted between the check and here.
        return true;
      }

      final activity = _currentActivity();
      if (activity == null) {
        _log(
          'No activity available, so the VPN consent dialog cannot be started. '
          'It needs an activity to launch from, otherwise Android cannot tell '
          'the system dialog which package to authorize',
        );
        return false;
      }

      try {
        AndroidApi.activityStartActivityForResult.call<jvoid, void>(
          activity,
          jvoid.type,
          [intent, JValueInt(requestCode)],
        );
        _log('Opened the VPN consent dialog from the current activity');
        return true;
      } finally {
        activity.release();
      }
    } catch (error, stackTrace) {
      _log('Failed to open the VPN consent dialog', error, stackTrace);
      return false;
    } finally {
      intent?.release();
    }
  }

  /// Polls until the consent dialog is answered, or until [permissionTimeout].
  ///
  /// The dialog records the consent system-side, so once the user accepts,
  /// `VpnService.prepare` starts returning `null` even though this plugin never
  /// sees an activity result.
  static Future<bool> _waitForVpnConsent(JObject context) async {
    final deadline = DateTime.now().add(permissionTimeout);
    var polls = 0;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(permissionPollInterval);
      polls++;
      if (_hasVpnConsent(context)) {
        _log(
          'VPN consent granted after '
          '${polls * permissionPollInterval.inMilliseconds}ms',
        );
        return true;
      }
    }
    return false;
  }

  /// `VpnService.prepare(context)`, or `null` when consent is already granted.
  static JObject? _prepareIntent(JObject context) {
    return AndroidApi.vpnServicePrepare.callNullable<JObject, JObject>(
      AndroidApi.vpnServiceClass,
      JObject.type,
      [context],
    );
  }

  // ---------------------------------------------------------------------------
  // Service intents.
  // ---------------------------------------------------------------------------

  /// `Intent(context, ClashVpnService::class.java).setAction(action)`.
  static JObject _serviceIntent(JObject context, String action) {
    final intent = AndroidApi.intentNew.call<JObject>(AndroidApi.intentClass, [
      context,
      AndroidApi.vpnServiceComponentClass,
    ]);

    final jAction = action.toJString();
    try {
      AndroidApi.intentSetAction
          .callNullable<JObject, JObject>(intent, JObject.type, [jAction])
          ?.release();
    } finally {
      jAction.release();
    }
    return intent;
  }

  static void _putString(JObject intent, String name, String value) {
    final jName = name.toJString();
    final jValue = value.toJString();
    try {
      AndroidApi.intentPutExtraString
          .callNullable<JObject, JObject>(intent, JObject.type, [jName, jValue])
          ?.release();
    } finally {
      jName.release();
      jValue.release();
    }
  }

  static void _putStringList(
    JObject intent,
    String name,
    List<String> values,
  ) {
    final list = AndroidApi.arrayListNew.call<JObject>(
      AndroidApi.arrayListClass,
      [JValueInt(values.length)],
    );
    final jName = name.toJString();
    try {
      for (final value in values) {
        final jValue = value.toJString();
        try {
          AndroidApi.arrayListAdd.call<jboolean, bool>(list, jboolean.type, [
            jValue,
          ]);
        } finally {
          jValue.release();
        }
      }

      AndroidApi.intentPutStringArrayListExtra
          .callNullable<JObject, JObject>(intent, JObject.type, [jName, list])
          ?.release();
    } finally {
      jName.release();
      list.release();
    }
  }

  /// Starts [intent] as a foreground service, falling back to a plain service
  /// start on API levels below Android O.
  static void _startService(JObject context, JObject intent) {
    if (AndroidApi.sdkInt >= _androidO) {
      AndroidApi.contextStartForegroundService
          .callNullable<JObject, JObject>(context, JObject.type, [intent])
          ?.release();
    } else {
      AndroidApi.contextStartService
          .callNullable<JObject, JObject>(context, JObject.type, [intent])
          ?.release();
    }
  }

  static void _log(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[clash_service_android] $message');
    if (error != null) {
      debugPrint('[clash_service_android]   cause: $error');
    }
    if (stackTrace != null) {
      debugPrint('[clash_service_android] $stackTrace');
    }
  }
}

/// Intent contract shared with `ClashVpnService` and `VpnServiceContract.kt`.
///
/// Keep these values in sync with
/// `android/src/main/kotlin/io/aote/vpnService/VpnServiceContract.kt`.
abstract final class _Contract {
  static const String actionStart = 'io.aote.vpnService.action.START';
  static const String actionStop = 'io.aote.vpnService.action.STOP';
  static const String extraConfigDir = 'configDir';
  static const String extraAllowedApplications = 'allowedApplications';
  static const String extraDisallowedApplications = 'disallowedApplications';
}
