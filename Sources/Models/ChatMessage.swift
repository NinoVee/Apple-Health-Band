import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let content: String
    /// JPEG bytes, if a photo was attached. Kept in memory only — chat
    /// history isn't persisted, so this doesn't add new storage exposure.
    var imageData: Data? = nil
    let timestamp: Date = .now
}
