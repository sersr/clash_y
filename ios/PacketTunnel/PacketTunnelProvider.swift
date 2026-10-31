import Darwin
import Foundation
import NetworkExtension

private enum PacketTunnelError: LocalizedError {
  case invalidConfiguration
  case socketPairFailed(Int32)
  case core(String)
  case invalidPacketFlow
  case simulatorUnsupported

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      return "The Packet Tunnel configuration is missing or outside the App Group."
    case .socketPairFailed(let code):
      return "Could not create the packet bridge (errno \(code))."
    case .core(let message):
      return "Could not start mihomo: \(message)"
    case .invalidPacketFlow:
      return "The Packet Tunnel packet flow is unavailable."
    case .simulatorUnsupported:
      return "The iOS VPN data plane can only run on a physical device."
    }
  }
}

@objc(PacketTunnelProvider)
final class PacketTunnelProvider: NEPacketTunnelProvider {
  private static let appGroupIdentifier = "group.com.aote.clashy"
  private let packetQueue = DispatchQueue(
    label: "clashy.packet-tunnel.io",
    qos: .userInitiated
  )
  private let stateLock = NSLock()

  private var active = false
  private var coreStarted = false
  private var packetPeerDescriptor: Int32 = -1
  private var packetReadSource: DispatchSourceRead?
  private var configDirectory: String?

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    do {
      let configDirectory = try validatedConfigDirectory()
      self.configDirectory = configDirectory
      try FileManager.default.createDirectory(
        atPath: configDirectory,
        withIntermediateDirectories: true
      )

      let settings = makeNetworkSettings()
      setTunnelNetworkSettings(settings) { [weak self] error in
        guard let self else {
          completionHandler(PacketTunnelError.invalidPacketFlow)
          return
        }
        if let error {
          completionHandler(error)
          return
        }

        self.packetQueue.async {
          do {
            try self.startCore(configDirectory: configDirectory)
            self.startPacketFlowPump()
            completionHandler(nil)
          } catch {
            self.stopCore()
            completionHandler(error)
          }
        }
      }
    } catch {
      completionHandler(error)
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    packetQueue.async {
      self.stopCore()
      completionHandler()
    }
  }

  override func handleAppMessage(
    _ messageData: Data,
    completionHandler: ((Data?) -> Void)? = nil
  ) {
    guard let message = try? JSONSerialization.jsonObject(with: messageData) as? [String: String],
          message["action"] == "reload",
          let configDirectory else {
      completionHandler?(Self.message(success: false))
      return
    }

    packetQueue.async {
      do {
        self.stopCore()
        try self.startCore(configDirectory: configDirectory)
        self.startPacketFlowPump()
        completionHandler?(Self.message(success: true))
      } catch {
        self.stopCore()
        NSLog("Clashy Packet Tunnel profile reload failed: %@", error.localizedDescription)
        completionHandler?(Self.message(success: false))
      }
    }
  }

  private func validatedConfigDirectory() throws -> String {
    guard let requestedPath = (protocolConfiguration as? NETunnelProviderProtocol)?
      .providerConfiguration?["configDir"] as? String,
      let groupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
      ) else {
      throw PacketTunnelError.invalidConfiguration
    }

