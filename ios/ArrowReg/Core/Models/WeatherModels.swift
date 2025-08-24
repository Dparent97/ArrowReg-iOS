import Foundation
import CoreLocation

// MARK: - Weather Units
enum WeatherUnit: String, CaseIterable {
    case metric = "metric"
    case imperial = "imperial"
    
    var temperatureSymbol: String {
        switch self {
        case .metric: return "°C"
        case .imperial: return "°F"
        }
    }
    
    var speedUnit: String {
        switch self {
        case .metric: return "km/h"
        case .imperial: return "mph"
        }
    }
    
    var distanceUnit: String {
        switch self {
        case .metric: return "m"
        case .imperial: return "ft"
        }
    }
    
    var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }
}

// MARK: - Weather Preferences
class WeatherPreferences: ObservableObject {
    @Published var units: WeatherUnit {
        didSet {
            UserDefaults.standard.set(units.rawValue, forKey: "weatherUnits")
        }
    }
    
    static let shared = WeatherPreferences()
    
    private init() {
        let savedUnit = UserDefaults.standard.string(forKey: "weatherUnits") ?? WeatherUnit.imperial.rawValue
        self.units = WeatherUnit(rawValue: savedUnit) ?? .imperial
    }
}

// MARK: - Weather Request Models
struct MaritimeWeatherRequest: Codable {
    let latitude: Double
    let longitude: Double
    let hourly: [HourlyParameter]
    let daily: [DailyParameter]
    let timezone: String
    let forecastDays: Int
    
    enum HourlyParameter: String, Codable, CaseIterable {
        case waveHeight = "wave_height"
        case wavePeriod = "wave_period" 
        case waveDirection = "wave_direction"
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case visibility = "visibility"
        case seaLevelPressure = "sea_level_pressure"
        case temperature = "temperature_2m"
        case precipitation = "precipitation"
        case swellWaveHeight = "swell_wave_height"
        case swellWavePeriod = "swell_wave_period"
        case swellWaveDirection = "swell_wave_direction"
        case windWaveHeight = "wind_wave_height"
        case windWavePeriod = "wind_wave_period"
        case windWaveDirection = "wind_wave_direction"
    }
    
    enum DailyParameter: String, Codable, CaseIterable {
        case waveHeightMax = "wave_height_max"
        case windSpeedMax = "wind_speed_10m_max"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
        case precipitationSum = "precipitation_sum"
    }
    
    init(coordinate: CLLocationCoordinate2D, forecastDays: Int = 7) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.hourly = HourlyParameter.allCases
        self.daily = DailyParameter.allCases
        self.timezone = "auto"
        self.forecastDays = forecastDays
    }
}

// MARK: - Weather Response Models
struct MaritimeWeatherResponse: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let hourly: HourlyWeatherData?
    let daily: DailyWeatherData?
    let current: CurrentWeatherData?
    
    struct HourlyWeatherData: Codable {
        let time: [String]
        let waveHeight: [Double?]
        let wavePeriod: [Double?]
        let waveDirection: [Double?]
        let windSpeed: [Double?]
        let windDirection: [Double?]
        let visibility: [Double?]
        let seaLevelPressure: [Double?]
        let temperature: [Double?]
        let precipitation: [Double?]
        let swellWaveHeight: [Double?]
        let swellWavePeriod: [Double?]
        let swellWaveDirection: [Double?]
        let windWaveHeight: [Double?]
        let windWavePeriod: [Double?]
        let windWaveDirection: [Double?]
        
        enum CodingKeys: String, CodingKey {
            case time
            case waveHeight = "wave_height"
            case wavePeriod = "wave_period"
            case waveDirection = "wave_direction"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case visibility
            case seaLevelPressure = "sea_level_pressure"
            case temperature = "temperature_2m"
            case precipitation
            case swellWaveHeight = "swell_wave_height"
            case swellWavePeriod = "swell_wave_period"
            case swellWaveDirection = "swell_wave_direction"
            case windWaveHeight = "wind_wave_height"
            case windWavePeriod = "wind_wave_period"
            case windWaveDirection = "wind_wave_direction"
        }
    }
    
    struct DailyWeatherData: Codable {
        let time: [String]
        let waveHeightMax: [Double?]
        let windSpeedMax: [Double?]
        let temperatureMax: [Double?]
        let temperatureMin: [Double?]
        let precipitationSum: [Double?]
        
        enum CodingKeys: String, CodingKey {
            case time
            case waveHeightMax = "wave_height_max"
            case windSpeedMax = "wind_speed_10m_max"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case precipitationSum = "precipitation_sum"
        }
    }
    
    struct CurrentWeatherData: Codable {
        let temperature: Double?
        let windSpeed: Double?
        let windDirection: Double?
        let waveHeight: Double?
        let visibility: Double?
        let pressure: Double?
        
        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case waveHeight = "wave_height"
            case visibility
            case pressure = "sea_level_pressure"
        }
    }
}

// MARK: - Processed Weather Models
struct MaritimeWeatherData {
    let location: WeatherLocation
    let current: CurrentWeather
    let hourlyForecast: [HourlyWeather]
    let dailyForecast: [DailyWeather]
    let lastUpdated: Date
    
