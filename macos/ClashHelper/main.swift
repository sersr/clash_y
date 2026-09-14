import Foundation

final class Delegate: NSObject, NSXPCListenerDelegate {

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {

        print("XPC client connected")

        connection.exportedInterface =
            NSXPCInterface(with: MihomoServiceProtocol.self)

        connection.exportedObject = MihomoService.shared

        connection.resume()

        return true
    }
}

let listener = NSXPCListener(
    machServiceName: "com.aote.clashy.helper"
)

let delegate = Delegate()

listener.delegate = delegate
listener.resume()

print("🔥 clashHelper started")

RunLoop.main.run()