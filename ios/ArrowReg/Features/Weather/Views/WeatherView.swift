import SwiftUI
import CoreLocation

struct WeatherView: View {
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var preferences = WeatherPreferences.shared
    @State private var showingLocationSearch = false
    @State private var selectedLocation: WeatherLocation?
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if weatherService.isLoading {
                    loadingView
                } else if let weatherData = weatherService.currentWeatherData {
                    weatherContentView(weatherData)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle(weatherService.currentWeatherData?.location.name ?? "Weather")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Units", selection: $preferences.units) {
                            ForEach(WeatherUnit.allCases, id: \.self) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.automatic)
                    } label: {
                        HStack(spacing: 4) {
                            Text(preferences.units.temperatureSymbol)
                                .font(.caption)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Current Location", systemImage: "location") {
                            weatherService.getCurrentLocationWeather()
                        }
                        
                        Button("Search Location", systemImage: "magnifyingglass") {
                            showingLocationSearch = true
                        }
                        
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            if let location = weatherService.currentWeatherData?.location {
                                Task {
                                    try? await weatherService.fetchWeather(
                                        for: location.coordinate,
                                        locationName: location.name
                                    )
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingLocationSearch) {
                LocationSearchView { location in
                    selectedLocation = location
                    Task {
                        try? await weatherService.fetchWeather(
                            for: location.coordinate,
                            locationName: location.name
                        )
                    }
                }
            }
            .alert("Weather Error", isPresented: .constant(weatherService.error != nil)) {
                Button("OK") {
                    weatherService.error = nil
                }
            } message: {
                Text(weatherService.error?.localizedDescription ?? "Unknown error")
            }
            .onAppear {
                if weatherService.currentWeatherData == nil {
                    weatherService.getCurrentLocationWeather()
                }
            }
            .onChange(of: preferences.units) { _, newUnits in
                // Refresh weather data when units change to get data in correct units from API
                if let location = weatherService.currentWeatherData?.location {
                    Task {
                        try? await weatherService.fetchWeather(
                            for: location.coordinate,
                            locationName: location.name
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading weather data...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "cloud.sun")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 12) {
                Text("Maritime Weather")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Get detailed weather conditions including waves, wind, and visibility for safe maritime operations")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    weatherService.getCurrentLocationWeather()
                }) {
                    Label("Use Current Location", systemImage: "location.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    showingLocationSearch = true
                }) {
                    Label("Search Location", systemImage: "magnifyingglass")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    private func weatherContentView(_ weatherData: MaritimeWeatherData) -> some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Location header
                locationHeader(weatherData.location)
                
                // Current conditions
                currentWeatherCard(weatherData.current)
                
                // Sea state and suitability
                seaStateCard(weatherData.current)
                
                // Hourly forecast
                hourlyForecastSection(weatherData.hourlyForecast)
                
                // Daily forecast
                dailyForecastSection(weatherData.dailyForecast)
                
                // Additional details
                detailsCard(weatherData.current)
            }
            .padding()
        }
    }
    
    private func locationHeader(_ location: WeatherLocation) -> some View {
        VStack(spacing: 8) {
            if let country = location.country {
                Text(country)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("Updated \(weatherService.currentWeatherData?.lastUpdated.formatted(date: .omitted, time: .shortened) ?? "")")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Ventusky comparison link
            Button(action: {
                weatherService.openVentusky(for: location)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                    Text("Compare to Ventusky")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
    
    private func currentWeatherCard(_ current: CurrentWeather) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        if let temp = current.temperature {
                            Text("\(Int(temp.rounded()))")
                                .font(.system(size: 48, weight: .thin))
                            Text(preferences.units.temperatureSymbol)
                                .font(.title2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("--")
                                .font(.system(size: 48, weight: .thin))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(weatherService.formatWindSpeed(current.windSpeedKnots))
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(weatherService.formatWaveHeight(current.waveHeight))
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Wave Height")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let windDir = current.windDirection {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(weatherService.formatWindDirection(windDir))
                                .font(.title3)
                                .fontWeight(.medium)
                            Text("Wind")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    
    private func seaStateCard(_ current: CurrentWeather) -> some View {
        let seaState = weatherService.getSeaState(for: current.waveHeight ?? 0.0)
        let suitability = weatherService.isWeatherSuitableForOperation(weather: current)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Operational Conditions")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sea State")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(seaState.description)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(Color(hex: seaState.color) ?? .primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Suitability")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(suitability.severity.description)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(Color(hex: suitability.severity.color) ?? .primary)
                }
            }
            
            if !suitability.factors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Concerns:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    ForEach(suitability.factors, id: \.self) { factor in
                        Text("• \(factor)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    
    private func hourlyForecastSection(_ hourlyData: [HourlyWeather]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("24-Hour Forecast")
                .font(.headline)
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(hourlyData.prefix(24).enumerated()), id: \.offset) { _, hour in
                        HourlyWeatherCard(weather: hour, preferences: preferences)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private func dailyForecastSection(_ dailyData: [DailyWeather]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("7-Day Forecast")
                .font(.headline)
            
            ForEach(Array(dailyData.enumerated()), id: \.offset) { _, day in
                DailyWeatherRow(weather: day, preferences: preferences)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    
    private func detailsCard(_ current: CurrentWeather) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                if let pressure = current.pressure {
                    DetailItem(title: "Pressure", value: "\(Int(pressure)) hPa", icon: "barometer")
                }
                
                DetailItem(title: "Visibility", value: weatherService.formatVisibility(current.visibility), icon: "eye")
                
                DetailItem(title: "Wind Speed", value: weatherService.formatWindSpeed(current.windSpeed), icon: "wind")
                
                DetailItem(title: "Wave Height", value: weatherService.formatWaveHeight(current.waveHeight), icon: "water.waves")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

// MARK: - Supporting Views

struct HourlyWeatherCard: View {
    let weather: HourlyWeather
    let preferences: WeatherPreferences
    
    var body: some View {
        VStack(spacing: 8) {
            Text(weather.time.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let temp = weather.temperature {
                Text("\(Int(temp.rounded()))\(preferences.units.temperatureSymbol)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            } else {
                Text("--")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            VStack(spacing: 2) {
                if let waveHeight = weather.waveHeight {
                    let heightText = preferences.units == .metric ? 
                        "\(String(format: "%.1f", waveHeight))m" : 
                        "\(String(format: "%.1f", waveHeight * 3.28084))ft"
                    Text(heightText)
                        .font(.caption)
                        .fontWeight(.medium)
                } else {
                    Text("--")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                Text("waves")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let windSpeed = weather.windSpeedKnots {
                let speedText = preferences.units == .metric ? 
                    "\(Int((windSpeed / 0.539957).rounded())) \(preferences.units.speedUnit)" : 
                    "\(Int(windSpeed.rounded())) kts"
                Text(speedText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .frame(minWidth: 80)
    }
}

struct DailyWeatherRow: View {
    let weather: DailyWeather
    let preferences: WeatherPreferences
    
    var body: some View {
        HStack {
            Text(weather.date.formatted(.dateTime.weekday(.wide)))
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if let waveMax = weather.waveHeightMax {
                    let heightText = preferences.units == .metric ? 
                        "\(String(format: "%.1f", waveMax))m" : 
                        "\(String(format: "%.1f", waveMax * 3.28084))ft"
                    Text(heightText)
                        .font(.subheadline)
                } else {
                    Text("--")
                        .font(.subheadline)
                }
                Text("waves")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 50)
            
            VStack(alignment: .trailing, spacing: 2) {
                if let windMax = weather.windSpeedMaxKnots {
                    let speedText = preferences.units == .metric ? 
                        "\(Int((windMax / 0.539957).rounded())) \(preferences.units.speedUnit)" : 
                        "\(Int(windMax.rounded())) kts"
                    Text(speedText)
                        .font(.subheadline)
                } else {
                    Text("--")
                        .font(.subheadline)
                }
                Text("wind")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 40)
            
            if let tempMax = weather.temperatureMax, let tempMin = weather.temperatureMin {
                HStack(spacing: 4) {
                    Text("\(Int(tempMax.rounded()))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("/")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(Int(tempMin.rounded()))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(preferences.units.temperatureSymbol)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DetailItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [WeatherLocation] = []
    @State private var isSearching = false
    
    let onLocationSelected: (WeatherLocation) -> Void
    
    var body: some View {
        NavigationStack {
            VStack {
                SearchBar(text: $searchText, onSearchButtonClicked: performSearch)
                
                if isSearching {
                    ProgressView()
                        .padding()
                    Spacer()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    Text("No locations found")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    List(searchResults, id: \.name) { location in
                        Button(action: {
                            onLocationSelected(location)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                if let country = location.country {
                                    Text(country)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isSearching = true
        
        Task {
            do {
                let results = try await WeatherService.shared.searchLocations(searchText)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let onSearchButtonClicked: () -> Void
    
    var body: some View {
        HStack {
            TextField("Search for a location...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    onSearchButtonClicked()
                }
            
            Button("Search", action: onSearchButtonClicked)
                .disabled(text.isEmpty)
        }
        .padding()
    }
}

// MARK: - Extensions

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    WeatherView()
}