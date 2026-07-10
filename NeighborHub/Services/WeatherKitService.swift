    import Combine
import CoreLocation
import Foundation
import WeatherKit

/// Full weather model with computed properties for UI display (previously in OpenWeatherMapService.swift)
struct WeatherData {
    let temperature: Double?
    let description: String?
    let humidity: Int?
    let windSpeed: Double?
    let windDirection: String?        // e.g. "NNE"
    let visibility: Int?              // metres
    let cloudCover: Int?              // percent
    let locationName: String?
    let apparentTemperature: Double?  // "feels like" °C
    let uvIndex: Int?
    let uvCategory: String?           // Low / Moderate / High / Very High / Extreme
    let pressure: Double?             // hPa
    let isDaylight: Bool
    let precipitationChance: Double?   // 0.0–1.0

    var precipitationChanceString: String {
        guard let chance = precipitationChance else { return "0%" }
        return "\(Int((chance * 100).rounded()))%"
    }

    var humidityString: String {
        guard let humidity = humidity else { return "N/A" }
        return "\(humidity)%"
    }

    var windSpeedString: String {
        guard let speed = windSpeed else { return "N/A" }
        return String(format: "%.0f km/h", speed)
    }

    var visibilityString: String {
        guard let vis = visibility else { return "N/A" }
        return String(format: "%.1f km", Double(vis) / 1000.0)
    }

    var apparentTemperatureString: String {
        guard let t = apparentTemperature else { return "N/A" }
        return String(format: "%.1f°C", t)
    }

    var pressureString: String {
        guard let p = pressure else { return "N/A" }
        return String(format: "%.0f hPa", p)
    }

    var uvIndexString: String {
        guard let uv = uvIndex else { return "N/A" }
        if let cat = uvCategory { return "\(uv) (\(cat))" }
        return "\(uv)"
    }
}

struct HourlyForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    let temperatureC: Double
    let conditionDescription: String
    let isDaylight: Bool
}

struct DailyForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    let highC: Double
    let lowC: Double
    let conditionDescription: String
}

/// Fetches current weather using Apple WeatherKit (iOS 16+).
/// Drop-in replacement for OpenWeatherMapService — identical @Published interface, no API key required.
final class WeatherKitService: ObservableObject {
    @Published var currentWeatherDescription: String? = nil
    @Published var currentTemperatureCelsius: Double? = nil
    @Published var currentWeather: WeatherData? = nil
    @Published var hourlyForecast: [HourlyForecastPoint] = []
    @Published var dailyForecast: [DailyForecastPoint] = []
    @Published var isLoading: Bool = false
    @Published var locationName: String = "Your Location"

    let locationManager = WeatherLocationManager()
    private var cancellables = Set<AnyCancellable>()
    private var lastWeatherLocation: CLLocation?
    private let weatherKitService = WeatherService.shared

    init() {
        setupLocationObserver()
        startLocationTracking()
    }

    private func setupLocationObserver() {
        // Observe location changes and automatically update weather
        locationManager.$currentLocation
            .compactMap { $0 }
            .removeDuplicates { (l1: CLLocation, l2: CLLocation) -> Bool in
                l1.distance(from: l2) < 500
            }
            .sink { [weak self] (location: CLLocation) in
                print("📍 Location changed significantly, updating weather")
                self?.lastWeatherLocation = location
                self?.fetchWeather(for: location)
            }
            .store(in: &cancellables)

        // Use geocoded city name for display
        locationManager.$currentCity
            .debounce(for: RunLoop.SchedulerTimeType.Stride.seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] (city: String) in
                guard let self = self, !city.isEmpty else { return }
                DispatchQueue.main.async { self.locationName = city }
                print("📍 Updated location name from geocoding: \(city)")
            }
            .store(in: &cancellables)

