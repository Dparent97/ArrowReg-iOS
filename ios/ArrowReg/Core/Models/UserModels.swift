import Foundation

// MARK: - Shared Regulation Source (also defined in SearchModels.swift)
enum RegulationSource: String, CaseIterable, Codable {
    case cfr33 = "33CFR"
    case cfr46 = "46CFR"
    case nvic = "NVIC"
    case abs = "ABS"
    case imo = "IMO"
    
    var displayName: String {
        switch self {
        case .cfr33: return "33 CFR"
        case .cfr46: return "46 CFR"
        case .nvic: return "NVIC"
        case .abs: return "ABS Rules"
        case .imo: return "IMO"
        }
    }
    
    var description: String {
        switch self {
        case .cfr33: return "Navigation and Navigable Waters"
        case .cfr46: return "Shipping"
        case .nvic: return "Navigation and Vessel Inspection Circulars"
        case .abs: return "American Bureau of Shipping Rules"
        case .imo: return "International Maritime Organization"
        }
    }
}

struct User: Codable, Identifiable {
    let id: UUID
    var name: String
    var email: String
    var organization: String?
    var vesselType: VesselType?
    var preferences: UserPreferences
    var createdAt: Date
    var lastActiveAt: Date
    
    init(name: String, email: String, organization: String? = nil, vesselType: VesselType? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.organization = organization
        self.vesselType = vesselType
        self.preferences = UserPreferences()
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }
}

struct UserPreferences: Codable {
    var searchHistory: Bool = true
    var offlineMode: Bool = false
    var notifications: NotificationSettings = NotificationSettings()
    var weatherUnits: WeatherUnits = .metric
    var preferredSources: [RegulationSource] = RegulationSource.allCases
    var autoSync: Bool = true
    
    enum WeatherUnits: String, CaseIterable, Codable {
        case metric = "metric"
        case imperial = "imperial"
        
        var displayName: String {
            switch self {
            case .metric: return "Metric (°C, m/s)"
            case .imperial: return "Imperial (°F, mph)"
            }
        }
    }
}

struct NotificationSettings: Codable {
    var weatherAlerts: Bool = true
    var regulatoryUpdates: Bool = true
    var searchResults: Bool = false
    var systemUpdates: Bool = true
}

enum VesselType: String, CaseIterable, Codable {
    case osv = "osv"
    case supply = "supply"
    case crew = "crew"
    case anchor = "anchor"
    case dive = "dive"
    case tug = "tug"
    case cargo = "cargo"
    case passenger = "passenger"
    case fishing = "fishing"
    case research = "research"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .osv: return "Offshore Supply Vessel"
        case .supply: return "Supply Vessel"
        case .crew: return "Crew Boat"
        case .anchor: return "Anchor Handling"
        case .dive: return "Dive Support"
        case .tug: return "Tug Boat"
        case .cargo: return "Cargo Vessel"
        case .passenger: return "Passenger Vessel"
        case .fishing: return "Fishing Vessel"
        case .research: return "Research Vessel"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .osv, .supply: return "ferry"
        case .crew: return "figure.wave"
        case .anchor: return "anchor"
        case .dive: return "figure.swimming"
        case .tug: return "tugboat"
        case .cargo: return "shippingbox"
        case .passenger: return "person.3"
        case .fishing: return "fish"
        case .research: return "scope"
        case .other: return "boat"
        }
    }
}

// MARK: - User Session Management

@MainActor
class UserSession: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    private let userDefaultsKey = "CurrentUser"
    
    init() {
        loadUser()
    }
    
    func signIn(user: User) {
        currentUser = user
        isAuthenticated = true
        saveUser()
    }
    
    func signOut() {
        currentUser = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    func updateUser(_ user: User) {
        currentUser = user
        saveUser()
    }
    
    private func saveUser() {
        guard let user = currentUser else { return }
        
        do {
            let userData = try JSONEncoder().encode(user)
            UserDefaults.standard.set(userData, forKey: userDefaultsKey)
        } catch {
            Logger.app.error("Failed to save user: \(error)")
        }
    }
    
    private func loadUser() {
        guard let userData = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        
        do {
            let user = try JSONDecoder().decode(User.self, from: userData)
            currentUser = user
            isAuthenticated = true
        } catch {
            Logger.app.error("Failed to load user: \(error)")
        }
    }
}