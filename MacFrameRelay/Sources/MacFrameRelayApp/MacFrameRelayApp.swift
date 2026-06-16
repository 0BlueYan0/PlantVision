import SwiftUI
#if canImport(MacFrameRelayCore)
import MacFrameRelayCore
#endif
import ApplicationServices
import AppKit
import SocketIO

@main
private enum MacFrameRelayMain {
    @MainActor
    private static let appDelegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        appDelegate.showWindow()
        app.run()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        showWindow()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "MacFrameRelayApp")
        let quitItem = NSMenuItem(
            title: "Quit MacFrameRelayApp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = FrameRelayView()
            .frame(minWidth: 920, minHeight: 640)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacFrameRelayApp"
        window.center()
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
private final class FrameRelayViewModel: ObservableObject {
    @Published var capturedImage: NSImage?
    @Published var statusText = "尚未抽幀"
    @Published var relayURL: String {
        didSet {
            settingsStore.relayURL = relayURL
        }
    }
    @Published var pairingCode: String {
        didSet {
            settingsStore.pairingCode = pairingCode
        }
    }
    @Published var relayStatus = "Socket.IO 尚未連線"
    @Published var lastCaptureDescription = "等待 Vision Pro 鏡像畫面顯示於 Mac 螢幕"
    @Published var showsPermissionAction = false
    @Published var captureTargets: [CaptureTarget] = []
    @Published var selectedTargetID = ""
    @Published var isAutomaticCaptureRunning = false
    @Published var shortcutPermissionText = "全域快捷鍵尚未檢查權限"
    @Published var showsAccessibilityAction = false

    private let settingsStore: FrameRelaySettingsStore
    private let capturer = ScreenFrameCapturer()
    private let relayClient = SocketIORelayClient()
    private let plantClassifier = try? PlantImageClassifier()
    /// 枯萎程度分類器：與植物辨識完全獨立的第二個模型。找不到模型時為 nil，
    /// 此時只是不送枯萎欄位（向後相容），不影響植物辨識。
    private let witherClassifier = try? WitherImageClassifier()
    private var automaticCaptureTask: Task<Void, Never>?
    private var localModifierFlagsMonitor: Any?
    private var globalModifierFlagsMonitor: Any?
    private var activeCaptureShortcutAction: CaptureShortcutAction?

    /// 跨幀穩定器：對最近幾幀的逐幀判定做多數決，濾掉決策邊界附近的抖動。
    /// 取代原本「保留上一個非背景結果 1 秒」的 hold（那會延續錯標）。
    private var labelSmoother = TemporalLabelSmoother()
    /// 枯萎比例是連續值，用時間窗取平均壓抖動（與 labelSmoother 的多數決不同）。
    private var witherSmoother = TemporalWitherSmoother()

    init(settingsStore: FrameRelaySettingsStore = FrameRelaySettingsStore()) {
        self.settingsStore = settingsStore
        self.relayURL = settingsStore.relayURL
        self.pairingCode = settingsStore.pairingCode
        relayClient.onStatusChange = { [weak self] status in
            self?.relayStatus = status
        }
        refreshShortcutAccessibilityStatus()
        refreshCaptureTargets(requestPermissionIfNeeded: false)
    }

    deinit {
        automaticCaptureTask?.cancel()
    }

    func connectRelay() {
        guard let url = URL(string: relayURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            relayStatus = "Relay URL 無效"
            return
        }

        relayClient.connect(relayURL: url, pairingCode: pairingCode)
    }

    func toggleAutomaticCapture() {
        if isAutomaticCaptureRunning {
            stopAutomaticCapture()
        } else {
            startAutomaticCapture()
        }
    }

    func startAutomaticCapture() {
        guard !isAutomaticCaptureRunning else { return }

        showsPermissionAction = false
        guard capturer.hasScreenCaptureAccess || capturer.requestScreenCaptureAccess() else {
            statusText = ScreenCaptureError.permissionDenied.localizedDescription
            showsPermissionAction = true
            return
        }

        automaticCaptureTask?.cancel()
        isAutomaticCaptureRunning = true
        statusText = "正在每 0.1 秒自動擷取 Mac 當前畫面..."
        automaticCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let shouldContinue = await captureAndRelayNow()
                guard shouldContinue else { break }
                do {
                    try await Task.sleep(nanoseconds: FrameRelayCapturePolicy.automaticCaptureIntervalNanoseconds)
                } catch {
                    break
                }
            }

            if !Task.isCancelled {
                automaticCaptureTask = nil
                isAutomaticCaptureRunning = false
            }
        }
    }

    func stopAutomaticCapture() {
        automaticCaptureTask?.cancel()
        automaticCaptureTask = nil
        isAutomaticCaptureRunning = false
        statusText = "已停止自動擷取"
    }

    func captureAndRelay() {
        showsPermissionAction = false
        guard capturer.hasScreenCaptureAccess || capturer.requestScreenCaptureAccess() else {
            statusText = ScreenCaptureError.permissionDenied.localizedDescription
            showsPermissionAction = true
            return
        }

        statusText = "正在擷取 Mac 當前畫面..."
        Task {
            _ = await captureAndRelayNow()
        }
    }

    private func captureAndRelayNow() async -> Bool {
        do {
            let selectedTarget = captureTargets.first { $0.stableID == selectedTargetID }
            let frame = try await capturer.captureFrame(target: selectedTarget)
            capturedImage = NSImage(
                cgImage: frame.cgImage,
                size: NSSize(width: frame.width, height: frame.height)
            )
            let targetLabel = selectedTarget?.label ?? "主螢幕"
            lastCaptureDescription = "\(targetLabel) · \(frame.width) x \(frame.height) · \(frame.capturedAt.formatted(date: .omitted, time: .standard))"
            // 同一幀只切一次 tiles，植物分類器與枯萎分類器共用（兩個模型各跑各的）。
            let tiles = PlantImageClassifier.sceneTiles(in: frame.cgImage)
            let capturedAt = Date()
            let classification = classify(tiles: tiles, at: capturedAt)
            let wither = witherSummary(tiles: tiles, at: capturedAt)
            statusText = relayStatusText(for: classification)

            try relayClient.sendFrameResult(
                .successFrameCaptured(frame: frame, classification: classification, wither: wither)
            )
            statusText = sentStatusText(for: classification)
            return true
        } catch {
            statusText = error.localizedDescription
            showsPermissionAction = (error as? ScreenCaptureError) == .permissionDenied
            return !showsPermissionAction
        }
    }

    private func classify(tiles: [CGImage], at date: Date) -> PlantClassificationResult? {
        guard let plantClassifier else { return nil }
        let perFrame = try? plantClassifier.classifyScene(tiles: tiles)
        // 逐幀判定交給跨幀穩定器做多數決：自動串流時需近期多幀一致才改變輸出，
        // 兩類拉鋸時回 nil（不確定），避免在 天竺葵 / 馬纓丹 之間跳。
        return labelSmoother.record(perFrame, at: date)
    }

    /// 枯萎判定：對同一批 tiles 算枯萎面積比例（枯萎 ÷ 有植物的 tile），再跨幀取平均平滑。
    /// 與植物辨識互不相干；找不到模型或樣本不足時回 nil，payload 就不帶枯萎欄位。
    private func witherSummary(tiles: [CGImage], at date: Date) -> WitherSummary? {
        guard let witherClassifier else { return nil }
        let perFrameRatio = WitherScoreResolver.resolve(witherClassifier.classifyTiles(tiles))
        guard let smoothedRatio = witherSmoother.record(perFrameRatio, at: date) else { return nil }
        return WitherSummary(ratio: smoothedRatio)
    }

    private func relayStatusText(for classification: PlantClassificationResult?) -> String {
        if let classification {
            "已抽幀並辨識為 \(classification.label)，正在透過 Socket.IO relay 回傳 Vision Pro..."
        } else {
            "已抽幀，找不到可用模型或分類失敗，正在透過 Socket.IO relay 回傳 Vision Pro..."
        }
    }

    private func sentStatusText(for classification: PlantClassificationResult?) -> String {
        if let classification {
            "已送出 Socket.IO JSON：\(classification.label) \(Int(classification.confidence * 100))%"
        } else {
            "已送出 Socket.IO JSON：成功抽幀，Vision Pro 將使用 demo 結果"
        }
    }

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshCaptureTargets(requestPermissionIfNeeded: Bool = true) {
        showsPermissionAction = false
        guard ScreenFrameCapturer.canReadTargets(
            hasAccess: capturer.hasScreenCaptureAccess,
            requestPermissionIfNeeded: requestPermissionIfNeeded,
            requestAccess: capturer.requestScreenCaptureAccess
        ) else {
            statusText = ScreenCaptureError.permissionDenied.localizedDescription
            showsPermissionAction = true
            return
        }

        statusText = "正在讀取可擷取的螢幕與視窗..."
        Task {
            do {
                let targets = try await capturer.availableTargets()
                captureTargets = targets
                if !targets.contains(where: { $0.stableID == selectedTargetID }) {
                    selectedTargetID = targets.first?.stableID ?? ""
                }
                statusText = targets.isEmpty ? "找不到可擷取目標" : "已讀取 \(targets.count) 個擷取目標"
            } catch {
                statusText = error.localizedDescription
                showsPermissionAction = (error as? ScreenCaptureError) == .permissionDenied
            }
        }
    }

    func installAutomaticCaptureShortcutMonitor() {
        refreshShortcutAccessibilityStatus()

        if localModifierFlagsMonitor == nil {
            localModifierFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                Task { @MainActor in
                    self?.handleModifierFlagsChanged(event.modifierFlags.rawValue)
                }
                return event
            }
        }

        guard globalModifierFlagsMonitor == nil else { return }
        globalModifierFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleModifierFlagsChanged(event.modifierFlags.rawValue)
            }
        }
    }

    func removeAutomaticCaptureShortcutMonitor() {
        if let localModifierFlagsMonitor {
            NSEvent.removeMonitor(localModifierFlagsMonitor)
            self.localModifierFlagsMonitor = nil
        }
        if let globalModifierFlagsMonitor {
            NSEvent.removeMonitor(globalModifierFlagsMonitor)
            self.globalModifierFlagsMonitor = nil
        }
        activeCaptureShortcutAction = nil
    }

    func refreshShortcutAccessibilityStatus() {
        if AXIsProcessTrusted() {
            shortcutPermissionText = "全域快捷鍵已啟用：左右 Option 開始，左 Option + 右 Command 停止"
            showsAccessibilityAction = false
        } else {
            shortcutPermissionText = "全域快捷鍵需要在 macOS 輔助使用權限中允許 MacFrameRelayApp"
            showsAccessibilityAction = true
        }
    }

    private func handleModifierFlagsChanged(_ rawValue: UInt) {
        let action: CaptureShortcutAction?
        if FrameRelayCaptureShortcut.shouldStopAutomaticCapture(modifierFlagsRawValue: rawValue) {
            action = .stop
        } else if FrameRelayCaptureShortcut.shouldStartAutomaticCapture(modifierFlagsRawValue: rawValue) {
            action = .start
        } else {
            action = nil
        }

        guard action != activeCaptureShortcutAction else { return }
        activeCaptureShortcutAction = action

        switch action {
        case .start:
            startAutomaticCapture()
        case .stop:
            stopAutomaticCapture()
        case nil:
            break
        }
    }

    private enum CaptureShortcutAction {
        case start
        case stop
    }
}

