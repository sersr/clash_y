import Darwin
import Foundation
import Network
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

  /// Packets handed to `NEPacketTunnelFlow.writePackets` per call. One call
  /// per packet costs more than the bridging itself at high packet rates.
  private static let packetBatchSize = 32

  private var active = false
  private var coreStarted = false
  private var packetPeerDescriptor: Int32 = -1
  private var packetReadSource: DispatchSourceRead?
  private var configDirectory: String?
  private var pathMonitor: NWPathMonitor?

  // Subscription refresh schedule, persisted in the App Group so a restarted
  // tunnel resumes it without help from the app.
  private var refreshTimer: Timer?
  private var refreshURL: String?
  private var refreshScript = ""
  private var refreshIntervalMinutes = 0
  private var refreshDueDate: Date?

  private static let refreshStateName = "profile_refresh.json"

  // Reused across pump iterations: a per-packet array Allocation on every
  // read is measurable on the extension's small heap.
  private var receiveBuffer = [UInt8](repeating: 0, count: 65_536)
  private var sendBuffer = [UInt8](repeating: 0, count: 65_536)

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    let configDirectory: String
    do {
      configDirectory = try validatedConfigDirectory()
      self.configDirectory = configDirectory
      try FileManager.default.createDirectory(
        atPath: configDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      completionHandler(error)
      return
    }

    let settings = makeNetworkSettings()
    packetQueue.async { [weak self] in
      guard let self else {
        completionHandler(PacketTunnelError.invalidPacketFlow)
        return
      }

      // Fetch the GeoIP/GeoSite databases before the tunnel owns the default
      // route. mihomo loads them while parsing rules, and a download started
      // afterwards would be routed into a stack that is not running yet, so it
      // would only stall until it fails and take the whole start down.
      do {
        try self.prepareCore(configDirectory: configDirectory)
      } catch {
        completionHandler(error)
        return
      }

      self.setTunnelNetworkSettings(settings) { error in
        if let error {
          completionHandler(error)
          return
        }

        self.packetQueue.async {
          do {
            try self.startCore(configDirectory: configDirectory)
            self.startPacketFlowPump()
            self.startPathMonitor()
            self.resumeRefreshSchedule()
            completionHandler(nil)
          } catch {
            self.stopCore()
            completionHandler(error)
          }
        }
      }
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    packetQueue.async {
      self.stopPathMonitor()
      self.stopRefreshSchedule()
      self.stopCore()
      completionHandler()
    }
  }

  override func handleAppMessage(
    _ messageData: Data,
    completionHandler: ((Data?) -> Void)? = nil
  ) {
    guard let message = try? JSONSerialization.jsonObject(with: messageData) as? [String: String],
          let action = message["action"],
          let configDirectory else {
      completionHandler?(Self.message(success: false))
      return
    }

    switch action {
    case "reload":
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

    case "refresh":
      // The app hands over the profile it wants refreshed; the download, the
      // profile script and the app-owned key overlay all run inside the core so
      // a background refresh produces the same config the app would.
      guard let url = message["url"], !url.isEmpty else {
        completionHandler?(Self.message(success: false))
        return
      }
      let script = message["script"] ?? ""
      let interval = Int(message["interval"] ?? "") ?? 0
      packetQueue.async {
        do {
          try self.downloadAndApplyProfile(
            configDirectory: configDirectory,
            url: url,
            script: script
          )
          try self.restartForNewConfig(configDirectory: configDirectory)
          self.scheduleRefresh(
            configDirectory: configDirectory,
            url: url,
            script: script,
            intervalMinutes: interval,
            lastUpdate: Date()
          )
          completionHandler?(Self.message(success: true))
        } catch {
          NSLog(
            "Clashy Packet Tunnel profile refresh failed: %@",
            error.localizedDescription
          )
          // A failed download still counts as an attempt so the schedule keeps
          // moving instead of retrying in a tight loop.
          self.scheduleRefresh(
            configDirectory: configDirectory,
            url: url,
            script: script,
            intervalMinutes: interval,
            lastUpdate: Date()
          )
          completionHandler?(Self.message(success: false))
        }
      }

    default:
      completionHandler?(Self.message(success: false))
    }
  }

  /// Downloads the subscription and rewrites config.yaml through the core.
  private func downloadAndApplyProfile(
    configDirectory: String,
    url: String,
    script: String
  ) throws {
    let errorPointer = configDirectory.withCString { dir in
      url.withCString { profileURL in
        script.withCString { profileScript in
          refreshProfile(
            UnsafeMutablePointer(mutating: dir),
            UnsafeMutablePointer(mutating: profileURL),
            UnsafeMutablePointer(mutating: profileScript)
          )
        }
      }
    }
    if let errorPointer {
      let message = String(cString: errorPointer)
      freeString(errorPointer)
      throw PacketTunnelError.core(message)
    }
  }

  /// Restarts the core so it picks up the freshly written config. Falls back to
  /// the backup the core left behind when the new configuration is rejected,
  /// otherwise a bad subscription would leave the user with no VPN at all.
  private func restartForNewConfig(configDirectory: String) throws {
    stopCore()
    do {
      try startCore(configDirectory: configDirectory)
      startPacketFlowPump()
    } catch {
      NSLog("Clashy Packet Tunnel rejected the refreshed config: %@", error.localizedDescription)
      do {
        try restoreBackup(configDirectory: configDirectory)
        try startCore(configDirectory: configDirectory)
        startPacketFlowPump()
      } catch {
        NSLog(
          "Clashy Packet Tunnel could not fall back to the previous config: %@",
          error.localizedDescription
        )
      }
      throw error
    }
  }

  private func restoreBackup(configDirectory: String) throws {
    let manager = FileManager.default
    let configPath = (configDirectory as NSString).appendingPathComponent("config.yaml")
    let backupPath = configPath + ".bak"
    guard manager.fileExists(atPath: backupPath) else { return }
    defer { try? manager.removeItem(atPath: backupPath) }
    _ = try? manager.removeItem(atPath: configPath)
    try manager.moveItem(atPath: backupPath, toPath: configPath)
  }

  // MARK: - Subscription refresh schedule

  /// Records the refresh parameters and arms the timer.
  ///
  /// The schedule lives in the tunnel, not in the app: the extension keeps
  /// running while the app is suspended, which is exactly when a subscription
  /// needs to refresh. `lastUpdate` anchors the interval the same way the app
  /// does, so a restart resumes instead of downloading again immediately.
  private func scheduleRefresh(
    configDirectory: String,
    url: String,
    script: String,
    intervalMinutes: Int,
    lastUpdate: Date
  ) {
    refreshTimer?.invalidate()
    refreshTimer = nil

    refreshURL = url
    refreshScript = script
    refreshIntervalMinutes = intervalMinutes

    guard intervalMinutes > 0, !url.isEmpty else {
      refreshDueDate = nil
      persistRefreshState(configDirectory: configDirectory)
      return
    }

    let due = lastUpdate.addingTimeInterval(TimeInterval(intervalMinutes) * 60)
    refreshDueDate = due
    persistRefreshState(configDirectory: configDirectory)

    let delay = max(0, due.timeIntervalSinceNow)
    let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
      self?.packetQueue.async {
        self?.runScheduledRefresh(configDirectory: configDirectory)
      }
    }
    // The tunnel's run loop only services the main queue; a timer added to it
    // from packetQueue still fires there, which is what we want.
    RunLoop.main.add(timer, forMode: .common)
    refreshTimer = timer
  }

  private func runScheduledRefresh(configDirectory: String) {
    guard let url = refreshURL, !url.isEmpty else { return }
    guard withStateLock({ coreStarted }) else { return }

    do {
      try downloadAndApplyProfile(
        configDirectory: configDirectory,
        url: url,
        script: refreshScript
      )
      try restartForNewConfig(configDirectory: configDirectory)
      scheduleRefresh(
        configDirectory: configDirectory,
        url: url,
        script: refreshScript,
        intervalMinutes: refreshIntervalMinutes,
        lastUpdate: Date()
      )
    } catch {
      NSLog(
        "Clashy Packet Tunnel scheduled refresh failed: %@",
        error.localizedDescription
      )
      // Retry on the next interval rather than immediately, so an unreachable
      // provider does not turn into a download loop.
      scheduleRefresh(
        configDirectory: configDirectory,
        url: url,
        script: refreshScript,
        intervalMinutes: refreshIntervalMinutes,
        lastUpdate: Date()
      )
    }
  }

  /// Re-arms the schedule after a tunnel restart, using the persisted state.
  private func resumeRefreshSchedule() {
    guard let configDirectory else { return }
    guard let state = loadRefreshState(configDirectory: configDirectory) else {
      return
    }
    scheduleRefresh(
      configDirectory: configDirectory,
      url: state["url"] as? String ?? "",
      script: state["script"] as? String ?? "",
      intervalMinutes: state["interval"] as? Int ?? 0,
      lastUpdate: (state["lastUpdate"] as? Double).map {
        Date(timeIntervalSince1970: $0)
      } ?? Date()
    )
  }

  private func stopRefreshSchedule() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  private func persistRefreshState(configDirectory: String) {
    let payload: [String: Any] = [
      "url": refreshURL ?? "",
      "script": refreshScript,
      "interval": refreshIntervalMinutes,
      "lastUpdate": (refreshDueDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
        - TimeInterval(refreshIntervalMinutes) * 60,
    ]
    let path = (configDirectory as NSString)
      .appendingPathComponent(Self.refreshStateName)
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
      return
    }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  private func loadRefreshState(configDirectory: String) -> [String: Any]? {
    let path = (configDirectory as NSString)
      .appendingPathComponent(Self.refreshStateName)
    guard let data = FileManager.default.contents(atPath: path) else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
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

  /// Downloads the databases the profile's rules reference while the device
  /// still uses its own network. Mirrors what the Android service does before
  /// it establishes the VpnService interface.
  private func prepareCore(configDirectory: String) throws {
    #if targetEnvironment(simulator)
    throw PacketTunnelError.simulatorUnsupported
    #else
    let errorPointer = configDirectory.withCString { path in
      prepare(UnsafeMutablePointer(mutating: path))
    }
    if let errorPointer {
      let message = String(cString: errorPointer)
      freeString(errorPointer)
      throw PacketTunnelError.core(message)
    }
    #endif
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

    // Both directions need headroom: the provider writes to descriptors[1]
    // (upstream) and reads from it (downstream), so the peer end that the core
    // keeps also carries downstream traffic. Leaving descriptors[0] at the
    // default size drops packets with ENOBUFS under load.
    setSocketBuffers(descriptors[0])
    setSocketBuffers(descriptors[1])

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

  private func setSocketBuffers(_ descriptor: Int32) {
    var bufferSize: Int32 = 1 << 20
    _ = setsockopt(
      descriptor,
      SOL_SOCKET,
      SO_SNDBUF,
      &bufferSize,
      socklen_t(MemoryLayout<Int32>.size)
    )
    _ = setsockopt(
      descriptor,
      SOL_SOCKET,
      SO_RCVBUF,
      &bufferSize,
      socklen_t(MemoryLayout<Int32>.size)
    )
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
          // The descriptor keeps utun framing: a 4 byte address family header
          // followed by the IP packet, both in one datagram.
          guard packet.count <= self.sendBuffer.count - 4 else { continue }

          let length = packet.count + 4
          let sent = self.sendBuffer.withUnsafeMutableBytes { bytes -> Int in
            bytes[0] = 0
            bytes[1] = 0
            bytes[2] = 0
            bytes[3] = UInt8(truncatingIfNeeded: family)
            packet.copyBytes(
              to: bytes.baseAddress!.advanced(by: 4)
                .assumingMemoryBound(to: UInt8.self),
              count: packet.count
            )
            return send(descriptor, bytes.baseAddress, length, 0)
          }
          if sent != length {
            NSLog("Clashy Packet Tunnel packet bridge write failed: errno %d", errno)
          }
        }
        self.readPacketsFromSystem()
      }
    }
  }

  private func writePacketsToSystem(from descriptor: Int32) {
    // A datagram socket yields exactly one packet per recv, so packets are
    // accumulated until the socket runs dry (or the batch is full) and then
    // handed to the flow in a single call. One call per packet makes the
    // syscall overhead dominate under load.
    var packets = [Data]()
    var protocols = [NSNumber]()
    packets.reserveCapacity(Self.packetBatchSize)
    protocols.reserveCapacity(Self.packetBatchSize)

    while withStateLock({ active }) {
      let count = receiveBuffer.withUnsafeMutableBytes { bytes in
        recv(descriptor, bytes.baseAddress, bytes.count, 0)
      }
      if count < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK {
          break
        }
        NSLog("Clashy Packet Tunnel packet bridge read failed: errno %d", errno)
        break
      }
      // A datagram socket returns 0 once the peer descriptor is closed; without
      // this the loop would spin on the read source forever.
      if count == 0 {
        break
      }
      guard count > 4 else { continue }

      let family = Int32(receiveBuffer[3])
      guard family == AF_INET || family == AF_INET6 else { continue }

      packets.append(Data(receiveBuffer[4..<count]))
      protocols.append(NSNumber(value: family))

      if packets.count >= Self.packetBatchSize {
        break
      }
    }

    guard !packets.isEmpty else { return }
    if !packetFlow.writePackets(packets, withProtocols: protocols) {
      NSLog("Clashy Packet Tunnel could not write packets to the system flow")
    }
  }

  /// Watches the underlying network. The core resolves the default interface
  /// once at start, so a Wi-Fi/cellular switch would leave every outbound
  /// connection pinned to an interface that no longer carries traffic. The
  /// system also expects `reasserting` to be set while the tunnel repairs
  /// itself, otherwise the VPN looks up but passes nothing.
  private func startPathMonitor() {
    let monitor = NWPathMonitor()
    var reportedInitialPath = false
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      // NWPathMonitor reports the current path immediately on start; that one
      // is not a change and needs no repair.
      if !reportedInitialPath {
        reportedInitialPath = true
        return
      }
      guard path.status == .satisfied else { return }
      self.packetQueue.async {
        self.restartCoreForNetworkChange()
      }
    }
    monitor.start(queue: packetQueue)
    pathMonitor = monitor
  }

  private func stopPathMonitor() {
    pathMonitor?.cancel()
    pathMonitor = nil
  }

  private func restartCoreForNetworkChange() {
    guard let configDirectory,
          withStateLock({ coreStarted }) else { return }

    reasserting = true
    stopCore()
    do {
      try startCore(configDirectory: configDirectory)
      startPacketFlowPump()
      reasserting = false
    } catch {
      reasserting = false
      NSLog(
        "Clashy Packet Tunnel could not restart after a network change: %@",
        error.localizedDescription
      )
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
