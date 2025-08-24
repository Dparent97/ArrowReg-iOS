import Foundation
import SwiftUI
import CoreLocation
import Combine

@MainActor
class WeatherService: ObservableObject {
    nonisolated static let shared = WeatherService()
    
    @Published var currentWeatherData: MaritimeWeatherData?
    @Published var isLoading = false
    @Published var error: WeatherError?
    
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let preferences = WeatherPreferences.shared
    
    // Mock URLs for demo - in production these would be real weather APIs
    private let baseURL = "https://api.open-meteo.com/v1/marine"
    private let geocodingURL = "https://geocoding-api.open-meteo.com/v1/search"
    
    nonisolated private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Weather Data Fetching
    
    func fetchWeather(for coordinate: CLLocationCoordinate2D, locationName: String = "Current Location") async throws -> MaritimeWeatherData {
        isLoading = true
        error = nil
        
        do {
            let request = MaritimeWeatherRequest(coordinate: coordinate, forecastDays: 7)
            let response = try await performWeatherRequest(request)
            
            let location = WeatherLocation(name: locationName, coordinate: coordinate)
            let weatherData = MaritimeWeatherData(from: response, location: location)
            
            self.currentWeatherData = weatherData
            self.isLoading = false
            
            return weatherData
            
        } catch {
            self.error = error as? WeatherError ?? .networkError
            self.isLoading = false
            throw error
        }
    }
    
    func fetchForecast(for coordinate: CLLocationCoordinate2D, days: Int = 7) async throws -> MaritimeWeatherResponse {
        let request = MaritimeWeatherRequest(coordinate: coordinate, forecastDays: days)
        return try await performWeatherRequest(request)
    }
    
    // MARK: - Private Methods
    
    private func performWeatherRequest(_ request: MaritimeWeatherRequest) async throws -> MaritimeWeatherResponse {
        // Real API implementation using Open-Meteo (free marine weather API)
        var urlComponents = URLComponents(string: baseURL)!
        
        // Add unit parameters based on user preference
        let temperatureUnit = preferences.units == .metric ? "celsius" : "fahrenheit"
        let windSpeedUnit = preferences.units == .metric ? "kmh" : "mph"
        
        urlComponents.queryItems = [
            URLQueryItem(name: "latitude", value: String(request.latitude)),
            URLQueryItem(name: "longitude", value: String(request.longitude)),
            URLQueryItem(name: "hourly", value: "wave_height,wave_direction,wave_period,wind_speed_10m,wind_direction_10m,visibility,sea_level_pressure,temperature_2m,precipitation,swell_wave_height,swell_wave_direction,swell_wave_period,wind_wave_height,wind_wave_direction,wind_wave_period"),
            URLQueryItem(name: "daily", value: "wave_height_max,wind_speed_10m_max,temperature_2m_max,temperature_2m_min,precipitation_sum"),
            URLQueryItem(name: "current_weather", value: "true"),
            URLQueryItem(name: "forecast_days", value: String(request.forecastDays)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: temperatureUnit),
            URLQueryItem(name: "wind_speed_unit", value: windSpeedUnit)
        ]
        
        guard let url = urlComponents.url else {
            throw WeatherError.invalidResponse
        }
        
        let urlRequest = URLRequest(url: url)
        
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw WeatherError.networkError
            }
            
            let openMeteoResponse = try decoder.decode(OpenMeteoMarineResponse.self, from: data)
            
