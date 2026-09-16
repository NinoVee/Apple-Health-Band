import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case claude
    case chatgpt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        }
    }
}