private struct FrameRelayView: View {
    @StateObject private var viewModel = FrameRelayViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear {
            viewModel.installAutomaticCaptureShortcutMonitor()
        }
        .onDisappear {
            viewModel.removeAutomaticCaptureShortcutMonitor()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PlantVision Mac Frame Relay")
                    .font(.title2.weight(.semibold))
                Text(viewModel.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.toggleAutomaticCapture()
            } label: {
                Label(
                    viewModel.isAutomaticCaptureRunning ? "停止自動擷取" : "開始自動擷取",
                    systemImage: viewModel.isAutomaticCaptureRunning ? "stop.circle" : "camera.viewfinder"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
    }

    private var content: some View {
        HStack(spacing: 0) {
            previewPane
            Divider()
            controlPane
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("抽出的畫面幀")
                .font(.headline)

            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))

                if let capturedImage = viewModel.capturedImage {
                    Image(nsImage: capturedImage)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "display")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                        Text("尚未擷取")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }

            Text(viewModel.lastCaptureDescription)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var controlPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Socket.IO Relay")
                .font(.headline)

            Text(viewModel.relayStatus)
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Relay URL", text: $viewModel.relayURL)
                .textFieldStyle(.roundedBorder)

            TextField("配對碼", text: $viewModel.pairingCode)
                .textFieldStyle(.roundedBorder)

            Button {
                viewModel.connectRelay()
            } label: {
                Label("連線 Relay", systemImage: "link")
            }

            Divider()

            Text("擷取目標")
                .font(.headline)

            Picker("擷取目標", selection: $viewModel.selectedTargetID) {
                if viewModel.captureTargets.isEmpty {
                    Text("尚未讀取目標").tag("")
                }
                ForEach(viewModel.captureTargets) { target in
                    Text(target.label).tag(target.stableID)
                }
            }
            .disabled(viewModel.isAutomaticCaptureRunning)

            Button {
                viewModel.refreshCaptureTargets(requestPermissionIfNeeded: true)
            } label: {
                Label("重新整理目標", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isAutomaticCaptureRunning)

            Divider()

            Label("Mac 與 Vision Pro 都連到同一個 relay，並使用相同配對碼。抽幀成功後，Mac 會 emit frameResult JSON，message 為「成功抽幀」。", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)

            if viewModel.showsPermissionAction {
                Button {
                    viewModel.openScreenCaptureSettings()
                } label: {
                    Label("開啟螢幕錄製權限", systemImage: "gear")
                }
            }

            Label(viewModel.shortcutPermissionText, systemImage: "keyboard")
                .font(.callout)
                .foregroundStyle(.secondary)

            if viewModel.showsAccessibilityAction {
                Button {
                    viewModel.openAccessibilitySettings()
                } label: {
                    Label("開啟輔助使用權限", systemImage: "accessibility")
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 300, alignment: .topLeading)
    }
}

@MainActor
private final class SocketIORelayClient {
    var onStatusChange: ((String) -> Void)?

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var pairingCode = ""

    func connect(relayURL: URL, pairingCode: String) {
        disconnect()
        self.pairingCode = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)

        let manager = SocketManager(
            socketURL: relayURL,
            config: [
                .log(false),
                .compress,
                .forceWebsockets(true),
                .reconnects(true)
            ]
        )
        let socket = manager.defaultSocket
        self.manager = manager
        self.socket = socket

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.onStatusChange?("已連線 relay，正在加入配對碼 \(self.pairingCode)")
                socket.emit("join", ["role": "mac", "code": self.pairingCode])
            }
        }

