import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(0)
            
            WeatherView()
                .tabItem {
                    Label("Weather", systemImage: "cloud.sun")
                }
                .tag(1)
            
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "newspaper")
                }
                .tag(2)
            
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(3)
        }
        .accentColor(.blue)
        .overlay(alignment: .top) {
            // Network status indicator
            if !networkMonitor.isConnected {
                HStack {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("Offline Mode")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .cornerRadius(20)
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(NetworkMonitor())
}
