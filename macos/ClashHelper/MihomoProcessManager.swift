//
//  MihomoProcessManager.swift
//  Runner
//

import Darwin
import Foundation

let clashPath = "packages/clash_core/clash"

final class MihomoProcessManager {

    // MARK: - Constants

    private enum Constants {

        static let configDirFile =
            "/Library/Application Support/clashy/config_dir"

        static let stopTimeout: TimeInterval = 5
        static let pollInterval: TimeInterval = 0.1
    }

    // MARK: - Properties

    private let pidStore = MihomoPidStore()

    private var process: Process?

    // mihomo stdout/stderr 日志文件
    private var logHandle: FileHandle?

    // 防止 stop 被重复调用
    private var isStopping = false

    // MARK: - State

    var isRunning: Bool {
        process?.isRunning == true
    }

    var pid: Int32 {
        process?.processIdentifier ?? 0
    }

    // MARK: - Config Directory

    /// 当前保存的 configDir
    var configDir: String? {
        loadConfigDir()
    }

    /// 保存 configDir
    @discardableResult
    func saveConfigDir(_ configDir: String) -> Bool {

        let path = configDir.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !path.isEmpty else {
            return false
        }

        let fileURL = URL(fileURLWithPath: Constants.configDirFile)
        let directoryURL = fileURL.deletingLastPathComponent()

        do {

            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            try path.write(
                toFile: Constants.configDirFile,
                atomically: true,
                encoding: .utf8
            )

            print("[mihomo] configDir saved: \(path)")

            return true

        } catch {

            print("[mihomo] failed to save configDir: \(error)")

            return false
        }
    }

    /// 读取已经保存的 configDir
    private func loadConfigDir() -> String? {

        guard
            let data = FileManager.default.contents(
                atPath: Constants.configDirFile
            )
        else {
            return nil
        }

        guard
            let value = String(
                data: data,
                encoding: .utf8
            )
        else {
            return nil
        }

        let path = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !path.isEmpty else {
            return nil
        }

        return path
    }

    /// 删除保存的 configDir
    func clearConfigDir() {

        try? FileManager.default.removeItem(
            atPath: Constants.configDirFile
        )

        print("[mihomo] configDir cleared")
    }

    // MARK: - Asset Path

