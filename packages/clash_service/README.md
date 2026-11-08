# clash_service

Platform service lifecycle for Clashy. iOS uses Apple's Network Extension
Packet Tunnel API; the Go core runs inside the `PacketTunnel` extension, not in
the Flutter app.

On desktop, the service can run the Clash core with TUN disabled so proxies
remain available while the VPN switch is off. Starting the VPN enables TUN;
stopping it disables TUN without stopping the core. The macOS, Windows, and
Linux service API exposes these as separate core and VPN operations. Reloading
the current configuration preserves the service's current VPN/TUN state. iOS
keeps its existing Packet Tunnel lifecycle.

## iOS setup

- Enable the **Network Extensions > Packet Tunnel** capability for
  `PacketTunnel`.
- Enable the **App Groups** capability for both `Runner` and `PacketTunnel`,
  using the same group identifier.
- The project uses `com.aote.clashy` for the app,
  `com.aote.clashy.PacketTunnel` for its extension, and
  `group.com.aote.clashy` for the App Group. Use a provisioning profile that
  authorizes the Network Extension and App Group.
- Run `flutter pub get` to resolve the Flutter plugin's Swift package. Do not
  run `pod install`; build the app through Flutter or `Runner.xcworkspace`.
- A physical iOS device is required to start the VPN. Simulator builds compile
  the app and extension, but the tunnel data plane is intentionally disabled
  there.

The app and extension share the selected profile through the App Group
container. The extension applies system routes and bridges `NEPacketTunnelFlow`
packets to mihomo's Darwin TUN adapter. The profile's `tun.stack` selection
(`mips`, `gvisor`, `mixed`, or `system`) is honored. iOS does not support
Android's per-app allow/disallow list behavior.