    init(from response: MaritimeWeatherResponse, location: WeatherLocation) {
        self.location = location
        self.lastUpdated = Date()
        
        // Process current weather
        if let current = response.current {
            self.current = CurrentWeather(from: current)
        } else {
            // Fallback to first hourly data point
            self.current = CurrentWeather(
                temperature: response.hourly?.temperature.first ?? nil,
                windSpeed: response.hourly?.windSpeed.first ?? nil,
                windDirection: response.hourly?.windDirection.first ?? nil,
                waveHeight: response.hourly?.waveHeight.first ?? nil,
                wavePeriod: response.hourly?.wavePeriod.first ?? nil,
                visibility: response.hourly?.visibility.first ?? nil,
                pressure: response.hourly?.seaLevelPressure.first ?? nil
            )
        }
        
        // Process hourly forecast
        self.hourlyForecast = Self.processHourlyData(response.hourly)
        
        // Process daily forecast  
        self.dailyForecast = Self.processDailyData(response.daily)
    }
    
    private static func processHourlyData(_ hourly: MaritimeWeatherResponse.HourlyWeatherData?) -> [HourlyWeather] {
        guard let hourly = hourly else { return [] }
        
        let formatter = ISO8601DateFormatter()
        
        return zip(hourly.time.indices, hourly.time).compactMap { (index, timeString) -> HourlyWeather? in
            guard let date = formatter.date(from: timeString) else { return nil }
            
            return HourlyWeather(
                time: date,
                temperature: hourly.temperature[safe: index] ?? nil,
                windSpeed: hourly.windSpeed[safe: index] ?? nil,
                windDirection: hourly.windDirection[safe: index] ?? nil,
                waveHeight: hourly.waveHeight[safe: index] ?? nil,
                wavePeriod: hourly.wavePeriod[safe: index] ?? nil,
                waveDirection: hourly.waveDirection[safe: index] ?? nil,
                swellHeight: hourly.swellWaveHeight[safe: index] ?? nil,
                swellPeriod: hourly.swellWavePeriod[safe: index] ?? nil,
                swellDirection: hourly.swellWaveDirection[safe: index] ?? nil,
                windWaveHeight: hourly.windWaveHeight[safe: index] ?? nil,
                precipitation: hourly.precipitation[safe: index] ?? nil,
                visibility: hourly.visibility[safe: index] ?? nil,
                pressure: hourly.seaLevelPressure[safe: index] ?? nil
            )
        }
    }
    
    private static func processDailyData(_ daily: MaritimeWeatherResponse.DailyWeatherData?) -> [DailyWeather] {
        guard let daily = daily else { return [] }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        return zip(daily.time.indices, daily.time).compactMap { (index, dateString) -> DailyWeather? in
            guard let date = formatter.date(from: dateString) else { return nil }
            
            return DailyWeather(
                date: date,
                temperatureMax: daily.temperatureMax[safe: index] ?? nil,
                temperatureMin: daily.temperatureMin[safe: index] ?? nil,
                windSpeedMax: daily.windSpeedMax[safe: index] ?? nil,
                waveHeightMax: daily.waveHeightMax[safe: index] ?? nil,
                precipitationSum: daily.precipitationSum[safe: index] ?? nil
            )
        }
    }
}

struct WeatherLocation {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let country: String?
    let region: String?
    
    init(name: String, coordinate: CLLocationCoordinate2D, country: String? = nil, region: String? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.country = country
        self.region = region
    }
}

struct CurrentWeather {
    let temperature: Double?     // °C
    let windSpeed: Double?       // km/h
    let windDirection: Double?   // degrees
    let waveHeight: Double?      // meters
    let wavePeriod: Double?      // seconds
    let visibility: Double?      // km
    let pressure: Double?        // hPa
    
    init(from current: MaritimeWeatherResponse.CurrentWeatherData) {
        self.temperature = current.temperature
        self.windSpeed = current.windSpeed
        self.windDirection = current.windDirection
        self.waveHeight = current.waveHeight
        self.wavePeriod = nil
        self.visibility = current.visibility
        self.pressure = current.pressure
    }
    
    init(temperature: Double?, windSpeed: Double?, windDirection: Double?, waveHeight: Double?, wavePeriod: Double?, visibility: Double?, pressure: Double?) {
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.waveHeight = waveHeight
        self.wavePeriod = wavePeriod
        self.visibility = visibility
        self.pressure = pressure
    }
    
    var windSpeedKnots: Double? {
        guard let windSpeed = windSpeed else { return nil }
        return windSpeed * 0.539957 // Convert km/h to knots
    }
    
    var waveHeightFeet: Double? {
        guard let waveHeight = waveHeight else { return nil }
        return waveHeight * 3.28084 // Convert meters to feet
    }
    
    var temperatureFahrenheit: Double? {
        guard let temperature = temperature else { return nil }
        return temperature * 9/5 + 32
    }
}