    private func flutterAssetURL(for assetKey: String) -> URL? {

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

    /// 第一次启动：
    ///
    ///     start(configDir: "/Library/Application Support/clashy")
    ///
    /// 后续 Helper 重启：
    ///
    ///     start()
    ///
    /// 自动读取之前保存的 configDir。
    @discardableResult
    func start(configDir: String? = nil) throws -> [String: Any] {

        // ---------------------------------------------------------
        // 1. 如果当前已经运行，直接返回
        // ---------------------------------------------------------

        if let process, process.isRunning {

            return [
                "status": 0,
                "pid": process.processIdentifier,
                "msg": "running",
                "error": "",
            ]
        }

        // ---------------------------------------------------------
        // 2. 查找 mihomo executable
        // ---------------------------------------------------------

        guard
            let clashURL = flutterAssetURL(
                for: clashPath
            )
        else {

            throw mihomoError(
                code: 1,
                message: "Cannot find clash executable"
            )
        }

        // ---------------------------------------------------------
        // 4. 确定 configDir
        //
        // 第一次：
        //     start(configDir: xxx)
        //
        // 后续：
        //     start()
        // ---------------------------------------------------------

        let resolvedConfigDir: String

        if let configDir {

            let path = configDir.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !path.isEmpty else {

                throw mihomoError(
                    code: 2,
                    message: "configDir is empty"
                )
            }

            resolvedConfigDir = path

            // 第一次启动时保存
            guard saveConfigDir(path) else {
                throw mihomoError(
                    code: 3,
                    message:
                        "Failed to save configDir: \(path)"
                )
            }

        } else {

            guard let savedDir = loadConfigDir() else {

                print(
                    "[mihomo] no configDir saved, do not start"
                )

                return [
                    "status": 1,
                    "pid": 0,
                    "msg": "configDir not configured",
                    "error": "",
                ]
            }

            resolvedConfigDir = savedDir
        }

        // ---------------------------------------------------------
        // 5. 检查 configDir
        // ---------------------------------------------------------

        var isDirectory: ObjCBool = false

        guard
            FileManager.default.fileExists(
                atPath: resolvedConfigDir,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw mihomoError(
                code: 4,
                message:
                    "Config directory does not exist: \(resolvedConfigDir)"
            )
        }

        // ---------------------------------------------------------
        // 6. 检查 config.yaml
        // ---------------------------------------------------------

        let configURL = URL(fileURLWithPath: resolvedConfigDir)
            .appendingPathComponent("config.yaml")

        guard
            FileManager.default.fileExists(
                atPath: configURL.path
            )
        else {
            throw mihomoError(
                code: 5,
                message:
                    "config.yaml does not exist: \(configURL.path)"
            )
        }

        // ---------------------------------------------------------
        // 7. 清理旧日志句柄
        // ---------------------------------------------------------

        cleanupLog()
        cleanupStaleProcess(path: clashURL.path)

        // ---------------------------------------------------------
        // 8. 创建 Process
        // ---------------------------------------------------------

        let newProcess = Process()

        newProcess.executableURL = clashURL

        newProcess.arguments = [
            "-d",
            resolvedConfigDir,
        ]

        let logURL =
            configURL
            .deletingPathExtension()
            .appendingPathExtension("yaml.log")

        do {

            if !FileManager.default.fileExists(
                atPath: logURL.path
            ) {

                FileManager.default.createFile(
                    atPath: logURL.path,
                    contents: nil
                )
            }

            let handle = try FileHandle(
                forWritingTo: logURL
            )

            // 追加写入，不覆盖之前日志
            handle.seekToEndOfFile()

            logHandle = handle

            newProcess.standardOutput = handle
            newProcess.standardError = handle

            print(
                "[mihomo] log file: \(logURL.path)"
            )

        } catch {
            throw mihomoError(
                code: 6,
                message:
                    "Failed to open mihomo log: \(error)"
            )
        }

        // ---------------------------------------------------------
        // 10. terminationHandler
        // ---------------------------------------------------------

        newProcess.terminationHandler = {
            [weak self] process in

            guard let self else {
                return
            }

            print(
                "mihomo terminated: " + "status=\(process.terminationStatus), "
                    + "pid=\(process.processIdentifier)"
            )

            DispatchQueue.main.async {
                if self.process === process {
                    self.process = nil
                    self.cleanupLog()
                    self.isStopping = false
                }
            }
        }

        // ---------------------------------------------------------
        // 11. 启动
        // ---------------------------------------------------------

        do {

            try newProcess.run()

        } catch {

            cleanupLog()

            throw mihomoError(
                code: 7,
                message:
                    "Failed to start mihomo: \(error)"
            )
        }

        process = newProcess

        // ---------------------------------------------------------
        // 12. 保存 PID
        // ---------------------------------------------------------

        pidStore.write(
            pid: newProcess.processIdentifier,
            executablePath: executablePath(of: newProcess.processIdentifier) ?? clashURL.path,
        )

        print(
            "mihomo started, " + "pid=\(newProcess.processIdentifier), "
                + "configDir=\(resolvedConfigDir)"
        )

        return [
            "status": 0,
            "pid": newProcess.processIdentifier,
            "msg": "start success",
            "error": "",
        ]
    }

    // MARK: - Stop

    func stop(completion: @escaping () -> Void) {

        // 防止同时执行多个 stop
        guard !isStopping else {
            completion()
            return
        }

        guard let process else {
            cleanupLog()
            completion()
            return
        }

        guard process.isRunning else {
            pidStore.clear(pid: process.processIdentifier)
            self.process = nil
            cleanupLog()
            completion()
            return
        }

        isStopping = true

        let pid = process.processIdentifier

        print(
            "mihomo stopping, pid=\(pid)"
        )

        process.terminate()

        let deadline = Date().addingTimeInterval(
            Constants.stopTimeout
        )

        func poll() {

            // -----------------------------------------------------
            // 已经退出
            // -----------------------------------------------------

            if !process.isRunning {

                print(
                    "mihomo stopped, pid=\(pid)"
                )

                DispatchQueue.main.async {

                    self.isStopping = false

                    if self.process === process {
                        self.pidStore.clear(pid: process.processIdentifier)
                        self.process = nil
                    }
                    self.cleanupLog()
                    completion()
                }

                return
            }

            // -----------------------------------------------------
            // 超时
            // -----------------------------------------------------

            if Date() >= deadline {

                print(
                    "mihomo did not terminate in time, " + "killing, pid=\(pid)"
                )

                kill(pid, SIGKILL)

                DispatchQueue.main.async {

                    self.isStopping = false

                    if self.process === process {
                        self.pidStore.clear(pid: process.processIdentifier)
                        self.process = nil
                    }

                    self.cleanupLog()

                    completion()
                }

                return
            }

            // -----------------------------------------------------
            // 继续等待
            // -----------------------------------------------------

            DispatchQueue.global().asyncAfter(
                deadline: .now() + Constants.pollInterval
            ) {
                poll()
            }
        }

        DispatchQueue.global().asyncAfter(
            deadline: .now() + Constants.pollInterval
        ) {
            poll()
        }
    }

    // MARK: - Stale Cleanup

    /// Helper 崩溃、kill -9、系统重启等情况下，
    /// 根据 PID 文件尝试清理之前遗留的 Mihomo。
    private func cleanupStaleProcess(
        path: String
    ) {

        guard let record = pidStore.load() else {
            return
        }

        defer {
            pidStore.clear(pid: record.pid)
        }

        let pid = record.pid

        guard let actualPath = executablePath(of: pid) else {

            print(
                "[cleanup] cannot resolve path for pid \(pid)"
            )

            return
        }

        guard actualPath.hasSuffix(clashPath) || actualPath == path else {

            print(
                "[cleanup] pid \(pid) is not our mihomo: " + "\(actualPath)"
            )

            return
        }

        print(
            "[cleanup] killing stale mihomo, pid=\(pid)"
        )

        if kill(pid, SIGKILL) != 0 {

            print(
                "[cleanup] failed to kill pid \(pid), " + "errno=\(errno)"
            )
        }
    }

    // MARK: - Process Path

    private func executablePath(
        of pid: Int32
    ) -> String? {

        var buffer = [CChar](
            repeating: 0,
            count: Int(MAXPATHLEN)
        )

        let result = proc_pidpath(
            pid,
            &buffer,
            UInt32(buffer.count)
        )

        guard result > 0 else {
            return nil
        }

        return String(cString: buffer)
    }

    // MARK: - Log

    /// 关闭当前 mihomo 日志文件
    private func cleanupLog() {

        guard let handle = logHandle else {
            return
        }

        do {
            try handle.synchronize()
        } catch {
            print(
                "[mihomo] failed to synchronize log: \(error)"
            )
        }

        do {
            try handle.close()
        } catch {
            print(
                "[mihomo] failed to close log: \(error)"
            )
        }

        logHandle = nil
    }

    // MARK: - Error

    private func mihomoError(
        code: Int,
        message: String
    ) -> NSError {
        NSError(
            domain: "mihomo",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: message
            ]
        )
    }
}
