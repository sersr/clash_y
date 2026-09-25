import ServiceManagement

@_cdecl("vpn_service_register_helper")
public func vpn_service_register_helper() -> Int32 {
  guard #available(macOS 13.0, *) else {
    return -2
  }

  do {
    let service = SMAppService.daemon(
      plistName: "com.aote.clashy.helper.plist"
    )

    try service.register()
    return 0
  } catch {
    print("register helper failed:", error)
    return -1
  }
}

@_cdecl("vpn_service_unregister_helper")
public func vpn_service_unregister_helper() -> Int32 {
  guard #available(macOS 13.0, *) else {
    return -2
  }

  do {
    let service = SMAppService.daemon(
      plistName: "com.aote.clashy.helper.plist"
    )

    try service.unregister()
    return 0
  } catch {
    print("unregister helper failed:", error)
    return -1
  }
}
