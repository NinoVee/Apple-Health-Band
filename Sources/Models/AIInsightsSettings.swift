import Foundation

/// Read-only accessors over the same UserDefaults keys `SettingsView`'s
/// `@AppStorage` properties write to, so non-View code (the chat view
/// model, the relay client call site) can read the current values
/// without needing a View context.
enum AIInsightsSettings {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "aiInsightsEnabled")
    }

    static var provider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? AIProvider.claude.rawValue) ?? .claude
    }

    static var relayURLString: String {
        UserDefaults.standard.string(forKey: "aiRelayURL") ?? ""
    }

    static var sharedSecret: String {
        UserDefaults.standard.string(forKey: "aiSharedSecret") ?? ""
    }
}
