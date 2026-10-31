import 'package:common/multi_window.dart' as mw;

/// 主窗口的运行时状态，由 main.dart 在创建窗口时写入。
abstract final class AppWindow {
  /// nativeapi 窗口事件监听 id。
  static mw.ListenerId? listenerId;

  /// 退出前移除原生窗口事件监听。
  ///
  /// nativeapi 会在窗口关闭时把事件回调进 Dart；此时引擎已在销毁，
  /// 回调会访问失效的 isolate，导致退出时 SIGSEGV。
  static void detachListeners() {
    final id = listenerId;
    listenerId = null;
    if (id != null) mw.WindowManager.instance.removeListener(id);
  }
}
