import Flutter
import Foundation
import NetworkExtension

private enum IOSVpnError: LocalizedError {
  case appGroupUnavailable
  case invalidArguments
  case tunnelNotConfigured
  case startTimedOut
  case simulatorUnsupported

  var errorDescription: String? {
    switch self {
    case .appGroupUnavailable:
      return "The iOS VPN App Group container is unavailable."
    case .invalidArguments:
      return "The iOS VPN request is missing required arguments."
    case .tunnelNotConfigured:
      return "The iOS Packet Tunnel is not configured."
    case .startTimedOut:
      return "The iOS VPN did not connect before the timeout."
    case .simulatorUnsupported:
      return "The iOS VPN data plane can only run on a physical device; iOS Simulator is not supported."
    }
  }
}

public final class ClashServicePlugin: NSObject, FlutterPlugin {
  private static let appGroupIdentifier = "group.com.aote.clashy"
  private static let providerBundleIdentifier = "com.aote.clashy.PacketTunnel"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "clash_service/ios",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(ClashServicePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "appGroupDirectory":
      guard let url = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
      ) else {
        result(FlutterError(
          code: "app_group_unavailable",
          message: IOSVpnError.appGroupUnavailable.localizedDescription,
          details: nil
        ))
        return
      }
      result(url.path)

    case "isConfigured":
      Task {
        do {
          let manager = try await Self.loadManager()
          Self.deliver(result, value: manager?.isEnabled == true)
        } catch {
          Self.deliver(result, error: error)
        }
      }

    case "isActive":
      Task {
        do {
          Self.deliver(result, value: try await Self.isActive())
        } catch {
          Self.deliver(result, error: error)
        }
      }

    case "start":
      guard let arguments = call.arguments as? [String: Any],
            let configDirectory = arguments["configDir"] as? String,
            !configDirectory.isEmpty else {
        result(FlutterError(
          code: "invalid_arguments",
          message: IOSVpnError.invalidArguments.localizedDescription,
          details: nil
        ))
        return
      }
      Task {
        do {
          let connected = try await Self.start(configDirectory: configDirectory)
          Self.deliver(result, value: connected)
        } catch {
          Self.deliver(result, error: error)
        }
      }

    case "updateProfile":
      guard let arguments = call.arguments as? [String: Any],
            let configDirectory = arguments["configDir"] as? String,
            !configDirectory.isEmpty else {
        result(FlutterError(
          code: "invalid_arguments",
          message: IOSVpnError.invalidArguments.localizedDescription,
          details: nil
        ))
        return
      }
      Task {
        do {
          let updated = try await Self.updateProfile(configDirectory: configDirectory)
          Self.deliver(result, value: updated)
        } catch {
          Self.deliver(result, error: error)
        }
      }

    case "refreshProfile":
      guard let arguments = call.arguments as? [String: Any],
            let configDirectory = arguments["configDir"] as? String,
            let url = arguments["url"] as? String,
            !configDirectory.isEmpty,
            !url.isEmpty else {
        result(FlutterError(
          code: "invalid_arguments",
          message: IOSVpnError.invalidArguments.localizedDescription,
          details: nil
        ))
        return
      }
      let script = arguments["script"] as? String ?? ""
      let interval = arguments["interval"] as? Int ?? 0
      Task {
        do {
          let refreshed = try await Self.refreshProfile(
            configDirectory: configDirectory,
            url: url,
            script: script,
            intervalMinutes: interval
          )
          Self.deliver(result, value: refreshed)
        } catch {
          Self.deliver(result, error: error)
        }
      }

    case "stop":
      Task {
        do {
          Self.deliver(result, value: try await Self.stop())
        } catch {
          Self.deliver(result, error: error)
        }
      }

