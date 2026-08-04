import Foundation

public struct ReadingUserDictionaryStore {
    public static let userDefaultsKey = "reading.userDictionary.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [ReadingDictionaryEntry] {
        guard let data = defaults.data(forKey: Self.userDefaultsKey),
              let entries = try? JSONDecoder().decode([ReadingDictionaryEntry].self, from: data) else { return [] }
        return entries
    }

    public func save(_ entries: [ReadingDictionaryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    public func upsert(_ entry: ReadingDictionaryEntry) {
        var entries = load()
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        save(entries.sorted { $0.priority > $1.priority })
    }

    public func remove(id: UUID) {
        save(load().filter { $0.id != id })
    }
}
