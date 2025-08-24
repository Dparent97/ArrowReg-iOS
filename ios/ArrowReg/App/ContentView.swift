import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
                            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(Tab.search)
            
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "globe.americas.fill")
                }
                .tag(Tab.discover)
            
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(Tab.library)
            
            WeatherView()
                .tabItem {
                    Label("Weather", systemImage: "cloud.sun")
                }
                .tag(Tab.weather)
        }
        .environmentObject(appState)
        .preferredColorScheme(.dark)
        .onAppear {
            setupAppearance()
        }
    }
    
    private func setupAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
}