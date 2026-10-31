import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        #if DEBUG
            return false
        #else
            return true
        #endif
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }



  var engine: FlutterEngine?
  var appChannel: FlutterMethodChannel?
  private var terminationRequested = false

  /// 退出前先通知 Dart 摘掉原生窗口事件监听，再关闭窗口。
  ///
  /// nativeapi 的窗口事件会在 `terminate:` 关闭窗口时回调 Dart，此时引擎
  /// 已在销毁，回调会访问失效状态并以 SIGSEGV 崩溃。
  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    if terminationRequested {
      return .terminateNow
    }
    terminationRequested = true

    appChannel?.invokeMethod("willTerminate", arguments: nil)
    // 取消本次退出，等 Dart 摘掉监听后再发起一次真正的退出。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      NSApp.terminate(nil)
    }
    return .terminateCancel
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    engine = FlutterEngine(name: "project", project: nil)
    RegisterGeneratedPlugins(registry: engine!)
    registerAppChannel()
    engine?.run(withEntrypoint:nil)
  }

  /// 应用级通道。
  ///
  /// 退出必须由原生侧发起：在 Dart 回调里直接调用 `NSApp.terminate` 会在
  /// 同一个调用栈里销毁引擎，触发 Dart_EnterIsolate 断言（SIGABRT）。
  private func registerAppChannel() {
    guard let engine else { return }
    let channel = FlutterMethodChannel(
      name: "clashy/app",
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "quit":
        result(nil)
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    appChannel = channel
  }

}
