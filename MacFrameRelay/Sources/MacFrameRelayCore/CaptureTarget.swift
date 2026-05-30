import Foundation

public enum CaptureTarget: Equatable, Identifiable, Sendable {
    case display(id: UInt32, title: String, width: Int, height: Int)
    case window(id: UInt32, title: String, ownerName: String)

    public var id: String {
        stableID
    }

    public var stableID: String {
        switch self {
        case .display(let id, _, _, _):
            "display-\(id)"
        case .window(let id, _, _):
            "window-\(id)"
        }
    }

    public var label: String {
        switch self {
        case .display(_, let title, let width, let height):
            "螢幕：\(title) (\(width) x \(height))"
        case .window(_, let title, let ownerName):
            if ownerName.isEmpty {
                "視窗：\(title)"
            } else if title.isEmpty {
                "視窗：\(ownerName)"
            } else {
                "視窗：\(ownerName) - \(title)"
            }
        }
    }

    public static func isListableWindow(isOnScreen: Bool, title: String?, ownerName: String?) -> Bool {
        guard isOnScreen else { return false }
        let hasTitle = !(title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasOwnerName = !(ownerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle || hasOwnerName
    }
}
