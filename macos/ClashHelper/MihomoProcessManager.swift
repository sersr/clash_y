//
//  MihomoProcessManager.swift
//  Runner
//

import Darwin
import Foundation

final class MihomoProcessManager {

    private let pidStore = MihomoPidStore()

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    var pid: Int32 {
        process?.processIdentifier ?? 0
    }

    // MARK: - Asset Path

    func flutterAssetURL(for assetKey: String) -> URL? {
        guard var url = Bundle.main.executableURL else {
            return nil
        }

        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()

        return
            url
            .appendingPathComponent("Frameworks")
            .appendingPathComponent("App.framework")
            .appendingPathComponent("Resources")
            .appendingPathComponent("flutter_assets")
            .appendingPathComponent(assetKey)
    }

    // MARK: - Start

    func start(configPath: String) throws -> [String: Any] {
        if isRunning {
            return [
                "status": 0,
                "pid": pid,
                "msg": "running",
                "error": "",
            ]
        }

        guard let clashURL = flutterAssetURL(for: "packages/clash_core/clash") else {
            throw NSError(
                domain: "clash",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot find clash executable"]
            )
        }

        guard FileManager.default.fileExists(atPath: configPath) else {
            throw NSError(
                domain: "clash",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Config file does not exist: \(configPath)"]
            )
        }

        // 🧹 清理上次残留（helper 崩溃 / 系统重启后遗留的 mihomo）
        cleanupStaleProcess(expectedPath: clashURL.path)

        cleanupPipes()

        let process = Process()
        process.executableURL = clashURL
        process.arguments = [
            "-d",
            URL(fileURLWithPath: configPath)
                .deletingLastPathComponent()
                .path,
        ]

        let stdout = Pipe()
        let stderr = Pipe()

        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                print("[mihomo] \(text)", terminator: "")
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                print("[mihomo:error] \(text)", terminator: "")
            }
        }

        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        process.terminationHandler = { [weak self] p in
            guard let self else { return }
            print("mihomo terminated: \(p.terminationStatus), pid=\(p.processIdentifier)")

            if self.process === p {
                self.process = nil
                self.cleanupPipes()
                self.pidStore.clear()
            }
        }

        try process.run()
        self.process = process

        // 📝 记录 PID，供下次启动清理
        pidStore.write(
            pid: process.processIdentifier,
            executablePath: clashURL.path
        )

        print("mihomo started, pid=\(process.processIdentifier)")

        return [
            "status": 0,
            "pid": process.processIdentifier,
            "msg": "start success",
            "error": "",
        ]
    }

    // MARK: - Stop

    func stop(completion: @escaping () -> Void) {
        guard let process = process else {
            pidStore.clear()
            cleanupPipes()
            completion()
            return
        }

        guard process.isRunning else {
            self.process = nil
            pidStore.clear()
            cleanupPipes()
            completion()
            return
        }

        let pid = process.processIdentifier
        print("mihomo stopping, pid=\(pid)")

        process.terminate()

        let deadline = Date().addingTimeInterval(5)

        func finish() {
            if self.process === process {
                self.process = nil
            }
            self.cleanupPipes()
            self.pidStore.clear()
            completion()
        }

        func poll() {
            if !process.isRunning {
                print("mihomo stopped, pid=\(pid)")
                finish()
                return
            }
            if Date() >= deadline {
                print("mihomo did not terminate in time, killing, pid=\(pid)")
                kill(pid, SIGKILL)
                finish()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                poll()
            }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            poll()
        }
    }

    // MARK: - Stale Cleanup

    /// 读取 PID 文件，校验可执行路径一致后 SIGKILL，最后清掉文件。
    /// 覆盖 helper 崩溃、被 kill -9、系统断电后残留的 mihomo。
    private func cleanupStaleProcess(expectedPath: String) {
        guard let record = pidStore.load() else { return }

        // 无论结果如何，先清掉记录，避免下次再读到同一份
        defer { pidStore.clear() }

        let pid = record.pid

        // 1. 进程是否还存在
        if kill(pid, 0) != 0 {
            let err = errno
            if err == ESRCH {
                print("[cleanup] pid \(pid) not running, nothing to do")
            } else if err == EPERM {
                print("[cleanup] pid \(pid) exists but EPERM (unexpected as root)")
            } else {
                print("[cleanup] kill(pid,0) failed: errno=\(err)")
            }
            return
        }

        // 2. 校验可执行路径，防 PID 复用误杀
        guard let path = executablePath(of: pid) else {
            print("[cleanup] cannot resolve path for pid \(pid), skip")
            return
        }
        guard path == expectedPath else {
            print("[cleanup] pid \(pid) is '\(path)', not our mihomo, skip")
            return
        }

        // 3. 确认是我们的进程 → 杀
        print("[cleanup] killing stale mihomo, pid=\(pid)")
        kill(pid, SIGKILL)
    }

    /// 通过 proc_pidpath 获取指定 pid 的可执行文件绝对路径
    private func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard ret > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Cleanup

    private func cleanupPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }
}
