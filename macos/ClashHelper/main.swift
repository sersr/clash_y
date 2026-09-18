//
//  main.swift
//  clashHelper
//

import Foundation

// MARK: - Service

let mihomoService = MihomoService()

// MARK: - XPC Delegate

final class Delegate: NSObject, NSXPCListenerDelegate {

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {

        print("🔥 XPC client connected")

        connection.exportedInterface =
            NSXPCInterface(
                with: MihomoServiceProtocol.self
            )

        connection.exportedObject = mihomoService

        connection.invalidationHandler = {
            print("XPC client invalidated")
        }

        connection.interruptionHandler = {
            print("XPC client interrupted")
        }

        connection.resume()

        return true
    }
}

// MARK: - Listener

let listener = NSXPCListener(
    machServiceName: "com.aote.clashy.helper"
)

let delegate = Delegate()

listener.delegate = delegate
listener.resume()

print("================================")
print("🔥 clashHelper started")
print("PID:", ProcessInfo.processInfo.processIdentifier)
print("================================")

// MARK: - Automatically start Mihomo
//
// Helper 每次启动时：
// 1. 读取之前保存的 configDir
// 2. 有 configDir → 启动 Mihomo
// 3. 没有 configDir → 不启动
//

mihomoService.start { res in
    print(
        "🔥 auto start mihomo:",
        res
    )
}

// MARK: - Keep Running

RunLoop.main.run()