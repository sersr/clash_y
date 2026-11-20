import AppKit
import Foundation

// MARK: - Options

private struct Options {
    var appPath: String?
    var serviceSocket: String?
    var clashSocket: String?

    var bundleId: String? {
        guard let appPath else { return nil }
        return Bundle(path: appPath)?.bundleIdentifier
    }

    static func parse() -> Options {
        var options = Options()
        var args = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = args.next() {
            switch arg {
            case "--app": options.appPath = args.next()
            case "--service-socket": options.serviceSocket = args.next()
            case "--clash-socket": options.clashSocket = args.next()
            default: break
            }
        }
        return options
    }
}

// MARK: - Unix socket HTTP

private func openUnixSocket(_ path: String, timeout: TimeInterval = 2) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8CString)
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        close(fd)
        return nil
    }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            for (index, byte) in pathBytes.enumerated() {
                dest[index] = byte
            }
        }
    }

    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, size)
        }
    }
    guard result == 0 else {
        close(fd)
        return nil
    }

    var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var sendTv = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTv, socklen_t(MemoryLayout<timeval>.size))
    return fd
}

private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    var remaining = data
    while !remaining.isEmpty {
        let written = remaining.withUnsafeBytes { pointer -> Int in
            guard let base = pointer.baseAddress else { return -1 }
            return write(fd, base, remaining.count)
        }
        if written <= 0 { return false }
        remaining = remaining.dropFirst(written)
    }
    return true
}

private func readChunk(_ fd: Int32) -> Data? {
    var buffer = [UInt8](repeating: 0, count: 8192)
    let count = recv(fd, &buffer, buffer.count, 0)
    guard count > 0 else { return nil }
    return Data(buffer[0..<count])
}

private struct HTTPResponse {
    let statusCode: Int
    let body: Data
}

private func readResponse(_ fd: Int32) -> HTTPResponse? {
    var raw = Data()
    while let chunk = readChunk(fd) {
        raw.append(chunk)
    }
    guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let head = String(decoding: raw[..<headerEnd.lowerBound], as: UTF8.self)
    guard let statusLine = head.components(separatedBy: "\r\n").first else { return nil }
    let statusParts = statusLine.split(separator: " ")
    guard statusParts.count > 1, let status = Int(statusParts[1]) else { return nil }
    let body = Data(raw[headerEnd.upperBound...])
    let responseBody =
        head.lowercased().contains("transfer-encoding: chunked")
        ? decodeChunked(body)
        : body
    return HTTPResponse(statusCode: status, body: responseBody)
}

private func decodeChunked(_ data: Data) -> Data {
    var output = Data()
    var rest = Data(data)
    while true {
        guard let lineEnd = rest.range(of: Data("\r\n".utf8)) else { break }
        let line = String(decoding: rest[..<lineEnd.lowerBound], as: UTF8.self)
        let sizeText = line.split(separator: ";").first.map(String.init) ?? line
        guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else {
            break
        }
        rest.removeSubrange(..<lineEnd.upperBound)
        if size == 0 { break }
        guard rest.count >= size + 2 else {
            output.append(rest)
            break
        }
        output.append(rest.prefix(size))
        rest.removeFirst(size + 2)
    }
    return output
}

// MARK: - Clash API

private struct ProxyGroup: Equatable {
    let name: String
    let type: String
    let options: [String]
    let selected: String?

    var supportsManualSelection: Bool {
        ["Selector", "URLTest", "Fallback"].contains(type)
    }
}

private struct ClashClient {
    let serviceSocket: String?
    let clashSocket: String?

    func isRunning() -> Bool {
        guard let serviceSocket, let fd = openUnixSocket(serviceSocket) else {
            return false
        }
        defer { close(fd) }
        let request = "GET /clash/status HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        guard writeAll(fd, Data(request.utf8)) else { return false }
        guard let response = readResponse(fd),
            (200..<300).contains(response.statusCode),
            let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        else { return false }
        return json["success"] as? Bool ?? (json["data"] as? Bool ?? false)
    }

