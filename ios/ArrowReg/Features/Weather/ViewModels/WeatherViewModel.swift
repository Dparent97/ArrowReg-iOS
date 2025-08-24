import SwiftUI
import Combine
import CoreLocation

@MainActor
class WeatherViewModel: ObservableObject {
    @Published var currentWeather: MaritimeWeatherResponse?
    @Published var forecast: [MaritimeWeatherResponse] = []
    @Published var isLoading = false
    @Published var error: WeatherError?
    @Published var showingError = false
    @Published var selectedLocation: CLLocationCoordinate2D?
    @Published var locationName = "Current Location"
    
    private let weatherService: WeatherService
    private let locationManager = CLLocationManager()
    private var locationDelegate: LocationManagerDelegate?
    private var cancellables = Set<AnyCancellable>()
    
    // Sample locations for quick access
    let sampleLocations = [
        MaritimeLocation(name: "Gulf of Mexico", coordinate: CLLocationCoordinate2D(latitude: 27.5, longitude: -90.0)),
        MaritimeLocation(name: "North Sea", coordinate: CLLocationCoordinate2D(latitude: 56.0, longitude: 3.0)),
        MaritimeLocation(name: "Caribbean Sea", coordinate: CLLocationCoordinate2D(latitude: 15.0, longitude: -75.0)),
        MaritimeLocation(name: "Mediterranean Sea", coordinate: CLLocationCoordinate2D(latitude: 36.0, longitude: 15.0)),
        MaritimeLocation(name: "Baltic Sea", coordinate: CLLocationCoordinate2D(latitude: 56.0, longitude: 18.0))
    ]
    
    init(weatherService: WeatherService = WeatherService.shared) {
        self.weatherService = weatherService
        setupLocationManager()
    }
    
    func loadWeatherForCurrentLocation() {
        guard let location = selectedLocation ?? locationManager.location?.coordinate else {
            requestLocation()
            return
        }
        
        loadWeather(for: location)
    }
    
    func loadWeather(for coordinate: CLLocationCoordinate2D) {
        isLoading = true
        error = nil
        selectedLocation = coordinate
        
        Task {
            do {
                // Load forecast (which includes current weather data)
                let forecastResponse = try await weatherService.fetchForecast(for: coordinate, days: 7)
                
                await MainActor.run {
                    self.currentWeather = forecastResponse
                    self.forecast = [forecastResponse]
                    self.isLoading = false
                }
                
            } catch let weatherError as WeatherError {
                await MainActor.run {
                    self.error = weatherError
                    self.showingError = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = .networkError
                    self.showingError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadWeather(for location: MaritimeLocation) {
        locationName = location.name
        loadWeather(for: location.coordinate)
    }
    
    func refreshWeather() {
        guard let location = selectedLocation else {
            loadWeatherForCurrentLocation()
            return
        }
        
        loadWeather(for: location)
    }
    
    private func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }
    
    private func setupLocationManager() {
        let delegate = LocationManagerDelegate(viewModel: self)
        locationManager.delegate = delegate
        // Keep a strong reference to prevent deallocation
        self.locationDelegate = delegate
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    // Weather analysis functions
    func getOperationalSuitability(for weather: MaritimeWeatherResponse, vesselType: VesselType = .osv) -> OperationalSuitability {
        // For now, create a simple operational suitability assessment
        // In a real app, this would use the actual weather data
        let factors: [String] = []
        let severity: OperationalSuitability.Severity = .good
        return OperationalSuitability(severity: severity, factors: factors)
    }
    
    func getSeaStateDescription(for waveHeight: Double) -> String {
        let seaState = SeaState.fromWaveHeight(waveHeight)
        return seaState.description
    }
    
    func getWindDescription(for windSpeed: Double) -> String {
        switch windSpeed {
        case 0..<5: return "Calm"
        case 5..<11: return "Light breeze"
        case 11..<19: return "Moderate breeze"
        case 19..<28: return "Fresh breeze"
        case 28..<38: return "Strong breeze"
        case 38..<49: return "Near gale"
        case 49..<61: return "Gale"
        case 61..<74: return "Strong gale"
        case 74..<88: return "Storm"
        default: return "Hurricane force"
        }
    }
}

// MARK: - Location Manager Delegate

private class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    weak var viewModel: WeatherViewModel?
    
    init(viewModel: WeatherViewModel) {
        self.viewModel = viewModel
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            viewModel?.locationName = "Current Location"
            viewModel?.loadWeather(for: location.coordinate)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            viewModel?.error = .locationError
            viewModel?.showingError = true
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            Task { @MainActor in
                viewModel?.error = .locationPermissionDenied
                viewModel?.showingError = true
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Supporting Models
// MaritimeLocation is defined in WeatherModels.swift