//
//  MihomoXPCClient.swift
//  Runner
//
//  Created by aote on 2026/9/11.
//

import Foundation

final class MihomoXPCClient {
    private var connection: NSXPCConnection?

    init() {
        connect()
    }

    func connect() {
        if self.connection != nil {
            return
        }

        let connection = NSXPCConnection(
            machServiceName: "com.aote.clashy.helper"
        )

        connection.remoteObjectInterface =
            NSXPCInterface(
                with: MihomoServiceProtocol.self
            )

        connection.invalidationHandler = { [weak self] in
            print("❌ XPC invalidated")
            self?.connection = nil
        }

        connection.interruptionHandler = {
            print("⚠️ XPC interrupted")
        }

        self.connection = connection

        connection.resume()
    }

    func start(
        configDir: String,
        completion: @escaping ([String: Any]) -> Void
    ) {
        let service: any MihomoServiceProtocol = getService { error in
            completion([
                "status": -1,
                "error": error.localizedDescription,
            ])
        }

        service.start(
            configDir: configDir
        ) { res in
            completion(res)
        }
    }

    func stop(
        completion: @escaping ([String: Any]) -> Void
    ) {
        let service = getService { error in
            completion([
                "status": -1,
                "error": error.localizedDescription,
            ])
        }

        service.stop { res in
            completion(res)
        }
    }

    func restart(
        configDir: String,
        completion: @escaping ([String: Any]) -> Void
    ) {
        let service = getService { error in
            completion([
                "status": -1,
                "error": error.localizedDescription,
            ])
        }

        service.restart(
            configDir: configDir
        ) { res in
            completion(res)
        }
    }

    func status(
        completion: @escaping ([String: Any]) -> Void
    ) {
        let service = getService { error in
            completion([
                "status": -1,
                "error": error.localizedDescription,
            ])
        }

        service.status { res in
            completion(res)
        }
    }

    private func getService(
        errorHandler: @escaping (Error) -> Void
    ) -> MihomoServiceProtocol {

        if connection == nil {
            connect()
        }

        return connection!.remoteObjectProxyWithErrorHandler(
            errorHandler
        ) as! MihomoServiceProtocol
    }

}