    func stop() {
        guard let serviceSocket, let fd = openUnixSocket(serviceSocket) else {
            return
        }
        defer { close(fd) }
        let request =
            "POST /clash/stop HTTP/1.1\r\nHost: localhost\r\n"
            + "Content-Type: application/json\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = writeAll(fd, Data(request.utf8))
        _ = readResponse(fd)
    }

    func currentMode() -> String? {
        guard let response = request(method: "GET", path: "/configs"),
            (200..<300).contains(response.statusCode),
            let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let mode = json["mode"] as? String
        else {
            return nil
        }
        return mode.lowercased()
    }

    func proxyGroups() -> [ProxyGroup]? {
        guard let response = request(method: "GET", path: "/proxies"),
            (200..<300).contains(response.statusCode),
            let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let proxies = json["proxies"] as? [String: Any]
        else {
            fputs("Failed to load proxy groups from Clash API\n", stderr)
            return nil
        }

        return proxies.compactMap { name, value in
            guard
                let proxy = value as? [String: Any],
                let type = proxy["type"] as? String,
                let options = proxy["all"] as? [String]
            else {
                return nil
            }
            return ProxyGroup(
                name: name,
                type: type,
                options: options,
                selected: proxy["now"] as? String
            )
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func selectMode(_ mode: String) -> Bool {
        guard let body = jsonBody(["mode": mode]),
            let response = request(method: "PATCH", path: "/configs", body: body)
        else {
            fputs("Failed to change Clash mode to \(mode)\n", stderr)
            return false
        }
        guard (200..<300).contains(response.statusCode) else {
            fputs(
                "Clash mode change failed with HTTP \(response.statusCode)\n",
                stderr
            )
            return false
        }
        return true
    }

    func selectProxy(group: String, proxy: String) -> Bool {
        guard
            let encodedGroup = group.addingPercentEncoding(
                withAllowedCharacters: CharacterSet(
                    charactersIn:
                        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
                )
            ),
            let body = jsonBody(["name": proxy]),
            let response = request(
                method: "PUT",
                path: "/proxies/\(encodedGroup)",
                body: body
            )
        else {
            fputs("Failed to select proxy \(proxy) in group \(group)\n", stderr)
            return false
        }
        guard (200..<300).contains(response.statusCode) else {
            fputs(
                "Proxy selection failed for \(group) with HTTP \(response.statusCode)\n",
                stderr
            )
            return false
        }
        return true
    }

    private func request(
        method: String,
        path: String,
        body: Data? = nil
    ) -> HTTPResponse? {
        guard let clashSocket, let fd = openUnixSocket(clashSocket) else {
            return nil
        }
        defer { close(fd) }

        var headers = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\n"
        if let body {
            headers += "Content-Type: application/json\r\n"
            headers += "Content-Length: \(body.count)\r\n"
        } else if method != "GET" {
            headers += "Content-Length: 0\r\n"
        }
        headers += "Connection: close\r\n\r\n"
        var requestData = Data(headers.utf8)
        if let body { requestData.append(body) }
        guard writeAll(fd, requestData) else { return nil }
        return readResponse(fd)
    }

    private func jsonBody(_ object: [String: String]) -> Data? {
        do {
            return try JSONSerialization.data(withJSONObject: object)
        } catch {
            fputs("Failed to encode Clash API request: \(error)\n", stderr)
            return nil
        }
    }

    /// 订阅 mihomo 的 `/traffic`，每行一个 JSON；返回时表示流已断开。
    func streamTraffic(onLine: (Int, Int) -> Void) -> Bool {
        guard let path = clashSocket, let fd = openUnixSocket(path, timeout: 10) else {
            return false
        }
        defer { close(fd) }

        let request = "GET /traffic HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
        guard writeAll(fd, Data(request.utf8)) else { return false }

        var raw = Data()
        var headersDone = false
        var chunked = false
        var chunkRemaining = 0
        var expectingChunkSize = true
        var payload = Data()
        var lineBuffer = Data()

        while true {
            guard let chunk = readChunk(fd) else { return false }

            if !headersDone {
                raw.append(chunk)
                guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { continue }
                let head = String(decoding: raw[..<headerEnd.lowerBound], as: UTF8.self)
                guard head.hasPrefix("HTTP/1.1 200") || head.hasPrefix("HTTP/1.0 200") else {
                    return false
                }
                chunked = head.lowercased().contains("transfer-encoding: chunked")
                raw = Data(raw[headerEnd.upperBound...])
                headersDone = true
            } else {
                raw.append(chunk)
            }

            if chunked {
                while true {
                    if expectingChunkSize {
                        guard let lineEnd = raw.range(of: Data("\r\n".utf8)) else { break }
                        let line = String(decoding: raw[..<lineEnd.lowerBound], as: UTF8.self)
                        let sizeText = line.split(separator: ";").first.map(String.init) ?? line
                        guard
                            let size = Int(
                                sizeText.trimmingCharacters(in: .whitespaces),
                                radix: 16
                            )
                        else { return false }
                        raw.removeSubrange(..<lineEnd.upperBound)
                        if size == 0 { return true }
                        chunkRemaining = size
                        expectingChunkSize = false
                    } else {
                        guard raw.count >= chunkRemaining + 2 else { break }
                        payload.append(raw.prefix(chunkRemaining))
                        raw.removeFirst(chunkRemaining + 2)
                        chunkRemaining = 0
                        expectingChunkSize = true
                    }
                }
            } else {
                payload.append(raw)
                raw.removeAll()
            }

            emitLines(&payload, &lineBuffer, onLine: onLine)
        }
    }

    private func emitLines(
        _ payload: inout Data,
        _ lineBuffer: inout Data,
        onLine: (Int, Int) -> Void
    ) {
        lineBuffer.append(payload)
        payload.removeAll(keepingCapacity: true)

        while let newline = lineBuffer.range(of: Data("\n".utf8)) {
            let lineData = lineBuffer[..<newline.lowerBound]
            lineBuffer.removeSubrange(...newline.lowerBound)
            guard let text = String(data: lineData, encoding: .utf8) else { continue }
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("{"), let data = line.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            onLine(json["up"] as? Int ?? 0, json["down"] as? Int ?? 0)
        }
    }
}

// MARK: - App

private func templateTrayImage(from image: NSImage, size: NSSize) -> NSImage? {
    var proposedRect = CGRect(origin: .zero, size: image.size)
    guard
        let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else {
        return nil
    }

    let width = source.width
    let height = source.height
    let bytesPerRow = width * 4
    var sourcePixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let didRenderSource = sourcePixels.withUnsafeMutableBytes { pixels -> Bool in
        guard
            let context = CGContext(
                data: pixels.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            )
        else {
            return false
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard didRenderSource else { return nil }

    var maskPixels = [UInt8](repeating: 0, count: sourcePixels.count)
    for offset in stride(from: 0, to: sourcePixels.count, by: 4) {
        let sourceAlpha = Int(sourcePixels[offset + 3])
        guard sourceAlpha > 0 else { continue }
        let red = Int(sourcePixels[offset])
        let green = Int(sourcePixels[offset + 1])
        let blue = Int(sourcePixels[offset + 2])
        let saturation =
            CGFloat(max(red, green, blue) - min(red, green, blue))
            / CGFloat(sourceAlpha)
        let opacity =
            min(max((saturation - 0.08) / 0.16, 0), 1)
            * CGFloat(sourceAlpha) / 255
        let alpha = UInt8((opacity * 255).rounded())
        maskPixels[offset] = alpha
        maskPixels[offset + 1] = alpha
        maskPixels[offset + 2] = alpha
        maskPixels[offset + 3] = alpha
    }

    guard
        let provider = CGDataProvider(data: Data(maskPixels) as CFData),
        let mask = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    else {
        return nil
    }

    let result = NSImage(cgImage: mask, size: size)
    result.isTemplate = true
    return result
}

private final class TraySpeedView: NSView {
    private static let minimumWidth: CGFloat = 42
    private var titleWidth = TraySpeedView.minimumWidth
    private var attributedTitle: NSAttributedString?

    private let titleAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.maximumLineHeight = 9
        paragraphStyle.minimumLineHeight = 9
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byClipping
        return [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: 8.75),
            .foregroundColor: NSColor.labelColor,
        ]
    }()

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: titleWidth, height: NSView.noIntrinsicMetric)
    }