        socket.on("joined") { [weak self] data, _ in
            Task { @MainActor in
                let description = data.first.map { "\($0)" } ?? self?.pairingCode ?? ""
                self?.onStatusChange?("已加入 relay room：\(description)")
            }
        }

        socket.on("relayError") { [weak self] data, _ in
            Task { @MainActor in
                self?.onStatusChange?("Relay error：\(data.first ?? "unknown")")
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            Task { @MainActor in
                self?.onStatusChange?("Relay 已斷線：\(data.first ?? "")")
            }
        }

        socket.on(clientEvent: .error) { [weak self] data, _ in
            Task { @MainActor in
                self?.onStatusChange?("Relay 連線錯誤：\(data.first ?? "unknown")")
            }
        }

        onStatusChange?("正在連線 relay：\(relayURL.absoluteString)")
        socket.connect()
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        manager = nil
    }

    func sendFrameResult(_ message: FrameRelayMessage) throws {
        guard let socket, socket.status == .connected else {
            throw RelayClientError.notConnected
        }

        guard let payload = try JSONSerialization.jsonObject(with: message.jsonPayload) as? [String: Any] else {
            throw RelayClientError.invalidPayload
        }
        socket.emit("frameResult", payload)
    }
}

private enum RelayClientError: LocalizedError {
    case invalidPayload
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            "Socket.IO relay payload 不是 JSON object"
        case .notConnected:
            "Socket.IO relay 尚未連線"
        }
    }
}
