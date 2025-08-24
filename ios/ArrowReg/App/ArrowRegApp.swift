import SwiftUI

@main
struct ArrowRegApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var networkMonitor = NetworkMonitor()
    
    init() {
        setupAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(networkMonitor)
                .onAppear {
                    setupApp()
                }
        }
    }
    
    private func setupAppearance() {
        // Configure for dark mode but let system handle it naturally
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        
        // Let the system handle tab bar appearance naturally
        UITabBar.appearance().backgroundColor = nil
    }
    
    private func setupApp() {
        // Request notification permissions if needed
        // Initialize any required services
        print("ArrowReg app launched successfully")
    }
}
