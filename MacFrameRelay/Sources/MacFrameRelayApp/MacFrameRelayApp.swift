import SwiftUI
import MacFrameRelayCore
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
        showWindow()
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
    @Published var relayURL = "http://127.0.0.1:8080"
    @Published var pairingCode = "482913"
    @Published var relayStatus = "Socket.IO 尚未連線"
    @Published var lastCaptureDescription = "等待 Vision Pro 鏡像畫面顯示於 Mac 螢幕"
    @Published var showsPermissionAction = false
    @Published var captureTargets: [CaptureTarget] = []
    @Published var selectedTargetID = ""

    private let capturer = ScreenFrameCapturer()
    private let relayClient = SocketIORelayClient()

    init() {
        relayClient.onStatusChange = { [weak self] status in
            self?.relayStatus = status
        }
        refreshCaptureTargets()
    }

    func connectRelay() {
        guard let url = URL(string: relayURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            relayStatus = "Relay URL 無效"
            return
        }

        relayClient.connect(relayURL: url, pairingCode: pairingCode)
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
            await captureAndRelayNow()
        }
    }

    private func captureAndRelayNow() async {
        do {
            let selectedTarget = captureTargets.first { $0.stableID == selectedTargetID }
            let frame = try await capturer.captureFrame(target: selectedTarget)
            capturedImage = NSImage(
                cgImage: frame.cgImage,
                size: NSSize(width: frame.width, height: frame.height)
            )
            let targetLabel = selectedTarget?.label ?? "主螢幕"
            lastCaptureDescription = "\(targetLabel) · \(frame.width) x \(frame.height) · \(frame.capturedAt.formatted(date: .omitted, time: .standard))"
            statusText = "已抽幀，正在透過 Socket.IO relay 回傳 Vision Pro..."

            try relayClient.sendFrameResult(.successFrameCaptured(frame: frame))
            statusText = "已送出 Socket.IO JSON：成功抽幀"
        } catch {
            statusText = error.localizedDescription
            showsPermissionAction = (error as? ScreenCaptureError) == .permissionDenied
        }
    }

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshCaptureTargets() {
        showsPermissionAction = false
        guard capturer.hasScreenCaptureAccess || capturer.requestScreenCaptureAccess() else {
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
}

private struct FrameRelayView: View {
    @StateObject private var viewModel = FrameRelayViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
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
                viewModel.captureAndRelay()
            } label: {
                Label("擷取當前畫面", systemImage: "camera.viewfinder")
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

            Button {
                viewModel.refreshCaptureTargets()
            } label: {
                Label("重新整理目標", systemImage: "arrow.clockwise")
            }

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