    case "uninstall":
      Task {
        do {
          Self.deliver(result, value: try await Self.uninstall())
        } catch {
          Self.deliver(result, error: error)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func deliver(
    _ result: @escaping FlutterResult,
    value: Any
  ) {
    DispatchQueue.main.async {
      result(value)
    }
  }

  private static func deliver(
    _ result: @escaping FlutterResult,
    error: Error
  ) {
    DispatchQueue.main.async {
      result(FlutterError(
        code: "ios_vpn_error",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private static func loadManager() async throws -> NETunnelProviderManager? {
    let managers = try await NETunnelProviderManager.loadAllFromPreferences()
    return managers.first { manager in
      guard let tunnel = manager.protocolConfiguration as? NETunnelProviderProtocol else {
        return false
      }
      return tunnel.providerBundleIdentifier == providerBundleIdentifier
    }
  }

  private static func configuredManager(
    configDirectory: String? = nil
  ) async throws -> NETunnelProviderManager {
    let manager = try await loadManager() ?? NETunnelProviderManager()
    let tunnel = (manager.protocolConfiguration as? NETunnelProviderProtocol)
      ?? NETunnelProviderProtocol()
    tunnel.providerBundleIdentifier = providerBundleIdentifier
    tunnel.serverAddress = "Clashy"
    if let configDirectory {
      tunnel.providerConfiguration = ["configDir": configDirectory]
    }
    manager.protocolConfiguration = tunnel
    manager.localizedDescription = "Clashy"
    manager.isEnabled = true
    return manager
  }

  /// Keeps the tunnel alive across reboots and system terminations. On-demand
  /// is only ever switched on here, from an explicit user start, so that
  /// turning the VPN off really stops it until the user turns it on again.
  private static func enableOnDemand(_ manager: NETunnelProviderManager) {
    manager.isOnDemandEnabled = true
    manager.onDemandRules = [NEOnDemandRuleConnect()]
  }

  /// Whether the Packet Tunnel is currently connected. `isConfigured` only says
  /// the configuration exists, so a core that is running while the tunnel is
  /// down must not be reported as an active VPN.
  private static func isActive() async throws -> Bool {
    guard let manager = try await loadManager(), manager.isEnabled else {
      return false
    }
    switch manager.connection.status {
    case .connected, .reasserting:
      return true
    default:
      return false
    }
  }

  private static func start(configDirectory: String) async throws -> Bool {
    #if targetEnvironment(simulator)
    throw IOSVpnError.simulatorUnsupported
    #else
    let manager = try await configuredManager(configDirectory: configDirectory)
    enableOnDemand(manager)
    try await manager.saveToPreferences()
    try await manager.loadFromPreferences()
    try manager.connection.startVPNTunnel()

    for _ in 0..<120 {
      switch manager.connection.status {
      case .connected:
        return true
      case .invalid:
        throw IOSVpnError.tunnelNotConfigured
      default:
        try await Task.sleep(nanoseconds: 500_000_000)
      }
    }
    manager.connection.stopVPNTunnel()
    throw IOSVpnError.startTimedOut
    #endif
  }

  private static func updateProfile(configDirectory: String) async throws -> Bool {
    guard let manager = try await loadManager(),
          manager.isEnabled,
          let session = manager.connection as? NETunnelProviderSession else {
      return false
    }

    let tunnel = (manager.protocolConfiguration as? NETunnelProviderProtocol)
      ?? NETunnelProviderProtocol()
    tunnel.providerConfiguration = ["configDir": configDirectory]
    manager.protocolConfiguration = tunnel
    try await manager.saveToPreferences()

    let message = try JSONSerialization.data(
      withJSONObject: ["action": "reload"]
    )
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
      do {
        try session.sendProviderMessage(message) { response in
          guard let response,
                let result = try? JSONSerialization.jsonObject(with: response) as? [String: Bool] else {
            continuation.resume(returning: false)
            return
          }
          continuation.resume(returning: result["success"] == true)
        }
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  /// Asks the running tunnel to download the subscription and rewrite
  /// config.yaml itself, so a refresh can happen while the app is suspended.
  /// The download, the profile script and the app-owned key overlay all run in
  /// the Go core, the same code the desktop daemon uses.
  private static func refreshProfile(
    configDirectory: String,
    url: String,
    script: String,
    intervalMinutes: Int
  ) async throws -> Bool {
    guard let manager = try await loadManager(),
          manager.isEnabled,
          let session = manager.connection as? NETunnelProviderSession else {
      return false
    }

    var payload: [String: String] = [
      "action": "refresh",
      "url": url,
      "interval": String(intervalMinutes),
    ]
    if !script.isEmpty {
      payload["script"] = script
    }
    let message = try JSONSerialization.data(withJSONObject: payload)

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
      do {
        try session.sendProviderMessage(message) { response in
          guard let response,
                let result = try? JSONSerialization.jsonObject(with: response) as? [String: Bool] else {
            continuation.resume(returning: false)
            return
          }
          continuation.resume(returning: result["success"] == true)
        }
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  private static func stop() async throws -> Bool {
    guard let manager = try await loadManager() else {
      return true
    }

    // On-demand rules would bring the tunnel straight back, so they have to be
    // cleared before the connection is stopped.
    if manager.isOnDemandEnabled {
      manager.isOnDemandEnabled = false
      manager.onDemandRules = []
      try await manager.saveToPreferences()
    }

    manager.connection.stopVPNTunnel()

    for _ in 0..<40 {
      if manager.connection.status == .disconnected ||
         manager.connection.status == .invalid {
        return true
      }
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    return false
  }

  private static func uninstall() async throws -> Bool {
    guard let manager = try await loadManager() else {
      removeSharedConfiguration()
      return true
    }
    manager.connection.stopVPNTunnel()

    // removeFromPreferences fails while the tunnel is still tearing down, so
    // wait for the connection to leave the transient states first.
    for _ in 0..<40 {
      if manager.connection.status == .disconnected ||
         manager.connection.status == .invalid {
        break
      }
      try await Task.sleep(nanoseconds: 250_000_000)
    }

    try await manager.removeFromPreferences()
    removeSharedConfiguration()
    return true
  }

  /// Drops the App Group copy of the profile so a reinstall cannot pick up a
  /// configuration left behind by the previous installation.
  private static func removeSharedConfiguration() {
    guard let groupURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return
    }
    let configuration = groupURL.appendingPathComponent(
      "clash_config",
      isDirectory: true
    )
    try? FileManager.default.removeItem(at: configuration)
  }
}