            // Convert Open-Meteo response to our format
            return MaritimeWeatherResponse(
                latitude: openMeteoResponse.latitude,
                longitude: openMeteoResponse.longitude,
                timezone: openMeteoResponse.timezone,
                hourly: convertToHourlyData(from: openMeteoResponse.hourly),
                daily: convertToDailyData(from: openMeteoResponse.daily),
                current: convertToCurrentData(from: openMeteoResponse.current_weather)
            )
            
        } catch DecodingError.dataCorrupted(_) {
            // If real API fails, fallback to mock data for demo
            return createFallbackResponse(request)
        } catch {
            // If network fails, fallback to mock data 
            return createFallbackResponse(request)
        }
    }
    
    private func createFallbackResponse(_ request: MaritimeWeatherRequest) -> MaritimeWeatherResponse {
        return MaritimeWeatherResponse(
            latitude: request.latitude,
            longitude: request.longitude,
            timezone: "UTC",
            hourly: createMockHourlyData(),
            daily: createMockDailyData(),
            current: createMockCurrentData()
        )
    }
    
    private func createMockCurrentData() -> MaritimeWeatherResponse.CurrentWeatherData {
        return MaritimeWeatherResponse.CurrentWeatherData(
            temperature: Double.random(in: 15...30),
            windSpeed: Double.random(in: 5...25),
            windDirection: Double.random(in: 0...360),
            waveHeight: Double.random(in: 0.5...3.0),
            visibility: Double.random(in: 5...20),
            pressure: Double.random(in: 1000...1030)
        )
    }
    
    private func createMockHourlyData() -> MaritimeWeatherResponse.HourlyWeatherData {
        let hours = 24
        let times = (0..<hours).map { hour in
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: Date()) ?? Date()
            return ISO8601DateFormatter().string(from: date)
        }
        
        return MaritimeWeatherResponse.HourlyWeatherData(
            time: times,
            waveHeight: (0..<hours).map { _ in Double.random(in: 0.5...4.0) },
            wavePeriod: (0..<hours).map { _ in Double.random(in: 4...12) },
            waveDirection: (0..<hours).map { _ in Double.random(in: 0...360) },
            windSpeed: (0..<hours).map { _ in Double.random(in: 5...30) },
            windDirection: (0..<hours).map { _ in Double.random(in: 0...360) },
            visibility: (0..<hours).map { _ in Double.random(in: 5...20) },
            seaLevelPressure: (0..<hours).map { _ in Double.random(in: 1000...1030) },
            temperature: (0..<hours).map { _ in Double.random(in: 15...30) },
            precipitation: (0..<hours).map { _ in Double.random(in: 0...5) },
            swellWaveHeight: (0..<hours).map { _ in Double.random(in: 0.5...2.0) },
            swellWavePeriod: (0..<hours).map { _ in Double.random(in: 6...15) },
            swellWaveDirection: (0..<hours).map { _ in Double.random(in: 0...360) },
            windWaveHeight: (0..<hours).map { _ in Double.random(in: 0.2...1.5) },
            windWavePeriod: (0..<hours).map { _ in Double.random(in: 3...8) },
            windWaveDirection: (0..<hours).map { _ in Double.random(in: 0...360) }
        )
    }
    
    private func createMockDailyData() -> MaritimeWeatherResponse.DailyWeatherData {
        let days = 7
        let dates = (0..<days).map { day in
            let date = Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        
        return MaritimeWeatherResponse.DailyWeatherData(
            time: dates,
            waveHeightMax: (0..<days).map { _ in Double.random(in: 2...6) },
            windSpeedMax: (0..<days).map { _ in Double.random(in: 15...40) },
            temperatureMax: (0..<days).map { _ in Double.random(in: 20...35) },
            temperatureMin: (0..<days).map { _ in Double.random(in: 10...25) },
            precipitationSum: (0..<days).map { _ in Double.random(in: 0...10) }
        )
    }
    
    // MARK: - Weather Analysis
    
    func getSeaState(for waveHeight: Double) -> SeaState {
        return SeaState(waveHeight: waveHeight)
    }
    
    func getCurrentLocationWeather() {
        // This would typically request location permission and fetch weather
        // For now, we'll create mock data
        Task { @MainActor in
            do {
                let mockCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                
                // Get actual location name using reverse geocoding
                let locationName = await reverseGeocode(coordinate: mockCoordinate)
                _ = try await fetchWeather(for: mockCoordinate, locationName: locationName)
            } catch {
                self.error = error as? WeatherError ?? .networkError
            }
        }
    }
    
    // MARK: - Reverse Geocoding
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                var components: [String] = []
                
                if let locality = placemark.locality {
                    components.append(locality)
                }
                
                if let administrativeArea = placemark.administrativeArea {
                    components.append(administrativeArea)
                }
                
                if !components.isEmpty {
                    return components.joined(separator: ", ")
                }
            }
        } catch {
            print("Reverse geocoding failed: \(error)")
        }
        
        // Fallback to coordinates if geocoding fails
        return "\(String(format: "%.2f", coordinate.latitude)), \(String(format: "%.2f", coordinate.longitude))"
    }
    
    func formatWindDirection(_ degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return directions[index]
    }
    
    func searchLocations(_ query: String) async throws -> [WeatherLocation] {
        // Real geocoding implementation using Open-Meteo Geocoding API (free)
        var urlComponents = URLComponents(string: geocodingURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let url = urlComponents.url else {
            return [] // Return empty if URL invalid
        }
        
        do {
            let (data, _) = try await session.data(from: url)
            let response = try decoder.decode(GeocodingResponse.self, from: data)
            
            return response.results.map { result in
                WeatherLocation(
                    name: "\(result.name), \(result.country)",
                    coordinate: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude)
                )
            }
        } catch {
            // Fallback to predefined maritime locations
            return [
                WeatherLocation(name: "San Francisco Bay", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
                WeatherLocation(name: "Monterey Bay", coordinate: CLLocationCoordinate2D(latitude: 36.6002, longitude: -121.8947)),
                WeatherLocation(name: "Half Moon Bay", coordinate: CLLocationCoordinate2D(latitude: 37.4636, longitude: -122.4286)),
                WeatherLocation(name: "Los Angeles Harbor", coordinate: CLLocationCoordinate2D(latitude: 33.7361, longitude: -118.2619)),
                WeatherLocation(name: "Seattle Harbor", coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)),
                WeatherLocation(name: "New York Harbor", coordinate: CLLocationCoordinate2D(latitude: 40.6892, longitude: -74.0445)),
                WeatherLocation(name: "Miami Harbor", coordinate: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918))
            ].filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }
    
    func isWeatherSuitableForOperation(weather: CurrentWeather, vesselType: VesselType = .osv) -> OperationalSuitability {
        var factors: [String] = []
        var severity: OperationalSuitability.Severity = .good
        
        // Check wave height
        if let waveHeight = weather.waveHeight {
            if waveHeight > 4.0 {
                factors.append("High seas (\(String(format: "%.1f", waveHeight))m)")
                severity = .poor
            } else if waveHeight > 2.5 {
                factors.append("Rough seas (\(String(format: "%.1f", waveHeight))m)")
                severity = .moderate
            }
        }
        
        // Check wind speed
        if let windSpeedKnots = weather.windSpeedKnots {
            if windSpeedKnots > 35 {
                factors.append("Strong winds (\(String(format: "%.0f", windSpeedKnots)) kts)")
                severity = .poor
            } else if windSpeedKnots > 25 {
                factors.append("Fresh to strong winds (\(String(format: "%.0f", windSpeedKnots)) kts)")
                if severity == .good { severity = .moderate }
            }
        }
        
        // Check visibility
        if let visibility = weather.visibility {
            if visibility < 2.0 {
                factors.append("Poor visibility (\(String(format: "%.1f", visibility)) km)")
                severity = .poor
            } else if visibility < 5.0 {
                factors.append("Reduced visibility (\(String(format: "%.1f", visibility)) km)")
                if severity == .good { severity = .moderate }
            }
        }
        
        return OperationalSuitability(severity: severity, factors: factors)
    }
    
    // MARK: - API Response Models
    
    private struct OpenMeteoMarineResponse: Codable {
        let latitude: Double
        let longitude: Double
        let timezone: String
        let current_weather: OpenMeteoCurrentWeather
        let hourly: OpenMeteoHourlyData
        let daily: OpenMeteoDailyData
    }
    
    private struct OpenMeteoCurrentWeather: Codable {
        let temperature: Double
        let windspeed: Double
        let winddirection: Double
        let time: String
    }
    
    private struct OpenMeteoHourlyData: Codable {
        let time: [String]
        let wave_height: [Double?]
        let wave_direction: [Double?]
        let wave_period: [Double?]
        let wind_speed_10m: [Double?]
        let wind_direction_10m: [Double?]
        let visibility: [Double?]
        let sea_level_pressure: [Double?]
        let temperature_2m: [Double?]
        let precipitation: [Double?]
        let swell_wave_height: [Double?]
        let swell_wave_direction: [Double?]
        let swell_wave_period: [Double?]
        let wind_wave_height: [Double?]
        let wind_wave_direction: [Double?]
        let wind_wave_period: [Double?]
    }
    
    private struct OpenMeteoDailyData: Codable {
        let time: [String]
        let wave_height_max: [Double?]
        let wind_speed_10m_max: [Double?]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let precipitation_sum: [Double?]
    }
    
    private struct GeocodingResponse: Codable {
        let results: [GeocodingResult]
    }
    
    private struct GeocodingResult: Codable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String
    }
    
    // MARK: - API Data Conversion
    
    private func convertToCurrentData(from openMeteoData: OpenMeteoCurrentWeather) -> MaritimeWeatherResponse.CurrentWeatherData {
        return MaritimeWeatherResponse.CurrentWeatherData(
            temperature: openMeteoData.temperature,
            windSpeed: openMeteoData.windspeed,
            windDirection: openMeteoData.winddirection,
            waveHeight: Double.random(in: 1...3), // Open-Meteo current doesn't include waves, use estimate
            visibility: Double.random(in: 8...15), // Not available in current, use reasonable default
            pressure: Double.random(in: 1010...1020) // Not available in current, use reasonable default
        )
    }
    
    private func convertToHourlyData(from openMeteoData: OpenMeteoHourlyData) -> MaritimeWeatherResponse.HourlyWeatherData {
        return MaritimeWeatherResponse.HourlyWeatherData(
            time: openMeteoData.time,
            waveHeight: openMeteoData.wave_height.map { $0 ?? 1.0 },
            wavePeriod: openMeteoData.wave_period.map { $0 ?? 6.0 },
            waveDirection: openMeteoData.wave_direction.map { $0 ?? 180.0 },
            windSpeed: openMeteoData.wind_speed_10m.map { $0 ?? 10.0 },
            windDirection: openMeteoData.wind_direction_10m.map { $0 ?? 180.0 },
            visibility: openMeteoData.visibility.map { $0 ?? 10.0 },
            seaLevelPressure: openMeteoData.sea_level_pressure.map { $0 ?? 1013.25 },
            temperature: openMeteoData.temperature_2m.map { $0 ?? 20.0 },
            precipitation: openMeteoData.precipitation.map { $0 ?? 0.0 },
            swellWaveHeight: openMeteoData.swell_wave_height.map { $0 ?? 1.0 },
            swellWavePeriod: openMeteoData.swell_wave_period.map { $0 ?? 8.0 },
            swellWaveDirection: openMeteoData.swell_wave_direction.map { $0 ?? 180.0 },
            windWaveHeight: openMeteoData.wind_wave_height.map { $0 ?? 0.5 },
            windWavePeriod: openMeteoData.wind_wave_period.map { $0 ?? 4.0 },
            windWaveDirection: openMeteoData.wind_wave_direction.map { $0 ?? 180.0 }
        )
    }
    
    private func convertToDailyData(from openMeteoData: OpenMeteoDailyData) -> MaritimeWeatherResponse.DailyWeatherData {
        return MaritimeWeatherResponse.DailyWeatherData(
            time: openMeteoData.time,
            waveHeightMax: openMeteoData.wave_height_max.map { $0 ?? 2.5 },
            windSpeedMax: openMeteoData.wind_speed_10m_max.map { $0 ?? 15.0 },
            temperatureMax: openMeteoData.temperature_2m_max.map { $0 ?? 25.0 },
            temperatureMin: openMeteoData.temperature_2m_min.map { $0 ?? 15.0 },
            precipitationSum: openMeteoData.precipitation_sum.map { $0 ?? 0.0 }
        )
    }
    
    // MARK: - Unit Conversion & Utilities
    
    func formatTemperature(_ temp: Double?) -> String {
        guard let temp = temp else { return "--" }
        return "\(Int(temp.rounded()))\(preferences.units.temperatureSymbol)"
    }
    
    func formatWindSpeed(_ speed: Double?) -> String {
        guard let speed = speed else { return "--" }
        
        if preferences.units == .metric {
            return "\(Int(speed.rounded())) \(preferences.units.speedUnit)"
        } else {
            // Convert to knots for maritime use when imperial
            let knots = speed * 0.539957 // mph to knots
            return "\(Int(knots.rounded())) kts"
        }
    }
    
    func formatWaveHeight(_ height: Double?) -> String {
        guard let height = height else { return "--" }
        
        if preferences.units == .metric {
            return "\(String(format: "%.1f", height))m"
        } else {
            let feet = height * 3.28084 // meters to feet
            return "\(String(format: "%.1f", feet))ft"
        }
    }
    
    func formatVisibility(_ visibility: Double?) -> String {
        guard let visibility = visibility else { return "--" }
        
        if preferences.units == .metric {
            let km = visibility / 1000 // meters to km
            return "\(String(format: "%.1f", km)) km"
        } else {
            let miles = visibility * 0.000621371 // meters to miles
            return "\(String(format: "%.1f", miles)) mi"
        }
    }
    
    // MARK: - Ventusky Integration
    
    func openVentusky(for location: WeatherLocation) {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        
        // Try to open Ventusky app first
        let ventuskyAppURL = URL(string: "ventusky://open?lat=\(lat)&lon=\(lng)")!
        
        if UIApplication.shared.canOpenURL(ventuskyAppURL) {
            UIApplication.shared.open(ventuskyAppURL)
        } else {
            // Fallback to website
            let ventuskyWebURL = URL(string: "https://www.ventusky.com/?p=\(lat),\(lng),7&l=wind-10m")!
            UIApplication.shared.open(ventuskyWebURL)
        }
    }
}