    @discardableResult
    func setTitle(_ title: String) -> Bool {
        let previousWidth = titleWidth
        if title.isEmpty {
            attributedTitle = nil
            titleWidth = Self.minimumWidth
        } else {
            let text = NSAttributedString(string: title, attributes: titleAttributes)
            attributedTitle = text
            titleWidth = max(Self.minimumWidth, ceil(measure(text).width))
        }
        needsDisplay = true
        let widthChanged = titleWidth != previousWidth
        if widthChanged {
            invalidateIntrinsicContentSize()
        }
        return widthChanged
    }

    private func measure(_ text: NSAttributedString) -> NSSize {
        text.boundingRect(
            with: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let attributedTitle else { return }
        let textBounds = attributedTitle.boundingRect(
            with: NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textHeight = ceil(textBounds.height)
        let y = max((bounds.height - textHeight) / 2, 0)
        attributedTitle.draw(in: NSRect(x: 0, y: y, width: bounds.width, height: textHeight))
    }
}

private final class TrayContentView: NSView {
    let speedView = TraySpeedView()

    init(image: NSImage) {
        super.init(frame: .zero)

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        speedView.setContentHuggingPriority(.required, for: .horizontal)
        speedView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stackView = NSStackView(views: [imageView, speedView])
        stackView.orientation = .horizontal
        stackView.spacing = 6
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TrayController: NSObject, NSApplicationDelegate {
    private let options = Options.parse()
    private lazy var client = ClashClient(
        serviceSocket: options.serviceSocket,
        clashSocket: options.clashSocket
    )

    private var statusItem: NSStatusItem!
    private var contentView: TrayContentView!
    private var menu: NSMenu!
    private var modeItems: [String: NSMenuItem] = [:]
    private var showAppItem: NSMenuItem!
    private var proxyGroupSeparator: NSMenuItem!
    private var vpnItem: NSMenuItem!
    private var proxyGroupItems: [NSMenuItem] = []
    private var cachedProxyGroups: [ProxyGroup]?
    private var isRunning = false
    private var isRefreshingMenuState = false
    private var menuRefreshTimer: Timer?
    private var clickWork: DispatchWorkItem?
    private var lastClickAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        buildMenu()
        startMonitor()
        startMenuMonitor()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let iconURL = options.appPath.map {
                URL(fileURLWithPath: $0)
                    .appendingPathComponent(
                        "Contents/Frameworks/App.framework/Versions/A/Resources/"
                            + "flutter_assets/assets/icons/clashy.png"
                    )
            }
            let sourceImage = iconURL.flatMap { NSImage(contentsOf: $0) }
            let iconImage = sourceImage.flatMap {
                templateTrayImage(from: $0, size: NSSize(width: 18, height: 18))
            }
            if iconImage == nil {
                fputs("Failed to load Clashy tray icon from app bundle\n", stderr)
            }
            let symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 17,
                weight: .regular
            )
            let displayedImage: NSImage
            if let iconImage {
                displayedImage = iconImage
            } else {
                let fallback = NSImage(
                    systemSymbolName: "shield.lefthalf.filled",
                    accessibilityDescription: "Clashy"
                )
                fallback?.isTemplate = true
                displayedImage =
                    fallback?.withSymbolConfiguration(symbolConfiguration) ?? NSImage()
            }
            contentView = TrayContentView(image: displayedImage)
            contentView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(contentView)
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                contentView.topAnchor.constraint(equalTo: button.topAnchor),
                contentView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                contentView.heightAnchor.constraint(
                    equalToConstant: NSStatusBar.system.thickness
                ),
            ])
            button.toolTip = "Clashy"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateSpeed(up: 0, down: 0)
    }

