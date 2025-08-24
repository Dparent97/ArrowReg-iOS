import Foundation

final class BookmarkService {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save<T: Codable>(_ item: T, forKey key: String) {
        var existing = defaults.array(forKey: key) as? [Data] ?? []
        if let data = try? encoder.encode(item) {
            existing.append(data)
            defaults.set(existing, forKey: key)
        }
    }

    func load<T: Codable>(forKey key: String) -> [T] {
        guard let dataArray = defaults.array(forKey: key) as? [Data] else {
            return []
        }
        return dataArray.compactMap { try? decoder.decode(T.self, from: $0) }
    }
}

