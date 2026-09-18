import Cocoa
import FlutterMacOS
import ServiceManagement


private let mihomoHelperPlistName =
  "com.aote.clashy.helper.plist"

public class VpnServicePlugin: NSObject, FlutterPlugin {

    private let mihomoClient = MihomoXPCClient()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "vpn_service", binaryMessenger: registrar.messenger)
    let instance = VpnServicePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "installHelper":
      install(result)
    case "start":
      start(call, result)
    case "stop":
      stop(call, result)
    case "unregister":
      unregister(result)
    case "satus":
      getStatus(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func install(_ result: @escaping FlutterResult) {
    let service = SMAppService.daemon(plistName: mihomoHelperPlistName)
    do {
      try service.register()
      result([
        "status": service.status.rawValue,
        "error": "",
      ])
    } catch {
      // result(
      //   FlutterError(
      //     code: "REGISTER_FAILED",
      //     message:
      //       error.localizedDescription,
      //     details: nil
      //   )
      // )
      result([
        "status": service.status.rawValue,
        "error": error.localizedDescription,
      ])
    }
  }

  func unregister(_ result: @escaping FlutterResult) {
    let service = SMAppService.daemon(plistName: mihomoHelperPlistName)
    do {
      try service.unregister()
      result([
        "status": service.status.rawValue,
        "error": "",
      ])
    } catch {
      result([
        "status": service.status.rawValue,
        "error": error.localizedDescription,
      ])
    }
  }

  func start(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let configDir = args["configDir"] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT",
          message: nil,
          details: nil
        )
      )

      return
    }

    self.mihomoClient.start(configDir: configDir) { res in
      DispatchQueue.main.async {
        result(res)
      }
    }
  }

  func stop(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    self.mihomoClient.stop { res in
      DispatchQueue.main.async {
        result(res)
      }
    }
  }

  func getStatus(_ result: @escaping FlutterResult) {
    self.mihomoClient.status { res in
      DispatchQueue.main.async {
        result(res)
      }
    }
  }

}
