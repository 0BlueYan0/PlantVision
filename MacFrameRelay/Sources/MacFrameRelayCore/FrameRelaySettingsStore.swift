import Foundation

public final class FrameRelaySettingsStore {
    public static let defaultRelayURL = "http://127.0.0.1:8080"
    public static let defaultPairingCode = "482913"

    private enum Key {
        static let relayURL = "MacFrameRelay.relayURL"
        static let pairingCode = "MacFrameRelay.pairingCode"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var relayURL: String {
        get {
            defaults.string(forKey: Key.relayURL) ?? Self.defaultRelayURL
        }
        set {
            defaults.set(newValue, forKey: Key.relayURL)
        }
    }

    public var pairingCode: String {
        get {
            defaults.string(forKey: Key.pairingCode) ?? Self.defaultPairingCode
        }
        set {
            defaults.set(newValue, forKey: Key.pairingCode)
        }
    }
}
