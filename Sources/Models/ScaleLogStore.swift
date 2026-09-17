import Foundation

@MainActor
final class ScaleLogStore: ObservableObject {
    @Published private(set) var entries: [ScaleEntry] = [] {
        didSet { persist() }
    }

    private let defaultsKey = "scaleLogEntries"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([ScaleEntry].self, from: data) {
            entries = decoded.sorted { $0.date > $1.date }
        }
    }

    func add(_ entry: ScaleEntry) {
        entries.append(entry)
        entries.sort { $0.date > $1.date }
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    var latest: ScaleEntry? { entries.first }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
