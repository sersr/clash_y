//
//  MihomoService.swift
//  Runner
//
//  Created by aote on 2026/9/11.
//

import Foundation

final class MihomoService: NSObject, MihomoServiceProtocol {
    static let shared = MihomoService()
    private let queue = DispatchQueue(label: "com.aote.clashy.clash.service")

    private let processManager = MihomoProcessManager()

    func start(
        configPath: String,
        reply: @escaping ([String: Any]) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let res = try self.processManager.start(configPath: configPath)
                reply(res)
            } catch {
                reply(["status": -1, "error": error.localizedDescription])
            }
        }
    }

    func stop(reply: @escaping ([String: Any]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.processManager.stop { [weak self] in
                self?.queue.async {
                    reply(["status": 0, "error": ""])
                }
            }
        }
    }

    func restart(
        configPath: String,
        reply: @escaping ([String: Any]) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.processManager.stop { [weak self] in
                guard let self else { return }
                // 给内核一点时间释放监听端口
                self.queue.asyncAfter(deadline: .now() + 0.3) {
                    do {
                        let res = try self.processManager.start(configPath: configPath)
                        reply(res)
                    } catch {
                        reply(["status": -1, "error": error.localizedDescription])
                    }
                }
            }
        }
    }

    func status(reply: @escaping ([String: Any]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            reply([
                "status": self.processManager.isRunning,
                "pid": self.processManager.pid,
            ])
        }
    }
}