    let expectedURL = groupURL
      .appendingPathComponent("clash_config", isDirectory: true)
      .standardizedFileURL
    let requestedURL = URL(fileURLWithPath: requestedPath).standardizedFileURL
    guard requestedURL.path == expectedURL.path,
          FileManager.default.fileExists(
            atPath: expectedURL.appendingPathComponent("config.yaml").path
          ) else {
      throw PacketTunnelError.invalidConfiguration
    }
    return expectedURL.path
  }

  private func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "172.19.0.2")
    let ipv4 = NEIPv4Settings(
      addresses: ["172.19.0.1"],
      subnetMasks: ["255.255.255.252"]
    )
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4

    let ipv6 = NEIPv6Settings(
      addresses: ["fdfe:dcba:9876::1"],
      networkPrefixLengths: [126]
    )
    ipv6.includedRoutes = [NEIPv6Route.default()]
    settings.ipv6Settings = ipv6
    settings.dnsSettings = NEDNSSettings(servers: ["172.19.0.2"])
    settings.mtu = NSNumber(value: 1500)
    return settings
  }

  private func startCore(configDirectory: String) throws {
    #if targetEnvironment(simulator)
    throw PacketTunnelError.simulatorUnsupported
    #else
    var descriptors: [Int32] = [0, 0]
    let result = descriptors.withUnsafeMutableBufferPointer { buffer in
      socketpair(AF_UNIX, SOCK_DGRAM, 0, buffer.baseAddress!)
    }
    guard result == 0 else {
      throw PacketTunnelError.socketPairFailed(errno)
    }

    var sendBufferSize: Int32 = 1 << 20
    _ = setsockopt(
      descriptors[1],
      SOL_SOCKET,
      SO_SNDBUF,
      &sendBufferSize,
      socklen_t(MemoryLayout<Int32>.size)
    )
    _ = setsockopt(
      descriptors[1],
      SOL_SOCKET,
      SO_RCVBUF,
      &sendBufferSize,
      socklen_t(MemoryLayout<Int32>.size)
    )

    let errorPointer = configDirectory.withCString { path in
      startTun(UnsafeMutablePointer(mutating: path), descriptors[0])
    }
    if let errorPointer {
      let message = String(cString: errorPointer)
      freeString(errorPointer)
      close(descriptors[0])
      close(descriptors[1])
      throw PacketTunnelError.core(message)
    }

    let flags = fcntl(descriptors[1], F_GETFL)
    guard flags >= 0,
          fcntl(descriptors[1], F_SETFL, flags | O_NONBLOCK) >= 0 else {
      _ = stop()
      close(descriptors[1])
      throw PacketTunnelError.socketPairFailed(errno)
    }

    withStateLock {
      coreStarted = true
      packetPeerDescriptor = descriptors[1]
      active = true
    }
    #endif
  }

  private func startPacketFlowPump() {
    let descriptor = withStateLock { packetPeerDescriptor }
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeReadSource(
      fileDescriptor: descriptor,
      queue: packetQueue
    )
    source.setEventHandler { [weak self] in
      self?.writePacketsToSystem(from: descriptor)
    }
    packetReadSource = source
    source.resume()
    readPacketsFromSystem()
  }

  private func readPacketsFromSystem() {
    guard withStateLock({ active }) else { return }
    packetFlow.readPackets { [weak self] packets, protocols in
      guard let self else { return }
      self.packetQueue.async {
        guard self.withStateLock({ self.active }) else { return }
        let descriptor = self.withStateLock { self.packetPeerDescriptor }
        guard descriptor >= 0 else { return }

        for (index, packet) in packets.enumerated() where index < protocols.count {
          let family = protocols[index].int32Value
          guard family == AF_INET || family == AF_INET6 else { continue }
          var frame = Data([0, 0, 0, UInt8(truncatingIfNeeded: family)])
          frame.append(packet)
          let sent = frame.withUnsafeBytes { bytes in
            send(descriptor, bytes.baseAddress, bytes.count, 0)
          }
          if sent != frame.count {
            NSLog("Clashy Packet Tunnel packet bridge write failed: errno %d", errno)
          }
        }
        self.readPacketsFromSystem()
      }
    }
  }

  private func writePacketsToSystem(from descriptor: Int32) {
    var frame = [UInt8](repeating: 0, count: 65_540)
    while withStateLock({ active }) {
      let count = frame.withUnsafeMutableBytes { bytes in
        recv(descriptor, bytes.baseAddress, bytes.count, 0)
      }
      if count < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK {
          return
        }
        NSLog("Clashy Packet Tunnel packet bridge read failed: errno %d", errno)
        return
      }
      guard count > 4 else { continue }

      let family = Int32(frame[3])
      guard family == AF_INET || family == AF_INET6 else { continue }
      let packet = Data(frame[4..<count])
      if !packetFlow.writePackets(
        [packet],
        withProtocols: [NSNumber(value: family)]
      ) {
        NSLog("Clashy Packet Tunnel could not write a packet to the system flow")
      }
    }
  }

  private func stopCore() {
    withStateLock {
      active = false
    }
    packetReadSource?.cancel()
    packetReadSource = nil

    let (wasStarted, peerDescriptor) = withStateLock {
      let wasStarted = coreStarted
      let peerDescriptor = packetPeerDescriptor
      coreStarted = false
      packetPeerDescriptor = -1
      return (wasStarted, peerDescriptor)
    }

    #if !targetEnvironment(simulator)
    if wasStarted, let errorPointer = stop() {
      NSLog(
        "Clashy Packet Tunnel core shutdown failed: %@",
        String(cString: errorPointer)
      )
      freeString(errorPointer)
    }
    #endif
    if peerDescriptor >= 0 {
      close(peerDescriptor)
    }
  }

  private func withStateLock<T>(_ body: () -> T) -> T {
    stateLock.lock()
    defer { stateLock.unlock() }
    return body()
  }

  private static func message(success: Bool) -> Data? {
    try? JSONSerialization.data(withJSONObject: ["success": success])
  }
}
