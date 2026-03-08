import Combine
import CoreLocation
import Foundation

/// Models matching the subset of OpenWeatherMap API used by the app.
struct OpenWeatherMapResponse: Codable {
    struct Weather: Codable {
        let description: String?
    }
    struct Main: Codable {
        let temp: Double?
        let humidity: Int?
    }
    struct Wind: Codable {
        let speed: Double?
    }
    struct Clouds: Codable {
        let all: Int?
    }
    let weather: [Weather]?
    let main: Main?
    let wind: Wind?
    let clouds: Clouds?
    let visibility: Int?
    let name: String?
}

/// Full weather model with computed properties for UI display
struct WeatherData {
    let temperature: Double?
    let description: String?
    let humidity: Int?
    let windSpeed: Double?
    let visibility: Int?
    let cloudCover: Int?
    let locationName: String?

    var humidityString: String {
        guard let humidity = humidity else { return "N/A" }
        return "\(humidity)%"
    }

    var windSpeedString: String {
        guard let speed = windSpeed else { return "N/A" }
        return String(format: "%.1f m/s", speed)
    }

    var visibilityString: String {
        guard let vis = visibility else { return "N/A" }
        return String(format: "%.1f km", Double(vis) / 1000.0)
    }
}

final class OpenWeatherMapService: ObservableObject {
    @Published var currentWeatherDescription: String? = nil
    @Published var currentTemperatureCelsius: Double? = nil
    @Published var currentWeather: WeatherData? = nil
    @Published var isLoading: Bool = false
    @Published var locationName: String = "Your Location"

    let locationManager = WeatherLocationManager()
    private var apiKey: String
    private var cancellables = Set<AnyCancellable>()
    private var lastWeatherLocation: CLLocation?

    init(apiKey: String = "") {
        self.apiKey = apiKey
        setupLocationObserver()
        startLocationTracking()
    }

    private func setupLocationObserver() {
        // Observe location changes and automatically update weather
        locationManager.$currentLocation
            .compactMap { $0 }
            .removeDuplicates { location1, location2 in
                // Only update if location changed significantly (more than 500 meters)
                return location1.distance(from: location2) < 500
            }
            .sink { [weak self] location in
                print("📍 Location changed significantly, updating weather")
                self?.lastWeatherLocation = location
                self?.refreshWeatherForLocation(location)
            }
            .store(in: &cancellables)

        // Prioritize location manager's geocoding for current location display
        locationManager.$currentCity
            .debounce(for: .seconds(1), scheduler: RunLoop.main)  // Shorter debounce for better responsiveness
            .sink { [weak self] city in
                guard let self = self else { return }
                if !city.isEmpty {
                    // Always use geocoded location name as it's more accurate for user's actual location
                    self.locationName = city
                    print("📍 Updated location name from geocoding: \(city)")
                }
            }
            .store(in: &cancellables)

        // Listen for app foreground refresh requests
        NotificationCenter.default.publisher(for: .refreshLocationAndWeather)
            .sink { [weak self] _ in
                print("🌤️ Received app foreground refresh request")
                self?.locationManager.startLocationUpdates()
                self?.refreshWeather()
            }
            .store(in: &cancellables)
    }

    private func startLocationTracking() {
        print("🌤️ Starting location tracking for weather updates")
        // Request immediate location for faster initial display
        locationManager.requestWhenInUse()
        locationManager.forceLocationRefresh()
    }

    private func refreshWeatherForLocation(_ location: CLLocation) {
        print(
            "🌤️ Refreshing weather for new location: \(location.coordinate.latitude), \(location.coordinate.longitude)"
        )

        Task {
            do {
                _ = try await fetchCurrentWeather(
                    lat: location.coordinate.latitude, lon: location.coordinate.longitude)
                print("🌤️ Weather fetch successful for new location")
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                print("🌤️ Failed to refresh weather for new location: \(error)")
            }
        }
    }

    /// Loads current weather for the provided location using OpenWeatherMap (async).
    func fetchCurrentWeather(lat: Double, lon: Double) async throws -> OpenWeatherMapResponse {
        DispatchQueue.main.async {
            self.isLoading = true
        }

        guard !apiKey.isEmpty else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            throw NSError(
                domain: "OpenWeatherMapService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "API key not configured"])
        }

        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "appid", value: apiKey),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            throw NSError(
                domain: "OpenWeatherMapService", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Network error or non-200 response"])
        }

        let decoded = try JSONDecoder().decode(OpenWeatherMapResponse.self, from: data)

        DispatchQueue.main.async {
            // Update weather data
            self.currentWeatherDescription = decoded.weather?.first?.description
            self.currentTemperatureCelsius = decoded.main?.temp

            // Use weather API location name only as fallback if no geocoded name available
            if let apiLocationName = decoded.name, !apiLocationName.isEmpty,
                self.locationName == "Your Location"
            {
                self.locationName = apiLocationName
                print("🌤️ Using weather API location as fallback: \(apiLocationName)")
            }

            // Log temperature for debugging
            if let temp = decoded.main?.temp {
                print("🌤️ Temperature received: \(temp)°C")
            }

            // Populate full weather data model
            self.currentWeather = WeatherData(
                temperature: decoded.main?.temp,
                description: decoded.weather?.first?.description,
                humidity: decoded.main?.humidity,
                windSpeed: decoded.wind?.speed,
                visibility: decoded.visibility,
                cloudCover: decoded.clouds?.all,
                locationName: decoded.name
            )

            self.isLoading = false
            print("🌤️ Weather data updated successfully")
        }

        return decoded
    }

    /// Refresh weather data using current location from location manager
    func refreshWeather() {
        print(
            "🌤️ Refreshing weather - API Key: \(apiKey.isEmpty ? "EMPTY" : "SET"), Location: \(locationManager.currentLocation?.description ?? "NONE")"
        )

        guard let location = locationManager.currentLocation else {
            print("🌤️ No location available for weather")
            // If no location available, just mark as not loading
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }

        print(
            "🌤️ Fetching weather for location: \(location.coordinate.latitude), \(location.coordinate.longitude)"
        )

        Task {
            do {
                _ = try await fetchCurrentWeather(
                    lat: location.coordinate.latitude, lon: location.coordinate.longitude)
                print("🌤️ Weather fetch successful")
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                print("🌤️ Failed to refresh weather: \(error)")
            }
        }
    }
}
