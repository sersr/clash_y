import 'package:jni/jni.dart';

/// Hand-written JNI bindings for the Android framework members this plugin
/// needs.
///
/// The surface is intentionally tiny: only the members used by
/// `AndroidVpnService` are resolved, and every handle is created lazily the
/// first time it is touched, so importing this library on a platform without a
/// JVM does nothing.
///
/// JNIgen is not used here because the plugin exposes no Java/Kotlin class to
/// bind: `ClashVpnService` is reached through an [android.content.Intent]
/// rather than through JNI, and the framework classes below are stable,
/// well-documented Android APIs.
abstract final class AndroidApi {
  // ---------------------------------------------------------------------------
  // Classes.
  // ---------------------------------------------------------------------------

  static final JClass contextClass = JClass.forName('android/content/Context');
  static final JClass intentClass = JClass.forName('android/content/Intent');
  static final JClass activityClass = JClass.forName('android/app/Activity');
  static final JClass vpnServiceClass = JClass.forName('android/net/VpnService');
  static final JClass arrayListClass = JClass.forName('java/util/ArrayList');
  static final JClass buildVersionClass = JClass.forName(
    r'android/os/Build$VERSION',
  );

  /// The component this plugin starts and stops.
  ///
  /// Resolving it eagerly turns a renamed or missing service into an immediate,
  /// readable failure instead of a silently ignored [android.content.Intent].
  static final JClass vpnServiceComponentClass = JClass.forName(
    'io/aote/vpnService/ClashVpnService',
  );

  // ---------------------------------------------------------------------------
  // android.net.VpnService.
  // ---------------------------------------------------------------------------

  /// `VpnService.prepare(Context)`.
  ///
  /// Returns `null` when the app already holds the user's consent, and the
  /// consent [android.content.Intent] otherwise.
  static final JStaticMethodId vpnServicePrepare = vpnServiceClass.staticMethodId(
    'prepare',
    '(Landroid/content/Context;)Landroid/content/Intent;',
  );

  // ---------------------------------------------------------------------------
  // android.content.Intent.
  // ---------------------------------------------------------------------------

  /// `Intent(Context, Class)`.
  static final JConstructorId intentNew = intentClass.constructorId(
    '(Landroid/content/Context;Ljava/lang/Class;)V',
  );

  static final JInstanceMethodId intentSetAction = intentClass.instanceMethodId(
    'setAction',
    '(Ljava/lang/String;)Landroid/content/Intent;',
  );

  static final JInstanceMethodId intentPutExtraString = intentClass
      .instanceMethodId(
        'putExtra',
        '(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;',
      );

  static final JInstanceMethodId intentPutStringArrayListExtra = intentClass
      .instanceMethodId(
        'putStringArrayListExtra',
        '(Ljava/lang/String;Ljava/util/ArrayList;)Landroid/content/Intent;',
      );

  // ---------------------------------------------------------------------------
  // android.app.Activity.
  // ---------------------------------------------------------------------------

  /// `Activity.startActivityForResult(Intent, int)`.
  ///
  /// The system VPN consent dialog reads the launching package through
  /// `Activity.getCallingPackage()`, which Android only populates when the
  /// caller passed a request code. Launching the dialog with plain
  /// `Context.startActivity`, or from the application context, leaves that
  /// package `null`, and the dialog then finishes on the spot without showing
  /// anything or recording consent.
  static final JInstanceMethodId activityStartActivityForResult = activityClass
      .instanceMethodId(
        'startActivityForResult',
        '(Landroid/content/Intent;I)V',
      );

  static final JInstanceMethodId contextStartService = contextClass
      .instanceMethodId(
        'startService',
        '(Landroid/content/Intent;)Landroid/content/ComponentName;',
      );

  static final JInstanceMethodId contextStartForegroundService = contextClass
      .instanceMethodId(
        'startForegroundService',
        '(Landroid/content/Intent;)Landroid/content/ComponentName;',
      );

  static final JInstanceMethodId contextStopService = contextClass
      .instanceMethodId('stopService', '(Landroid/content/Intent;)Z');

  // ---------------------------------------------------------------------------
  // java.util.ArrayList.
  // ---------------------------------------------------------------------------

  /// `ArrayList(int)` — sized up front because the lists are written once.
  static final JConstructorId arrayListNew = arrayListClass.constructorId('(I)V');

  static final JInstanceMethodId arrayListAdd = arrayListClass.instanceMethodId(
    'add',
    '(Ljava/lang/Object;)Z',
  );

  // ---------------------------------------------------------------------------
  // android.os.Build.VERSION.
  // ---------------------------------------------------------------------------

  static final JStaticFieldId buildVersionSdkInt = buildVersionClass
      .staticFieldId('SDK_INT', 'I');

  /// `Build.VERSION.SDK_INT`.
  static int get sdkInt =>
      buildVersionSdkInt.get<jint, int>(buildVersionClass, jint.type);
}
