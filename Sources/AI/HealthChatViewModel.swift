import Foundation

/// Drives the AI Insights chat: builds the Health summary, sends it plus
/// the conversation to the relay on each message, and appends the reply.
/// Reads provider/URL/secret fresh from `AIInsightsSettings` on every
/// send, so changes made in Settings apply to the very next message.
@MainActor
final class HealthChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var pendingImageData: Data?
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private let client = HealthInsightsRelayClient()
    private let healthKit: HealthKitManager
    private let bluetooth: BandBluetoothManager
    private let coordinator: ActivitySyncCoordinator
    private let scaleLog: ScaleLogStore

    init(healthKit: HealthKitManager, bluetooth: BandBluetoothManager, coordinator: ActivitySyncCoordinator, scaleLog: ScaleLogStore) {
        self.healthKit = healthKit
        self.bluetooth = bluetooth
        self.coordinator = coordinator
        self.scaleLog = scaleLog
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImageData != nil, !isSending else { return }
        guard let url = URL(string: AIInsightsSettings.relayURLString) else {
            errorMessage = "Set a valid Relay URL in Settings → AI Insights first."
            return
        }

        messages.append(ChatMessage(role: .user, content: text, imageData: pendingImageData))
        draft = ""
        pendingImageData = nil
        errorMessage = nil
        isSending = true

        let provider = AIInsightsSettings.provider
        let sharedSecret = AIInsightsSettings.sharedSecret
        let context = HealthContextBuilder.summary(healthKit: healthKit, bluetooth: bluetooth, coordinator: coordinator, scaleLog: scaleLog)
        let conversation = messages

        Task {
            do {
                let reply = try await client.sendMessage(
                    provider: provider,
                    relayURL: url,
                    sharedSecret: sharedSecret,
                    healthContext: context,
                    conversation: conversation
                )
                messages.append(ChatMessage(role: .assistant, content: reply))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    func clear() {
        messages.removeAll()
        errorMessage = nil
    }
}
