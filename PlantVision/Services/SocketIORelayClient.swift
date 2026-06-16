import Foundation

struct RelayFramePayload: Equatable {
    let message: String
    let type: String?
    let frameWidth: Int?
    let frameHeight: Int?
    let plantID: String?
    let confidence: Double?
    /// 枯萎面積比例（0–1）與等級。皆為可選——舊版 Mac 不會帶這兩個欄位，缺值不可崩潰。
    let witherRatio: Double?
    let witherLevel: Int?
}

enum RelayClientStatus: Equatable {
    case disconnected
    case connecting(URL)
    case connected
    case joined(String)
    case failed(String)

    var message: String {
        switch self {
        case .disconnected:
            "尚未連線 Socket.IO relay"
        case .connecting(let url):
            "正在連線 relay：\(url.absoluteString)"
        case .connected:
            "已連線 relay，正在加入配對碼"
        case .joined(let code):
            "已加入 relay room：\(code)"
        case .failed(let reason):
            "Relay 連線失敗：\(reason)"
        }
    }
}

enum SocketIORelayClientError: LocalizedError {
    case invalidRelayURL
    case malformedSocketIOEvent

    var errorDescription: String? {
        switch self {
        case .invalidRelayURL:
            "Relay URL 無效"
        case .malformedSocketIOEvent:
            "Socket.IO event 格式無效"
        }
    }
}

final class SocketIORelayClient {
    var onStatusChange: ((RelayClientStatus) -> Void)?
    var onFramePayload: ((RelayFramePayload) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var pairingCode = ""
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(relayURL: URL, pairingCode: String) throws {
        disconnect()

        let socketURL = try Self.socketURL(from: relayURL)
        self.pairingCode = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        onStatusChange?(.connecting(socketURL))

        let task = session.webSocketTask(with: socketURL)
        self.task = task
        task.resume()
        receiveNextMessage()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onStatusChange?(.disconnected)
    }

    static func socketURL(from relayURL: URL) throws -> URL {
        guard var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false) else {
            throw SocketIORelayClientError.invalidRelayURL
        }

        switch components.scheme {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            throw SocketIORelayClientError.invalidRelayURL
        }

        components.path = "/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]

        guard let url = components.url else {
            throw SocketIORelayClientError.invalidRelayURL
        }
        return url
    }

    private func receiveNextMessage() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveNextMessage()
            case .failure(let error):
                self.onStatusChange?(.failed(error.localizedDescription))
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleSocketIOPacket(text)
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else { return }
            handleSocketIOPacket(text)
        @unknown default:
            break
        }
    }

    private func handleSocketIOPacket(_ packet: String) {
        if packet.hasPrefix("0") {
            send("40")
            onStatusChange?(.connected)
            return
        }

        if packet == "2" {
            send("3")
            return
        }

        if packet.hasPrefix("40") {
            emitJoin()
            return
        }

        guard packet.hasPrefix("42") else { return }

        do {
            let event = try Self.parseEventPacket(packet)
            switch event.name {
            case "joined":
                if let code = event.payload["code"] as? String {
                    onStatusChange?(.joined(code))
                }
            case "plantVisionRelay":
                if let payload = Self.parseFramePayload(from: event.payload) {
                    onFramePayload?(payload)
                }
            default:
                break
            }
        } catch {
            onStatusChange?(.failed(error.localizedDescription))
        }
    }

    private func emitJoin() {
        let payload: [Any] = [
            "join",
            [
                "role": "vision",
                "code": pairingCode
            ]
        ]
        emit(payload)
    }

    private func emit(_ payload: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        send("42\(json)")
    }

    private func send(_ text: String) {
        task?.send(.string(text)) { [weak self] error in
            if let error {
                self?.onStatusChange?(.failed(error.localizedDescription))
            }
        }
    }

    static func parseEventPacket(_ packet: String) throws -> (name: String, payload: [String: Any]) {
        guard packet.hasPrefix("42") else {
            throw SocketIORelayClientError.malformedSocketIOEvent
        }

        let jsonStart = packet.index(packet.startIndex, offsetBy: 2)
        let jsonText = String(packet[jsonStart...])
        guard let data = jsonText.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [Any],
              let name = array.first as? String,
              let payload = array.dropFirst().first as? [String: Any] else {
            throw SocketIORelayClientError.malformedSocketIOEvent
        }

        return (name, payload)
    }

    static func parseFramePayload(from relayPayload: [String: Any]) -> RelayFramePayload? {
        guard let data = relayPayload["data"] as? [String: Any],
              let message = data["message"] as? String else {
            return nil
        }

        return RelayFramePayload(
            message: message,
            type: data["type"] as? String,
            frameWidth: data["frameWidth"] as? Int,
            frameHeight: data["frameHeight"] as? Int,
            plantID: data["plantID"] as? String,
            confidence: data["confidence"] as? Double,
            // 可選欄位：舊端不帶時為 nil，不影響既有解析。
            witherRatio: data["witherRatio"] as? Double,
            witherLevel: data["witherLevel"] as? Int
        )
    }
}
