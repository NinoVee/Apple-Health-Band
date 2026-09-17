import Foundation

struct RelayClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to *your own* relay server (see `Server/` in this repo), never
/// to Anthropic or OpenAI directly — the relay is what holds the actual
/// API key. `sharedSecret` is a weaker, app-side secret that just keeps
/// random internet traffic off your relay; see Server/README.md.
final class HealthInsightsRelayClient {
    func sendMessage(
        provider: AIProvider,
        relayURL: URL,
        sharedSecret: String,
        healthContext: String,
        conversation: [ChatMessage]
    ) async throws -> String {
        var request = URLRequest(url: relayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !sharedSecret.isEmpty {
            request.setValue(sharedSecret, forHTTPHeaderField: "X-App-Secret")
        }

        let payload: [String: Any] = [
            "provider": provider.rawValue,
            "healthContext": healthContext,
            "messages": conversation.map { message -> [String: Any] in
                var dict: [String: Any] = ["role": message.role.rawValue, "content": message.content]
                if let imageData = message.imageData {
                    dict["imageBase64"] = imageData.base64EncodedString()
                }
                return dict
            }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RelayClientError(message: "No response from relay server.")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RelayClientError(message: "Relay returned \(http.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(RelayResponse.self, from: data)
        return decoded.reply
    }

    private struct RelayResponse: Decodable {
        let reply: String
    }
}