    private func buildMenu() {
        menu = NSMenu()

        showAppItem = menu.addItem(
            withTitle: "显示 Clashy", action: #selector(openApp), keyEquivalent: ""
        )
        menu.addItem(.separator())

        showAppItem.target = self
        for (title, mode) in [("Rule", "rule"), ("Global", "global"), ("Direct", "direct")] {
            let item = menu.addItem(
                withTitle: title,
                action: #selector(selectModeFromMenu),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            item.isEnabled = false
            modeItems[mode] = item
        }
        menu.addItem(.separator())
        let loadingItem = menu.addItem(withTitle: "正在加载代理组…", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        proxyGroupItems = [loadingItem]

        proxyGroupSeparator = NSMenuItem.separator()
        menu.addItem(proxyGroupSeparator)
        vpnItem = menu.addItem(withTitle: "关闭 VPN", action: #selector(stopVpn), keyEquivalent: "")
        vpnItem.target = self
    }

    // MARK: Clicks

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            lastClickAt = nil
            clickWork?.cancel()
            clickWork = nil
            showMenu()
            return
        }

        // macOS 的双击会先派发一次单击，用点击间隔自行判定，避免依赖 clickCount。
        let now = Date()
        let isDoubleClick = lastClickAt.map { now.timeIntervalSince($0) < 0.35 } ?? false
        clickWork?.cancel()
        clickWork = nil

        if event.clickCount >= 2 || isDoubleClick {
            lastClickAt = nil
            showMenu()
            return
        }

        lastClickAt = now
        let work = DispatchWorkItem { [weak self] in self?.openApp() }
        clickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func showMenu() {
        refreshMenuState()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Actions

    @objc private func openApp() {
        if let bundleId = options.bundleId,
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
        guard let path = options.appPath else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: configuration
        ) { _, _ in }
    }

    @objc private func stopVpn() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.client.stop()
        }
    }

