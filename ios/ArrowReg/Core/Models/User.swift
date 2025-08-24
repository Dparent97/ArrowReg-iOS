import Foundation

struct User: Codable, Identifiable {
    let id: UUID
    let email: String
    let name: String
    let createdAt: Date
    let preferences: UserPreferences
    
    init(id: UUID = UUID(), email: String, name: String, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.name = name
        self.createdAt = createdAt
        self.preferences = UserPreferences()
    }
}

struct UserPreferences: Codable {
    var searchHistoryEnabled: Bool = true
    var notificationsEnabled: Bool = true
    var preferredSources: [RegulationSource] = [.cfr33, .cfr46]
    var darkModePreference: DarkModePreference = .system
    
    enum DarkModePreference: String, Codable, CaseIterable {
        case light = "light"
        case dark = "dark"
        case system = "system"
        
        var displayName: String {
            switch self {
            case .light: return "Light"
            case .dark: return "Dark"
            case .system: return "System"
            }
        }
    }
}

enum RegulationSource: String, Codable, CaseIterable {
    case cfr33 = "33_cfr"
    case cfr46 = "46_cfr"
    case abs = "abs"
    case nvic = "nvic"
    
    var displayName: String {
        switch self {
        case .cfr33: return "33 CFR"
        case .cfr46: return "46 CFR"
        case .abs: return "ABS Rules"
        case .nvic: return "NVIC"
        }
    }
}