struct HourlyWeather {
    let time: Date
    let temperature: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let waveHeight: Double?
    let wavePeriod: Double?
    let waveDirection: Double?
    let swellHeight: Double?
    let swellPeriod: Double?
    let swellDirection: Double?
    let windWaveHeight: Double?
    let precipitation: Double?
    let visibility: Double?
    let pressure: Double?
    
    var windSpeedKnots: Double? {
        guard let windSpeed = windSpeed else { return nil }
        return windSpeed * 0.539957
    }
    
    var waveHeightFeet: Double? {
        guard let waveHeight = waveHeight else { return nil }
        return waveHeight * 3.28084
    }
}

struct DailyWeather {
    let date: Date
    let temperatureMax: Double?
    let temperatureMin: Double?
    let windSpeedMax: Double?
    let waveHeightMax: Double?
    let precipitationSum: Double?
    
    var windSpeedMaxKnots: Double? {
        guard let windSpeedMax = windSpeedMax else { return nil }
        return windSpeedMax * 0.539957
    }
    
    var waveHeightMaxFeet: Double? {
        guard let waveHeightMax = waveHeightMax else { return nil }
        return waveHeightMax * 3.28084
    }
}

// MARK: - Weather Conditions
enum SeaState: Int, CaseIterable {
    case calm = 0
    case slight = 1
    case moderate = 2
    case rough = 3
    case veryRough = 4
    case high = 5
    case veryHigh = 6
    case phenomenal = 7
    case exceptional = 8
    case extreme = 9
    
    init(waveHeight: Double) {
        switch waveHeight {
        case 0..<0.1: self = .calm
        case 0.1..<0.5: self = .slight
        case 0.5..<1.25: self = .moderate
        case 1.25..<2.5: self = .rough
        case 2.5..<4.0: self = .veryRough
        case 4.0..<6.0: self = .high
        case 6.0..<9.0: self = .veryHigh
        case 9.0..<14.0: self = .phenomenal
        case 14.0..<20.0: self = .exceptional
        default: self = .extreme
        }
    }
    
    static func fromWaveHeight(_ waveHeight: Double) -> SeaState {
        return SeaState(waveHeight: waveHeight)
    }
    
    var description: String {
        switch self {
        case .calm: return "Calm"
        case .slight: return "Slight"
        case .moderate: return "Moderate"
        case .rough: return "Rough"
        case .veryRough: return "Very Rough"
        case .high: return "High"
        case .veryHigh: return "Very High"
        case .phenomenal: return "Phenomenal"
        case .exceptional: return "Exceptional"
        case .extreme: return "Extreme"
        }
    }
    
    var color: String {
        switch self {
        case .calm: return "#00FF00"
        case .slight: return "#ADFF2F"
        case .moderate: return "#FFFF00"
        case .rough: return "#FFA500"
        case .veryRough: return "#FF6347"
        case .high: return "#FF0000"
        case .veryHigh: return "#8B0000"
        case .phenomenal: return "#800080"
        case .exceptional: return "#4B0082"
        case .extreme: return "#000000"
        }
    }
}

// MARK: - Operational Suitability
struct OperationalSuitability {
    let isOperational: Bool
    let severity: Severity
    let factors: [String]
    let recommendations: [String]
    
    enum Severity: String, CaseIterable {
        case good = "good"
        case moderate = "moderate"
        case poor = "poor"
        
        var displayName: String {
            switch self {
            case .good: return "Good"
            case .moderate: return "Moderate"
            case .poor: return "Poor"
            }
        }
        
        var description: String {
            switch self {
            case .good: return "Conditions are favorable for operations"
            case .moderate: return "Conditions require caution"
            case .poor: return "Operations not recommended"
            }
        }
        
        var color: String {
            switch self {
            case .good: return "#00FF00"
            case .moderate: return "#FFFF00"
            case .poor: return "#FF0000"
            }
        }
    }
    
    init(severity: Severity, factors: [String], recommendations: [String] = []) {
        self.severity = severity
        self.factors = factors
        self.isOperational = severity != .poor
        self.recommendations = recommendations
    }
}

// MARK: - Weather Errors
enum WeatherError: Error, LocalizedError {
    case locationNotFound
    case locationError
    case locationPermissionDenied
    case networkError
    case invalidResponse
    case apiKeyMissing
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .locationNotFound:
            return "Weather location not found"
        case .locationError:
            return "Error accessing location services"
        case .locationPermissionDenied:
            return "Location permission denied"
        case .networkError:
            return "Network error while fetching weather data"
        case .invalidResponse:
            return "Invalid weather data response"
        case .apiKeyMissing:
            return "Weather API key is missing"
        case .rateLimitExceeded:
            return "Weather API rate limit exceeded"
        }
    }
}

// MARK: - Maritime Location Model
struct MaritimeLocation: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let description: String?
    
    init(name: String, coordinate: CLLocationCoordinate2D, description: String? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.description = description
    }
}

// MARK: - Weather Response (Legacy)
struct WeatherResponse: Codable {
    let temperature: Double
    let windSpeed: Double
    let waveHeight: Double
    let visibility: Double
}

// MARK: - Helper Extensions
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}