        // Refresh on app foreground
        NotificationCenter.default.publisher(for: NSNotification.Name("refreshLocationAndWeather"))
            .sink { [weak self] _ in
                print("🌤️ Received app foreground refresh request")
                self?.locationManager.startLocationUpdates()
                self?.refreshWeather()
            }
            .store(in: &cancellables)
    }

    private func startLocationTracking() {
        locationManager.requestWhenInUse()
        locationManager.forceLocationRefresh()
    }

    /// Refresh weather using the current location from the location manager.
    func refreshWeather() {
        guard let location = locationManager.currentLocation else {
            Task { await MainActor.run { self.isLoading = false } }
            print("🌤️ No location available for WeatherKit fetch")
            return
        }
        fetchWeather(for: location)
    }

    private func fetchWeather(for location: CLLocation) {
        Task {
            await MainActor.run { self.isLoading = true }

            do {
                let weather = try await weatherKitService.weather(for: location)
                let current = weather.currentWeather

                let tempC         = current.temperature.converted(to: .celsius).value
                let apparentTempC = current.apparentTemperature.converted(to: .celsius).value
                let desc          = conditionDescription(current.condition)
                let humidity      = Int((current.humidity * 100).rounded())
                let windKph       = current.wind.speed.converted(to: .kilometersPerHour).value
                let windDir       = compassAbbreviation(current.wind.compassDirection)
                let visM          = Int(current.visibility.converted(to: .meters).value)
                let cloudPct      = Int((current.cloudCover * 100).rounded())
                let uvVal         = current.uvIndex.value
                let uvCat         = uvCategoryString(current.uvIndex.category)
                let pressureHPa   = current.pressure.converted(to: .hectopascals).value
                let isDaylight    = current.isDaylight
                let now = Date()
                let sortedHourly = weather.hourlyForecast.forecast.sorted(by: { $0.date < $1.date })
                let nextSixHours = sortedHourly.filter {
                    $0.date >= now && $0.date <= now.addingTimeInterval(6 * 60 * 60)
                }
                let nextSixChances = nextSixHours.map(\.precipitationChance)
                let meanNextSixChance = nextSixChances.isEmpty
                    ? nil
                    : nextSixChances.reduce(0, +) / Double(nextSixChances.count)
                let nearestHourChance = sortedHourly
                    .min(by: { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) })
                    .map(\.precipitationChance)
                let precipChance = meanNextSixChance ?? nearestHourChance
                let hourly = weather.hourlyForecast.forecast
                    .filter { $0.date >= now.addingTimeInterval(-1800) }
                    .sorted(by: { $0.date < $1.date })
                    .prefix(12)
                    .map { hour in
                    HourlyForecastPoint(
                        date: hour.date,
                        temperatureC: hour.temperature.converted(to: .celsius).value,
                        conditionDescription: self.conditionDescription(hour.condition),
                        isDaylight: hour.isDaylight
                    )
                }
                let daily = weather.dailyForecast.forecast
                    .filter { Calendar.current.startOfDay(for: $0.date) >= Calendar.current.startOfDay(for: now) }
                    .sorted(by: { $0.date < $1.date })
                    .prefix(7)
                    .map { day in
                    DailyForecastPoint(
                        date: day.date,
                        highC: day.highTemperature.converted(to: .celsius).value,
                        lowC: day.lowTemperature.converted(to: .celsius).value,
                        conditionDescription: self.conditionDescription(day.condition)
                    )
                }

                await MainActor.run {
                    self.currentTemperatureCelsius = tempC
                    self.currentWeatherDescription = desc
                    self.currentWeather = WeatherData(
                        temperature: tempC,
                        description: desc,
                        humidity: humidity,
                        windSpeed: windKph,
                        windDirection: windDir,
                        visibility: visM,
                        cloudCover: cloudPct,
                        locationName: nil,
                        apparentTemperature: apparentTempC,
                        uvIndex: uvVal,
                        uvCategory: uvCat,
                        pressure: pressureHPa,
                        isDaylight: isDaylight,
                        precipitationChance: precipChance
                    )
                    self.hourlyForecast = hourly
                    self.dailyForecast = daily
                    self.isLoading = false
                    print("🌤️ WeatherKit data updated: \(tempC)°C, \(desc)")
                }
            } catch {
                print("🌤️ WeatherKit fetch failed: \(error)")
                print("🌤️ Using local demo weather data")
                await loadMockWeather()
            }
        }
    }

    @MainActor
    private func loadMockWeather() {
        self.currentTemperatureCelsius = 22.0
        self.currentWeatherDescription = "partly cloudy"
        self.currentWeather = WeatherData(
            temperature: 22.0,
            description: "partly cloudy",
            humidity: 45,
            windSpeed: 12.0,
            windDirection: "NW",
            visibility: 10000,
            cloudCover: 30,
            locationName: nil,
            apparentTemperature: 24.0,
            uvIndex: 5,
            uvCategory: "Moderate",
            pressure: 1012.0,
            isDaylight: true,
            precipitationChance: 0.1
        )
        
        let now = Date()
        self.hourlyForecast = (1...12).map { i in
            HourlyForecastPoint(
                date: now.addingTimeInterval(Double(i) * 3600),
                temperatureC: 22.0 - (Double(i) * 0.5),
                conditionDescription: i > 6 ? "clear sky" : "partly cloudy",
                isDaylight: i < 8
            )
        }
        
        self.dailyForecast = (0...6).map { i in
            DailyForecastPoint(
                date: now.addingTimeInterval(Double(i) * 86400),
                highC: 24.0 + Double.random(in: -2...3),
                lowC: 14.0 + Double.random(in: -2...2),
                conditionDescription: i % 3 == 0 ? "clear sky" : "partly cloudy"
            )
        }
        
        self.isLoading = false
    }

    /// Maps a WeatherKit condition to a human-readable description string.
    private func conditionDescription(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear:                    return "clear sky"
        case .mostlyClear:              return "mostly clear"
        case .partlyCloudy:             return "partly cloudy"
        case .mostlyCloudy:             return "mostly cloudy"
        case .cloudy:                   return "cloudy"
        case .foggy:                    return "fog"
        case .haze:                     return "haze"
        case .smoky:                    return "smoky"
        case .breezy:                   return "breezy"
        case .windy:                    return "windy"
        case .drizzle:                  return "drizzle"
        case .rain:                     return "rain"
        case .heavyRain:                return "heavy rain"
        case .sleet:                    return "sleet"
        case .snow:                     return "snow"
        case .heavySnow:                return "heavy snow"
        case .blizzard:                 return "blizzard"
        case .freezingDrizzle:          return "freezing drizzle"
        case .freezingRain:             return "freezing rain"
        case .hail:                     return "hail"
        case .sunFlurries:              return "sun flurries"
        case .isolatedThunderstorms:    return "isolated thunderstorms"
        case .scatteredThunderstorms:   return "scattered thunderstorms"
        case .thunderstorms:            return "thunderstorms"
        case .strongStorms:             return "strong storms"
        case .tropicalStorm:            return "tropical storm"
        case .hurricane:                return "hurricane"
        case .hot:                      return "hot"
        case .frigid:                   return "frigid"
        default:                        return "cloudy"
        }
    }

    /// Converts a WeatherKit compass direction to a short abbreviation (e.g. "NNE").
    private func compassAbbreviation(_ dir: Wind.CompassDirection) -> String {
        switch dir {
        case .north:          return "N"
        case .northNortheast: return "NNE"
        case .northeast:      return "NE"
        case .eastNortheast:  return "ENE"
        case .east:           return "E"
        case .eastSoutheast:  return "ESE"
        case .southeast:      return "SE"
        case .southSoutheast: return "SSE"
        case .south:          return "S"
        case .southSouthwest: return "SSW"
        case .southwest:      return "SW"
        case .westSouthwest:  return "WSW"
        case .west:           return "W"
        case .westNorthwest:  return "WNW"
        case .northwest:      return "NW"
        case .northNorthwest: return "NNW"
        default:              return "—"
        }
    }

    /// Converts a WeatherKit UV exposure category to a display string.
    private func uvCategoryString(_ category: UVIndex.ExposureCategory) -> String {
        switch category {
        case .low:      return "Low"
        case .moderate: return "Moderate"
        case .high:     return "High"
        case .veryHigh: return "Very High"
        case .extreme:  return "Extreme"
        default:        return ""
        }
    }
}
