import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isOnline = true
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var appVersion = "1.0.0"
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupNetworkMonitoring()
        loadUserSession()
    }
    
    private func setupNetworkMonitoring() {
        // Network monitoring will be implemented later
    }
    
    private func loadUserSession() {
        // Load saved user session if any
        // For now, set as authenticated for development
        isAuthenticated = true
    }
    
    func signOut() {
        currentUser = nil
        isAuthenticated = false
        // Clear any cached data
    }
}