    @objc private func selectModeFromMenu(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.client.selectMode(mode) else { return }
            let selectedMode = self.client.currentMode()
            DispatchQueue.main.async {
                if let selectedMode {
                    self.updateSelectedMode(selectedMode)
                }
            }
        }
    }

    @objc private func selectProxyFromMenu(_ sender: NSMenuItem) {
        guard
            let selection = sender.representedObject as? [String],
            selection.count == 2
        else {
            return
        }
        let group = selection[0]
        let proxy = selection[1]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.client.selectProxy(group: group, proxy: proxy) else {
                return
            }
            guard let groups = self.client.proxyGroups() else { return }
            DispatchQueue.main.async {
                self.updateProxyGroups(groups)
            }
        }
    }

    @objc private func quitAgent() {
        NSApp.terminate(nil)
    }

    // MARK: Monitor

    private func startMonitor() {
        let thread = Thread { [weak self] in self?.monitorLoop() }
        thread.name = "clashy-tray-monitor"
        thread.start()
    }

    private func startMenuMonitor() {
        refreshMenuState()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshMenuState()
        }
        RunLoop.main.add(timer, forMode: .common)
        menuRefreshTimer = timer
    }

    private func refreshMenuState() {
        guard !isRefreshingMenuState else { return }
        isRefreshingMenuState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let running = self.client.isRunning()
            let mode = running ? self.client.currentMode() : nil
            let groups = running ? self.client.proxyGroups() : nil
            DispatchQueue.main.async {
                self.isRefreshingMenuState = false
                self.setRunning(running)
                if let mode {
                    self.updateSelectedMode(mode)
                }
                if running {
                    if let groups {
                        self.updateProxyGroups(groups)
                    }
                } else {
                    self.updateProxyGroups([])
                }
            }
        }
    }

    private func monitorLoop() {
        while true {
            let running = client.isRunning()
            DispatchQueue.main.async { [weak self] in self?.setRunning(running) }

            guard running else {
                DispatchQueue.main.async { [weak self] in self?.updateSpeed(up: 0, down: 0) }
                Thread.sleep(forTimeInterval: 3)
                continue
            }

            _ = client.streamTraffic { up, down in
                DispatchQueue.main.async { [weak self] in self?.updateSpeed(up: up, down: down) }
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func setRunning(_ value: Bool) {
        isRunning = value
        vpnItem?.isEnabled = value
        modeItems.values.forEach { $0.isEnabled = value }
        for groupItem in proxyGroupItems {
            groupItem.isEnabled = value && groupItem.submenu != nil
            groupItem.submenu?.items.forEach { item in
                guard item.action != nil else { return }
                item.isEnabled = value && item.tag == 1
            }
        }
    }

    private func updateSelectedMode(_ mode: String) {
        for (name, item) in modeItems {
            item.state = name == mode ? .on : .off
        }
    }

    private func updateProxyGroups(_ groups: [ProxyGroup]) {
        guard groups != cachedProxyGroups else { return }
        cachedProxyGroups = groups
        for item in proxyGroupItems {
            menu.removeItem(item)
        }
        proxyGroupItems.removeAll()

        proxyGroupSeparator.isHidden = groups.isEmpty
        guard !groups.isEmpty else { return }

        for group in groups {
            let groupItem = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            if group.options.isEmpty {
                let emptyItem = NSMenuItem(
                    title: "暂无可用节点",
                    action: nil,
                    keyEquivalent: ""
                )
                emptyItem.isEnabled = false
                submenu.addItem(emptyItem)
            } else {
                for proxy in group.options {
                    let item = NSMenuItem(
                        title: proxy,
                        action: #selector(selectProxyFromMenu),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = [group.name, proxy]
                    item.tag = group.supportsManualSelection ? 1 : 0
                    item.state = group.selected == proxy ? .on : .off
                    item.isEnabled = isRunning && group.supportsManualSelection
                    submenu.addItem(item)
                }
            }
            groupItem.submenu = submenu
            groupItem.isEnabled = isRunning
            if !group.supportsManualSelection {
                groupItem.toolTip = "此代理组不支持手动切换"
            }
            let insertionIndex = menu.index(of: proxyGroupSeparator)
            menu.insertItem(groupItem, at: insertionIndex)
            proxyGroupItems.append(groupItem)
        }
    }

    private func updateSpeed(up: Int, down: Int) {
        let changed = contentView.speedView.setTitle(
            "\(speedLine(up))\n\(speedLine(down))"
        )
        if changed {
            statusItem?.button?.sizeToFit()
        }
    }

    private func speedLine(_ bytes: Int) -> String {
        "\(format(bytes))/s"
    }

    private func format(_ bytes: Int) -> String {
        let kb = 1024.0
        let mb = kb * 1024
        let gb = mb * 1024
        let tb = gb * 1024
        let value = Double(bytes)
        if value >= tb { return String(format: "%.1fT", value / tb) }
        if value >= gb { return String(format: "%.1fG", value / gb) }
        if value >= mb { return String(format: "%.1fM", value / mb) }
        if value >= kb { return String(format: "%.0fK", value / kb) }
        return "\(bytes)B"
    }
}

// MARK: - Entry

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
private let controller = TrayController()
application.delegate = controller
application.run()
