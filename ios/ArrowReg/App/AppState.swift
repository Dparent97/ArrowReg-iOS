import SwiftUI
import Combine

enum Tab: String, CaseIterable {
    case search = "search"
    case discover = "discover"
    case library = "library"
    case weather = "weather"
}

@MainActor
class AppState: ObservableObject {
    @Published var selectedTab: Tab = .search
    @Published var isOnline = true
    @Published var user: User?
    @Published var showOnboarding = false
    
    private var networkMonitor: NetworkMonitor!
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        networkMonitor = NetworkMonitor.shared
        setupNetworkMonitoring()
        checkFirstLaunch()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: \AppState.isOnline, on: self)
            .store(in: &cancellables)
    }
    
    private func checkFirstLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "HasLaunchedBefore")
        if !hasLaunchedBefore {
            showOnboarding = true
            UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        }
    }
    
    func selectTab(_ tab: Tab) {
        selectedTab = tab
    }
}