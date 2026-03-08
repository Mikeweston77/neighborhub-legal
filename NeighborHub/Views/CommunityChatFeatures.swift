import SwiftUI
import CoreLocation
import UIKit
import OSLog
// Firebase conditional import for Firestore usage
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

/*
 🚀 REAL BUSINESS API INTEGRATION SETUP
 
 To enable real business data, replace the placeholder API keys below:
 
 1. Google Places API:
    - Go to: https://console.cloud.google.com/
    - Enable Places API
    - Create credentials and replace: "AIzaSyCB90Wo8yTXSNdtukE3nEWXyjZBc3hPMQo"
 
 2. Current Status:
    - ✅ Uses actual location from weather service
    - ✅ Integrated with existing OpenWeatherMapService location
    - ✅ Real API structure ready
    - ⚠️  API keys need to be added for live data
    - 📍 Currently shows enhanced sample data until APIs are configured
    - ❌ Yelp API removed to simplify implementation
 */

// MARK: - Real Business API Service
class RealBusinessAPIService: NSObject, ObservableObject {
    private let googlePlacesAPIKey = "AIzaSyAR7GauIRyx8HWtUNoc0EqS2x59M79qcXE" // Replace with your real API key
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Google Places API Integration (Connected to AI Search)
    func searchGooglePlaces(query: String, location: CLLocation, radius: Int = 2000) async throws -> [LocalBusiness] {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        
        // Step 1: Use Google Places Text Search API to get place IDs
        let urlString = "https://maps.googleapis.com/maps/api/place/textsearch/json?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&location=\(lat),\(lng)&radius=\(radius)&key=\(googlePlacesAPIKey)"
        
        guard let url = URL(string: urlString) else {
            throw BusinessAPIError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(GooglePlacesResponse.self, from: data)
        
        // Step 2: Get detailed information for each place (including phone numbers)
        var detailedBusinesses: [LocalBusiness] = []
        
        for place in response.results.prefix(10) { // Limit to 10 to avoid rate limits
            do {
                let details = try await getPlaceDetails(placeId: place.place_id)
                let business = LocalBusiness(
                    id: UUID(),
                    name: details.name,
                    category: categorizeGooglePlace(place.types),
                    address: details.formatted_address ?? place.vicinity ?? "Address not available",
                    phone: details.formatted_phone_number, // Now includes phone number!
                    website: details.website,
                    description: "Real business from Google Places API",
                    rating: details.rating ?? place.rating ?? 0.0,
                    distance: calculateDistance(from: location, to: CLLocation(latitude: place.geometry.location.lat, longitude: place.geometry.location.lng)),
                    isOpen: details.opening_hours?.open_now ?? place.opening_hours?.open_now ?? false,
                    hours: details.opening_hours?.open_now == true ? "Open Now" : "Closed",
                    tags: place.types
                )
                detailedBusinesses.append(business)
            } catch {
                // If details fail, use basic info without phone
                let business = LocalBusiness(
                    id: UUID(),
                    name: place.name,
                    category: categorizeGooglePlace(place.types),
                    address: place.formatted_address ?? place.vicinity ?? "Address not available",
                    phone: nil, // No phone if details API fails
                    website: nil,
                    description: "Real business from Google Places API (limited details)",
                    rating: place.rating ?? 0.0,
                    distance: calculateDistance(from: location, to: CLLocation(latitude: place.geometry.location.lat, longitude: place.geometry.location.lng)),
                    isOpen: place.opening_hours?.open_now ?? false,
                    hours: place.opening_hours?.open_now == true ? "Open Now" : "Closed",
                    tags: place.types
                )
                detailedBusinesses.append(business)
            }
        }
        
        return detailedBusinesses
    }
    
    // New function to get detailed place information
    private func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        let fields = "name,formatted_address,formatted_phone_number,website,rating,opening_hours,geometry"
        let urlString = "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeId)&fields=\(fields)&key=\(googlePlacesAPIKey)"
        
        guard let url = URL(string: urlString) else {
            throw BusinessAPIError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(GooglePlaceDetailsResponse.self, from: data)
        
        return response.result
    }
    
    private func calculateDistance(from: CLLocation, to: CLLocation) -> Double {
        return from.distance(from: to) / 1000.0 // Convert meters to kilometers
    }
    
    private func categorizeGooglePlace(_ types: [String]) -> String {
        for type in types {
            switch type {
            case "restaurant", "food", "meal_takeaway":
                return "Restaurant"
            case "grocery_or_supermarket", "supermarket":
                return "Grocery"
            case "gas_station", "car_repair":
                return "Automotive"
            case "hospital", "pharmacy", "doctor":
                return "Healthcare"
            case "store", "shopping_mall":
                return "Retail"
            case "veterinary_care", "pet_store":
                return "Pet Services"
            default:
                continue
            }
        }
        return "Services"
    }
}

// MARK: - API Response Models
struct GooglePlacesResponse: Codable {
    let results: [GooglePlace]
    let status: String
}

struct GooglePlace: Codable {
    let place_id: String // Add place_id for details lookup
    let name: String
    let formatted_address: String?
    let vicinity: String?
    let rating: Double?
    let types: [String]
    let geometry: GoogleGeometry
    let opening_hours: GoogleOpeningHours?
}

// New structure for Place Details API response
struct GooglePlaceDetailsResponse: Codable {
    let result: GooglePlaceDetails
    let status: String
}

struct GooglePlaceDetails: Codable {
    let name: String
    let formatted_address: String?
    let formatted_phone_number: String? // Phone number from details API
    let website: String? // Website from details API
    let rating: Double?
    let geometry: GoogleGeometry?
    let opening_hours: GoogleDetailedOpeningHours?
}

struct GoogleDetailedOpeningHours: Codable {
    let open_now: Bool
    let weekday_text: [String]? // Detailed hours like "Monday: 9:00 AM – 5:00 PM"
}

struct GoogleGeometry: Codable {
    let location: GoogleLocation
}

struct GoogleLocation: Codable {
    let lat: Double
    let lng: Double
}

struct GoogleOpeningHours: Codable {
    let open_now: Bool
}

enum BusinessAPIError: Error, LocalizedError {
    case invalidURL
    case noAPIKey
    case networkError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .noAPIKey:
            return "API key not configured"
        case .networkError:
            return "Network request failed"
        case .decodingError:
            return "Failed to decode API response"
        }
    }
}

// MARK: - Enhanced Location Manager for Business Search
class EnhancedLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var userLocation: CLLocation?
    @Published var currentLocation: CLLocation? // For weather service compatibility
    @Published var currentCity: String = "Your Location" // For weather service compatibility
    @Published var currentNeighborhood: String = "Your Neighborhood"
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Integration with existing weather service location
    private var weatherService: OpenWeatherMapService?
    
    @MainActor
    func setWeatherService(_ weatherService: OpenWeatherMapService) {
        self.weatherService = weatherService
        
        // Use weather service location if available
        if let weatherLocation = weatherService.locationManager.currentLocation {
            self.userLocation = weatherLocation
            self.currentLocation = weatherLocation
            self.currentCity = weatherService.locationName
        }
    }
    
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100 // Update location every 100 meters
        requestLocationPermission()
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        isLoading = true
        errorMessage = nil
        
        // First, try to use weather service location if available
        Task { @MainActor in
            if let weatherService = weatherService,
               let weatherLocation = weatherService.locationManager.currentLocation {
                userLocation = weatherLocation
                currentLocation = weatherLocation
                currentCity = weatherService.locationName
                isLoading = false
                return
            }
            
            // Otherwise use standard location request
            performLocationRequest()
        }
    }
    
    private func performLocationRequest() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            errorMessage = "Location access denied. Please enable in Settings."
            isLoading = false
        @unknown default:
            errorMessage = "Unknown location authorization status."
            isLoading = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        userLocation = location
        currentLocation = location // For weather service compatibility
        
        locationManager.stopUpdatingLocation()
        
        // Reverse geocoding to get readable address
        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                await MainActor.run {
                    self.isLoading = false
                    
                    guard let placemark = placemarks.first else {
                        self.errorMessage = "No location information found"
                        return
                    }
                    
                    // Update location names
                    if let city = placemark.locality {
                        self.currentCity = city
                    }
                    if let neighborhood = placemark.subLocality ?? placemark.thoroughfare {
                        self.currentNeighborhood = neighborhood
                    } else if let area = placemark.subAdministrativeArea {
                        self.currentNeighborhood = area
                    }
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Failed to get location name: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        errorMessage = "Location error: \(error.localizedDescription)"
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Location access denied"
        case .notDetermined:
            break
        @unknown default:
            isLoading = false
            errorMessage = "Unknown authorization status"
        }
    }
    
    func calculateDistance(to business: LocalBusiness) -> Double {
        guard userLocation != nil else { return business.distance }
        
        // Use actual business coordinates if available from API
        return business.distance // API should provide real distance
    }
}

// MARK: - Business Detail View
struct BusinessDetailView: View {
    let business: LocalBusiness
    @Environment(\.dismiss) private var dismiss
    let onShareTap: (LocalBusiness) -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with business info
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: categoryIcon(for: business.category))
                                .foregroundColor(.orange)
                                .font(.title)
                                .frame(width: 40, height: 40)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(business.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text(business.category)
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(business.isOpen ? .green : .red)
                                        .frame(width: 10, height: 10)
                                    Text(business.isOpen ? "Open" : "Closed")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(business.isOpen ? .green : .red)
                                }
                                
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: "star.fill")
                                            .foregroundColor(Double(star) <= business.rating ? .yellow : .gray.opacity(0.3))
                                            .font(.caption)
                                    }
                                    Text(String(format: "%.1f", business.rating))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Text(business.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // Contact Information
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Contact Information")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 12) {
                            InfoRow(icon: "location", title: "Address", value: business.address, color: .blue)
                            
                            if let phone = business.phone {
                                InfoRow(
                                    icon: "phone", 
                                    title: "Phone", 
                                    value: phone, 
                                    color: .green, 
                                    isActionable: true,
                                    onTap: {
                                        if let url = URL(string: "tel:\(phone)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                )
                            }
                            
                            if let website = business.website {
                                InfoRow(
                                    icon: "globe", 
                                    title: "Website", 
                                    value: website, 
                                    color: .purple, 
                                    isActionable: true,
                                    onTap: {
                                        let urlString = website.hasPrefix("http") ? website : "https://\(website)"
                                        if let url = URL(string: urlString) {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                )
                            }
                            
                            InfoRow(icon: "clock", title: "Hours", value: business.hours, color: .orange)
                            InfoRow(icon: "location.circle", title: "Distance", value: String(format: "%.1f km away", business.distance), color: .gray)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // Tags
                    if !business.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tags")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 80))
                            ], spacing: 8) {
                                ForEach(business.tags, id: \.self) { tag in
                                    Text(tag.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            onShareTap(business)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share with Neighbors")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        
                        HStack(spacing: 12) {
                            if business.phone != nil {
                                Button(action: {
                                    if let phone = business.phone, let url = URL(string: "tel:\(phone)") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "phone.fill")
                                        Text("Call")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(12)
                                }
                            }
                            
                            Button(action: {
                                // Open in Maps
                                let address = business.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let url = URL(string: "http://maps.apple.com/?q=\(address)") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "map.fill")
                                    Text("Directions")
                                }
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .padding()
            }
            .background(Color(.systemGray6))
            .navigationTitle("Business Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case "restaurant": return "fork.knife"
        case "grocery": return "cart"
        case "services": return "wrench.and.screwdriver"
        case "healthcare": return "cross.case"
        case "automotive": return "car"
        case "retail": return "bag"
        case "pet services": return "pawprint"
        default: return "storefront"
        }
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    var isActionable: Bool = false
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
                    .foregroundColor(isActionable ? color : .primary)
            }
            
            Spacer()
            
            if isActionable {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isActionable, let onTap = onTap {
                onTap()
            }
        }
    }
}

// MARK: - Local Business Feature
struct LocalBusiness: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: String
    let address: String
    let phone: String?
    let website: String?
    let description: String
    let rating: Double
    let distance: Double // in miles
    let isOpen: Bool
    let hours: String
    let tags: [String]
}

struct BusinessSearchResult: Identifiable {
    let id: UUID
    let business: LocalBusiness
    let relevanceScore: Double
    let matchedTerm: String
    
    init(business: LocalBusiness, relevanceScore: Double, matchedTerm: String) {
        self.id = UUID()
        self.business = business
        self.relevanceScore = relevanceScore
        self.matchedTerm = matchedTerm
    }
}

class LocalBusinessManager: ObservableObject {
    @Published var businesses: [LocalBusiness] = []
    @Published var searchResults: [BusinessSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""
    @Published var showAllResults: Bool = false
    @Published var sortBy: SortOption = .distance
    @Published var hasLocationAccess: Bool = false
    @Published var locationError: String?
    
    let maxDisplayResults = 8
    @ObservedObject private var locationManager: EnhancedLocationManager
    private let realBusinessAPI = RealBusinessAPIService()
    private var searchWorkItem: DispatchWorkItem?
    
    // Integration with existing weather service
    private var weatherService: OpenWeatherMapService?
    
    enum SortOption: String, CaseIterable {
        case distance = "Distance"
        case rating = "Rating"
        case name = "Name"
        case open = "Open Now"
    }
    
    init(weatherService: OpenWeatherMapService? = nil) {
        // Initialize enhanced location manager
        let manager = EnhancedLocationManager()
        self.locationManager = manager
        self.weatherService = weatherService
        
        // Set weather service for location integration
        if let weatherService = weatherService {
            manager.setWeatherService(weatherService)
        }
        
        // Request location access on initialization
        manager.requestLocationPermission()
    }
    
    func searchBusinesses(query: String) {
        // Cancel previous search
        searchWorkItem?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            searchQuery = ""
            isSearching = false
            return
        }
        
        // Update query immediately
        searchQuery = query
        
        // Debounce the actual search
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isSearching = true
                self.locationError = nil
            }
            
            // Always show fallback results immediately for better UX
            Task {
                await self.loadFallbackBusinesses(query: query)
                
                // Try to get real location-based results in background
                let userLocation = self.weatherService?.locationManager.currentLocation ?? self.locationManager.userLocation
                
                if let location = userLocation {
                    // We have location, try to get real API results
                    await self.performRealBusinessSearch(query: query, location: location)
                } else {
                    // No location, but fallback results are already loading above
                    await MainActor.run {
                        self.locationError = "Enable location access for real nearby businesses. Showing sample results."
                    }
                    
                    // Try to get location for future searches
                    self.locationManager.requestLocation()
                }
            }
        }
        
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    @MainActor
    private func performRealBusinessSearch(query: String, location: CLLocation) async {
        var allBusinesses: [LocalBusiness] = []
        
        // Try Google Places API
        do {
            let googleBusinesses = try await realBusinessAPI.searchGooglePlaces(query: query, location: location)
            allBusinesses.append(contentsOf: googleBusinesses)
        } catch {
            print("Google Places API error: \(error.localizedDescription)")
        }
        
        if allBusinesses.isEmpty {
            // If API fails, show fallback message
            locationError = "Real business API unavailable. Enable API keys in RealBusinessAPIService for live data."
            await loadFallbackBusinesses(query: query)
        } else {
            // Process real business results
            businesses = removeDuplicateBusinesses(allBusinesses)
            searchResults = performBusinessSearch(query: query, businesses: businesses)
            isSearching = false
            locationError = nil
        }
    }
    
    private func removeDuplicateBusinesses(_ businesses: [LocalBusiness]) -> [LocalBusiness] {
        var seen = Set<String>()
        return businesses.filter { business in
            let key = "\(business.name.lowercased())_\(business.address.lowercased())"
            return seen.insert(key).inserted
        }
    }
    
    @MainActor
    private func loadFallbackBusinesses(query: String) async {
        // Use enhanced sample businesses that are more realistic
        let fallbackBusinesses = generateEnhancedSampleBusinesses(query: query)
        businesses = fallbackBusinesses
        searchResults = performBusinessSearch(query: query, businesses: fallbackBusinesses)
        isSearching = false
    }
    
    private func generateEnhancedSampleBusinesses(query: String) -> [LocalBusiness] {
        // Create more realistic sample businesses based on common US business types
        let sampleBusinesses = [
            LocalBusiness(id: UUID(), name: "Starbucks", category: "Restaurant", address: "123 Main St", phone: "(555) 123-4567", website: "starbucks.com", description: "Coffee chain - Enable API keys for real results", rating: 4.2, distance: 0.3, isOpen: true, hours: "6 AM - 10 PM", tags: ["coffee", "chain"]),
            LocalBusiness(id: UUID(), name: "Safeway", category: "Grocery", address: "456 Oak Ave", phone: "(555) 234-5678", website: "safeway.com", description: "Grocery store - Enable API keys for real results", rating: 3.8, distance: 0.5, isOpen: true, hours: "7 AM - 11 PM", tags: ["grocery", "supermarket"]),
            LocalBusiness(id: UUID(), name: "CVS Pharmacy", category: "Healthcare", address: "789 Pine St", phone: "(555) 345-6789", website: "cvs.com", description: "Pharmacy - Enable API keys for real results", rating: 3.9, distance: 0.4, isOpen: true, hours: "8 AM - 10 PM", tags: ["pharmacy", "health"]),
            LocalBusiness(id: UUID(), name: "Shell Gas Station", category: "Automotive", address: "321 Elm Dr", phone: "(555) 456-7890", website: "shell.com", description: "Gas station - Enable API keys for real results", rating: 3.6, distance: 0.6, isOpen: true, hours: "24 Hours", tags: ["gas", "fuel"]),
            LocalBusiness(id: UUID(), name: "Home Depot", category: "Retail", address: "654 Cedar Ln", phone: "(555) 567-8901", website: "homedepot.com", description: "Hardware store - Enable API keys for real results", rating: 4.1, distance: 0.8, isOpen: true, hours: "6 AM - 9 PM", tags: ["hardware", "home"]),
            LocalBusiness(id: UUID(), name: "McDonald's", category: "Restaurant", address: "987 Birch Way", phone: "(555) 678-9012", website: "mcdonalds.com", description: "Fast food - Enable API keys for real results", rating: 3.7, distance: 0.2, isOpen: true, hours: "5 AM - 12 AM", tags: ["fastfood", "chain"])
        ]
        
        // Filter based on query
        return sampleBusinesses.filter { business in
            let queryLower = query.lowercased()
            return business.name.lowercased().contains(queryLower) ||
                   business.category.lowercased().contains(queryLower) ||
                   business.tags.contains { $0.lowercased().contains(queryLower) }
        }
    }
    
    private func performBusinessSearch(query: String, businesses: [LocalBusiness]) -> [BusinessSearchResult] {
        let queryWords = query.lowercased().split(separator: " ").map(String.init)
        var results: [BusinessSearchResult] = []
        
        for business in businesses {
            var score: Double = 0
            var matchedTerm = ""
            
            // Exact name match (highest score)
            if business.name.lowercased().contains(query.lowercased()) {
                score += 15.0
                matchedTerm = business.name
            }
            
            // Category match
            if business.category.lowercased().contains(query.lowercased()) {
                score += 12.0
                if matchedTerm.isEmpty {
                    matchedTerm = business.category
                }
            }
            
            // Tags match
            for tag in business.tags {
                if tag.lowercased().contains(query.lowercased()) {
                    score += 8.0
                    if matchedTerm.isEmpty {
                        matchedTerm = tag
                    }
                }
            }
            
            // Description match
            if business.description.lowercased().contains(query.lowercased()) {
                score += 5.0
                if matchedTerm.isEmpty {
                    matchedTerm = query
                }
            }
            
            // Individual word matches
            for word in queryWords {
                if business.name.lowercased().contains(word) ||
                   business.category.lowercased().contains(word) ||
                   business.description.lowercased().contains(word) {
                    score += 2.0
                    if matchedTerm.isEmpty {
                        matchedTerm = word
                    }
                }
            }
            
            // Distance bonus (closer = higher score)
            if business.distance <= 0.5 {
                score += 5.0
            } else if business.distance <= 1.0 {
                score += 3.0
            } else if business.distance <= 2.0 {
                score += 1.0
            }
            
            // Rating bonus
            score += business.rating * 0.8
            
            // Open now bonus
            if business.isOpen {
                score += 2.0
            }
            
            if score > 0 {
                results.append(BusinessSearchResult(
                    business: business,
                    relevanceScore: score,
                    matchedTerm: matchedTerm
                ))
            }
        }
        
        // Sort by selected option
        return sortResults(results)
    }
    
    private func sortResults(_ results: [BusinessSearchResult]) -> [BusinessSearchResult] {
        switch sortBy {
        case .distance:
            return results.sorted { $0.business.distance < $1.business.distance }
        case .rating:
            return results.sorted { $0.business.rating > $1.business.rating }
        case .name:
            return results.sorted { $0.business.name < $1.business.name }
        case .open:
            return results.sorted { business1, business2 in
                if business1.business.isOpen && !business2.business.isOpen {
                    return true
                } else if !business1.business.isOpen && business2.business.isOpen {
                    return false
                } else {
                    return business1.relevanceScore > business2.relevanceScore
                }
            }
        }
    }
    
    func clearSearch() {
        searchWorkItem?.cancel()
        searchResults = []
        searchQuery = ""
        showAllResults = false
        isSearching = false
    }
    
    var displayedResults: [BusinessSearchResult] {
        if showAllResults {
            return searchResults
        } else {
            return Array(searchResults.prefix(maxDisplayResults))
        }
    }
    
    var hasMoreResults: Bool {
        return searchResults.count > maxDisplayResults
    }
    
    // MARK: - Integration with Weather Service
    func setWeatherService(_ weatherService: OpenWeatherMapService) {
        self.weatherService = weatherService
        self.locationManager.setWeatherService(weatherService)
    }
}

struct BusinessSearchResultsView: View {
    @ObservedObject var businessManager: LocalBusinessManager
    let onBusinessTap: (LocalBusiness) -> Void
    let onBusinessShare: (LocalBusiness) -> Void
    let onSendMessageToChat: ((String) -> Void)? // New callback for sending to chat
    let onSendBusinessListToChat: (([LocalBusiness]) -> Void)? // New callback for sending business list to chat
    @State private var selectedBusiness: LocalBusiness?
    @State private var showBusinessDetail = false
    
    var body: some View {
        if businessManager.isSearching {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Finding local businesses near you...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        } else if let locationError = businessManager.locationError {
            // Show location permission request
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "location.slash")
                        .foregroundColor(.orange)
                    Text("Location Required")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Spacer()
                }
                
                Text(locationError)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("To find real local businesses near you, please enable location access in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !businessManager.searchResults.isEmpty {
                    Text("Showing sample results for \"\(businessManager.searchQuery)\"")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 8)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(businessManager.displayedResults) { result in
                                BusinessCardView(
                                    business: result.business,
                                    matchedTerm: result.matchedTerm,
                                    relevanceScore: result.relevanceScore,
                                    onTap: {
                                        selectedBusiness = result.business
                                        showBusinessDetail = true
                                    },
                                    onShare: {
                                        onBusinessShare(result.business)
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .padding(.horizontal)
        } else if !businessManager.searchResults.isEmpty {
            StableBusinessResultsView(
                businessManager: businessManager,
                selectedBusiness: $selectedBusiness,
                showBusinessDetail: $showBusinessDetail,
                onBusinessTap: onBusinessTap,
                onBusinessShare: onBusinessShare,
                onSendMessageToChat: onSendMessageToChat,
                onSendBusinessListToChat: onSendBusinessListToChat
            )
        }
    }
}

// MARK: - Stable Business Results View (No Flashing)
struct StableBusinessResultsView: View {
    @ObservedObject var businessManager: LocalBusinessManager
    @Binding var selectedBusiness: LocalBusiness?
    @Binding var showBusinessDetail: Bool
    let onBusinessTap: (LocalBusiness) -> Void
    let onBusinessShare: (LocalBusiness) -> Void
    let onSendMessageToChat: ((String) -> Void)? // New callback for sending to chat
    let onSendBusinessListToChat: (([LocalBusiness]) -> Void)? // New callback for sending business list to chat
    @State private var showShareSheet = false
    @State private var showShareOptions = false // For action sheet
    @State private var shareText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Stable Header (No Animations)
            VStack(spacing: 12) {
                HStack {
                    // AI Icon
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.15))
                            .frame(width: 45, height: 45)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundColor(.cyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Text("Business Discovery")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            // Share All Results Button
                            Button(action: {
                                prepareShareText()
                                if onSendMessageToChat != nil {
                                    showShareOptions = true
                                } else {
                                    shareAllBusinesses()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up.fill")
                                        .font(.caption2)
                                    Text("Share All (\(businessManager.searchResults.count))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(8)
                                .shadow(color: .blue.opacity(0.2), radius: 1, x: 0, y: 1)
                            }
                            .accessibilityLabel("Share all \(businessManager.searchResults.count) business search results")
                            .accessibilityHint("Shares all found businesses with contact details to other apps")
                        }
                        
                        Text("\(businessManager.searchResults.count) matches found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Close Button
                    Button(action: {
                        businessManager.clearSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Sort Controls
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LocalBusinessManager.SortOption.allCases, id: \.self) { option in
                            Button(action: {
                                businessManager.sortBy = option
                            }) {
                                Text(option.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        businessManager.sortBy == option ?
                                        Color.blue : Color(.systemGray5)
                                    )
                                    .foregroundColor(
                                        businessManager.sortBy == option ?
                                        .white : .primary
                                    )
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            // Scrollable Business List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(businessManager.displayedResults) { result in
                        StableBusinessCard(
                            business: result.business,
                            matchedTerm: result.matchedTerm,
                            relevanceScore: result.relevanceScore,
                            onTap: {
                                selectedBusiness = result.business
                                showBusinessDetail = true
                            },
                            onShare: {
                                onBusinessShare(result.business)
                            }
                        )
                    }
                    
                    // Show More/Less Button
                    if businessManager.hasMoreResults {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                businessManager.showAllResults.toggle()
                            }
                        }) {
                            HStack {
                                Image(systemName: businessManager.showAllResults ? "chevron.up" : "chevron.down")
                                Text(businessManager.showAllResults ? 
                                     "Show Less" : 
                                     "Show \(businessManager.searchResults.count - businessManager.maxDisplayResults) More")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
                .padding(.top)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color(.systemGray6))
        .sheet(isPresented: $showBusinessDetail) {
            if let business = selectedBusiness {
                BusinessDetailView(business: business) { business in
                    onBusinessShare(business)
                }
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [shareText])
        }
        .confirmationDialog("Share Business Results", isPresented: $showShareOptions) {
            Button("Send to Chat") {
                sendToChat()
            }
            Button("Share to Other Apps") {
                shareToExternalApps()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("How would you like to share the \(businessManager.searchResults.count) business results?")
        }
    }
    
    private func prepareShareText() {
        let businessList = businessManager.searchResults.map { result in
            let business = result.business
            return """
            📍 \(business.name)
            🏷️ \(business.category) • ⭐ \(String(format: "%.1f", business.rating))/5.0
            📍 \(String(format: "%.1f km away", business.distance))
            📍 \(business.address)
            \(business.phone != nil ? "📞 \(business.phone!)" : "")
            \(business.isOpen ? "🟢 Open Now" : "🔴 Closed")
            """
        }.joined(separator: "\n\n")
        
        shareText = """
        🤖 Business Discovery Results for "\(businessManager.searchQuery)"
        
        Found \(businessManager.searchResults.count) local businesses in your neighborhood:
        
        \(businessList)
        
        📱 Shared from NeighborHub - Your Community App
        🏘️ Connecting neighbors, one discovery at a time!
        """
    }
    
    private func prepareBusinessListData() -> [LocalBusiness] {
        return businessManager.searchResults.map { $0.business }
    }
    
    private func sendToChat() {
        // Use business list callback if available (for better chat experience)
        if let businessListCallback = onSendBusinessListToChat {
            let businessList = prepareBusinessListData()
            businessListCallback(businessList)
        } else {
            // Fallback to text callback
            onSendMessageToChat?(shareText)
        }
    }
    
    private func shareToExternalApps() {
        showShareSheet = true
    }
    
    // Legacy function for backward compatibility
    private func shareAllBusinesses() {
        prepareShareText()
        showShareSheet = true
    }
}

// MARK: - Stable Business Card (No Animations)
struct StableBusinessCard: View {
    let business: LocalBusiness
    let matchedTerm: String
    let relevanceScore: Double
    let onTap: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Business Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: categoryIcon(for: business.category))
                        .font(.title2)
                        .foregroundColor(.cyan)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // Business Name and Status
                    HStack {
                        Text(business.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(business.isOpen ? .green : .red)
                                .frame(width: 6, height: 6)
                            Text(business.isOpen ? "Open" : "Closed")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(business.isOpen ? .green : .red)
                        }
                    }
                    
                    // Category
                    Text(business.category)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Phone Number (if available)
                    if let phone = business.phone {
                        Button(action: {
                            if let url = URL(string: "tel:\(phone)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Text(phone)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .fontDesign(.monospaced)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Rating and Distance
                    HStack {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(Double(star) <= business.rating ? .yellow : .gray.opacity(0.3))
                            }
                            Text(String(format: "%.1f", business.rating))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Image(systemName: "location")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(String(format: "%.1f km", business.distance))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Matched Term
                    if !matchedTerm.isEmpty {
                        Text("Match: \(matchedTerm)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                Button(action: onTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("View Details")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Button(action: onShare) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case "restaurant": return "fork.knife"
        case "grocery": return "cart"
        case "services": return "wrench.and.screwdriver"
        case "healthcare": return "cross.case"
        case "automotive": return "car"
        case "retail": return "bag"
        case "pet services": return "pawprint"
        default: return "building.2"
        }
    }
}

// Note: ShareSheet is defined in ShareSheet.swift to avoid duplication

// MARK: - Legacy Support
struct BusinessCardView: View {
    let business: LocalBusiness
    let matchedTerm: String
    let relevanceScore: Double
    let onTap: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        // Use the new stable business card
        StableBusinessCard(
            business: business,
            matchedTerm: matchedTerm,
            relevanceScore: relevanceScore,
            onTap: onTap,
            onShare: onShare
        )
    }
}

// MARK: - Shared Business Card for Chat
struct SharedBusinessCard: Identifiable, Codable {
    let id: UUID
    let business: LocalBusiness
    let sharedBy: String
    let sharedAt: Date
    let messageText: String
    
    init(business: LocalBusiness, sharedBy: String, messageText: String = "") {
        self.id = UUID()
        self.business = business
        self.sharedBy = sharedBy
        self.sharedAt = Date()
        self.messageText = messageText.isEmpty ? "Check out this local business!" : messageText
    }
}

struct SharedBusinessCardView: View {
    let sharedCard: SharedBusinessCard
    @State private var showBusinessDetail = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Shared message text
            if !sharedCard.messageText.isEmpty {
                Text(sharedCard.messageText)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            // Business card
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: categoryIcon(for: sharedCard.business.category))
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sharedCard.business.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        
                        Text(sharedCard.business.category)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Phone Number (if available)
                        if let phone = sharedCard.business.phone {
                            Button(action: {
                                if let url = URL(string: "tel:\(phone)") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "phone.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                    Text(phone)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                        .fontDesign(.monospaced)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        HStack {
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundColor(Double(star) <= sharedCard.business.rating ? .yellow : .gray.opacity(0.3))
                                }
                                Text(String(format: "%.1f", sharedCard.business.rating))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(String(format: "%.1f km", sharedCard.business.distance))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Circle()
                            .fill(sharedCard.business.isOpen ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(sharedCard.business.isOpen ? "Open" : "Closed")
                            .font(.caption2)
                            .foregroundColor(sharedCard.business.isOpen ? .green : .red)
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                
                // Action buttons
                HStack(spacing: 0) {
                    Button(action: {
                        showBusinessDetail = true
                    }) {
                        HStack {
                            Image(systemName: "info.circle")
                            Text("Details")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    Button(action: {
                        // Open in Maps
                        let address = sharedCard.business.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "http://maps.apple.com/?q=\(address)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "map")
                            Text("Directions")
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                    }
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
            
            // Shared by info
            HStack {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Shared by \(sharedCard.sharedBy)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(sharedCard.sharedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showBusinessDetail) {
            BusinessDetailView(business: sharedCard.business) { business in
                // Handle share from detail view
            }
            .presentationDetents([.fraction(0.75), .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case "restaurant": return "fork.knife"
        case "grocery": return "cart"
        case "services": return "wrench.and.screwdriver"
        case "healthcare": return "cross.case"
        case "automotive": return "car"
        case "retail": return "bag"
        case "pet services": return "pawprint"
        default: return "storefront"
        }
    }
}

// MARK: - AI Search Feature
struct SearchResult: Identifiable {
    let id: UUID
    let message: CommunityMessage
    let relevanceScore: Double
    let matchedText: String
    
    init(message: CommunityMessage, relevanceScore: Double, matchedText: String) {
        self.id = UUID()
        self.message = message
        self.relevanceScore = relevanceScore
        self.matchedText = matchedText
    }
}

class AISearchManager: ObservableObject {

    /// Public method to trigger a business search regardless of query content
    func searchBusinesses(query: String, in messages: [CommunityMessage]) {
        // Cancel previous search
        searchWorkItem?.cancel()
        guard !query.isEmpty else {
            businessResults = []
            searchResults = []
            searchQuery = ""
            isSearching = false
            locationError = nil
            return
        }
        searchQuery = query
        searchType = .businesses
        isSearching = true
        locationError = nil
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task {
                await self.performBusinessSearch(query: query)
            }
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    @Published var searchResults: [SearchResult] = []
    @Published var businessResults: [BusinessSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""
    @Published var showAllResults: Bool = false
    @Published var searchType: SearchType = .messages
    @Published var locationError: String?
    
    let maxDisplayResults = 10
    private var searchWorkItem: DispatchWorkItem?
    private let realBusinessAPI = RealBusinessAPIService()
    private var locationManager: EnhancedLocationManager?
    
    enum SearchType {
        case messages
        case businesses
    }
    
    // MARK: - Initialization
    init(locationManager: EnhancedLocationManager? = nil) {
        self.locationManager = locationManager
    }
    
    func setLocationManager(_ locationManager: EnhancedLocationManager) {
        self.locationManager = locationManager
    }
    
    func search(query: String, in messages: [CommunityMessage]) {
        // Cancel previous search
        searchWorkItem?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            businessResults = []
            searchQuery = ""
            isSearching = false
            locationError = nil
            return
        }
        
        // Update query immediately but debounce the actual search
        searchQuery = query
        searchType = determineSearchType(query: query)
        isSearching = true
        locationError = nil
        
        // Debounce search by 300ms to prevent excessive updates
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            Task {
                if self.searchType == .businesses {
                    // Perform business search using Google API
                    await self.performBusinessSearch(query: query)
                } else {
                    // Perform message search
                    let results = self.performAISearch(query: query, messages: messages)
                    
                    await MainActor.run {
                        self.searchResults = results
                        self.businessResults = []
                        self.isSearching = false
                    }
                }
            }
        }
        
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    private func determineSearchType(query: String) -> SearchType {
        let businessKeywords = ["restaurant", "food", "grocery", "store", "shop", "business", "service", "gas", "pharmacy", "hospital", "doctor", "cafe", "coffee", "bar", "hotel", "gym", "nail", "salon", "bank", "atm", "repair", "auto", "mechanic", "dentist", "vet", "locksmith", "plumber", "electrician", "service", "local", "nearby", "delivery", "takeout", "nearby", "local", "businesses"]
        let queryLower = query.lowercased()
        
        for keyword in businessKeywords {
            if queryLower.contains(keyword) {
                return .businesses
            }
        }
        
        return .messages
    }
    
    // MARK: - Google API Business Search
    @MainActor
    private func performBusinessSearch(query: String) async {
        // Always show fallback sample results immediately for best UX
        let fallbackBusinesses = generateFallbackBusinessResults(query: query)
        businessResults = fallbackBusinesses
        searchResults = []
        isSearching = false

        // Now try to get real business results in the background (if API key and location are set up)
        guard let locationManager = locationManager,
              let userLocation = locationManager.userLocation ?? locationManager.currentLocation else {
            locationError = "Location or API unavailable. Showing sample results."
            return
        }
        do {
            let businesses = try await realBusinessAPI.searchGooglePlaces(query: query, location: userLocation)
            let businessSearchResults = businesses.map { business in
                BusinessSearchResult(
                    business: business,
                    relevanceScore: calculateBusinessRelevance(business: business, query: query),
                    matchedTerm: findBusinessMatchedTerm(business: business, query: query)
                )
            }.sorted { $0.relevanceScore > $1.relevanceScore }
            if !businessSearchResults.isEmpty {
                businessResults = businessSearchResults
                locationError = nil
            }
        } catch {
            locationError = "Google API unavailable. Showing sample results. Error: \(error.localizedDescription)"
        }
    }
    
    private func calculateBusinessRelevance(business: LocalBusiness, query: String) -> Double {
        var score: Double = 0
        let queryLower = query.lowercased()
        
        // Name match (highest score)
        if business.name.lowercased().contains(queryLower) {
            score += 20.0
        }
        
        // Category match
        if business.category.lowercased().contains(queryLower) {
            score += 15.0
        }
        
        // Tags match
        for tag in business.tags {
            if tag.lowercased().contains(queryLower) {
                score += 10.0
                break
            }
        }
        
        // Description match
        if business.description.lowercased().contains(queryLower) {
            score += 8.0
        }
        
        // Distance bonus (closer = higher score)
        if business.distance <= 0.5 {
            score += 10.0
        } else if business.distance <= 1.0 {
            score += 6.0
        } else if business.distance <= 2.0 {
            score += 3.0
        }
        
        // Rating bonus
        score += business.rating * 2.0
        
        // Open now bonus
        if business.isOpen {
            score += 5.0
        }
        
        return score
    }
    
    private func findBusinessMatchedTerm(business: LocalBusiness, query: String) -> String {
        let queryLower = query.lowercased()
        
        if business.name.lowercased().contains(queryLower) {
            return business.name
        }
        
        if business.category.lowercased().contains(queryLower) {
            return business.category
        }
        
        for tag in business.tags {
            if tag.lowercased().contains(queryLower) {
                return tag
            }
        }
        
        return query
    }
    
    private func generateFallbackBusinessResults(query: String) -> [BusinessSearchResult] {
        // Enhanced fallback businesses with better variety
        let fallbackBusinesses = [
            LocalBusiness(id: UUID(), name: "Starbucks Coffee", category: "Restaurant", address: "123 Main St", phone: "(555) 123-4567", website: "starbucks.com", description: "Coffee chain - Real API unavailable", rating: 4.2, distance: 0.3, isOpen: true, hours: "6 AM - 10 PM", tags: ["coffee", "chain", "cafe"]),
            LocalBusiness(id: UUID(), name: "Whole Foods Market", category: "Grocery", address: "456 Oak Ave", phone: "(555) 234-5678", website: "wholefoodsmarket.com", description: "Organic grocery store - Real API unavailable", rating: 4.1, distance: 0.8, isOpen: true, hours: "7 AM - 10 PM", tags: ["grocery", "organic", "supermarket"]),
            LocalBusiness(id: UUID(), name: "CVS Pharmacy", category: "Healthcare", address: "789 Pine St", phone: "(555) 345-6789", website: "cvs.com", description: "Pharmacy and health store - Real API unavailable", rating: 3.9, distance: 0.4, isOpen: true, hours: "8 AM - 10 PM", tags: ["pharmacy", "health", "medicine"]),
            LocalBusiness(id: UUID(), name: "Shell Gas Station", category: "Automotive", address: "321 Elm Dr", phone: "(555) 456-7890", website: "shell.com", description: "Gas station with convenience store - Real API unavailable", rating: 3.6, distance: 0.6, isOpen: true, hours: "24 Hours", tags: ["gas", "fuel", "convenience"]),
            LocalBusiness(id: UUID(), name: "Best Buy", category: "Retail", address: "654 Cedar Ln", phone: "(555) 567-8901", website: "bestbuy.com", description: "Electronics retailer - Real API unavailable", rating: 4.0, distance: 1.2, isOpen: true, hours: "10 AM - 9 PM", tags: ["electronics", "tech", "retail"]),
            LocalBusiness(id: UUID(), name: "Chipotle Mexican Grill", category: "Restaurant", address: "987 Birch Way", phone: "(555) 678-9012", website: "chipotle.com", description: "Fast casual Mexican food - Real API unavailable", rating: 4.3, distance: 0.5, isOpen: true, hours: "11 AM - 10 PM", tags: ["mexican", "fastcasual", "burrito"])
        ]
        
        return fallbackBusinesses
            .filter { business in
                let queryLower = query.lowercased()
                return business.name.lowercased().contains(queryLower) ||
                       business.category.lowercased().contains(queryLower) ||
                       business.tags.contains { $0.lowercased().contains(queryLower) } ||
                       business.description.lowercased().contains(queryLower)
            }
            .map { business in
                BusinessSearchResult(
                    business: business,
                    relevanceScore: calculateBusinessRelevance(business: business, query: query),
                    matchedTerm: findBusinessMatchedTerm(business: business, query: query)
                )
            }
            .sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    private func performAISearch(query: String, messages: [CommunityMessage]) -> [SearchResult] {
        let queryWords = query.lowercased().split(separator: " ").map(String.init)
        var results: [SearchResult] = []
        
        for message in messages {
            var score: Double = 0
            var matchedText = ""
            
            // Check username match
            if message.user.lowercased().contains(query.lowercased()) {
                score += 15.0
                matchedText = message.user
            }
            
            // Check message content match
            if message.text.lowercased().contains(query.lowercased()) {
                score += 10.0
                if matchedText.isEmpty {
                    // Find the exact matched part
                    let content = message.text.lowercased()
                    let queryLower = query.lowercased()
                    if let range = content.range(of: queryLower) {
                        let start = max(content.startIndex, content.index(range.lowerBound, offsetBy: -10, limitedBy: content.startIndex) ?? content.startIndex)
                        let end = min(content.endIndex, content.index(range.upperBound, offsetBy: 10, limitedBy: content.endIndex) ?? content.endIndex)
                        matchedText = String(content[start..<end])
                    } else {
                        matchedText = String(message.text.prefix(50))
                    }
                }
            }
            
            // Check individual word matches
            for word in queryWords {
                if message.text.lowercased().contains(word) || message.user.lowercased().contains(word) {
                    score += 3.0
                    if matchedText.isEmpty {
                        matchedText = word
                    }
                }
            }
            
            // Boost recent messages
            let daysSinceMessage = Calendar.current.dateComponents([.day], from: message.timestamp, to: Date()).day ?? 0
            if daysSinceMessage <= 1 {
                score += 5.0
            } else if daysSinceMessage <= 7 {
                score += 2.0
            }
            
            if score > 0 {
                results.append(SearchResult(
                    message: message,
                    relevanceScore: score,
                    matchedText: matchedText
                ))
            }
        }
        
        // Sort by relevance score and return top results
        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    func clearSearch() {
        searchWorkItem?.cancel()
        searchResults = []
        businessResults = []
        searchQuery = ""
        showAllResults = false
        isSearching = false
        locationError = nil
    }
    
    var displayedResults: [SearchResult] {
        if showAllResults {
            return searchResults
        } else {
            return Array(searchResults.prefix(maxDisplayResults))
        }
    }
    
    var displayedBusinessResults: [BusinessSearchResult] {
        if showAllResults {
            return businessResults
        } else {
            return Array(businessResults.prefix(maxDisplayResults))
        }
    }
    
    var hasMoreResults: Bool {
        if searchType == .businesses {
            return businessResults.count > maxDisplayResults
        } else {
            return searchResults.count > maxDisplayResults
        }
    }
}

/*
 AISearchResultsView and SearchResultCard moved to Views/AISearchResultsView.swift
 and Views/SearchResultCard.swift respectively.
 The original implementations were large and slowed down Swift compiler type-checking.
*/

// MARK: - Type Aliases for Compatibility
// Provide aliases to make types available to other files that expect them
typealias LocationManager = EnhancedLocationManager

// MARK: - Pinned Messages Feature (Enhanced with Persistence)
struct PinnedMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let messageId: UUID
    let text: String
    let user: String
    let timestamp: Date
    let pinnedBy: String // Who pinned the message
    let pinnedAt: Date   // When it was pinned
}

class PinnedMessagesManager: ObservableObject {
    @Published var pinnedMessages: [PinnedMessage] = [] {
        didSet {
            savePinnedMessagesLocally() // Keep local backup
        }
    }
    
    @Published var isCollapsed: Bool = false {
        didSet {
            saveCollapsedState()
        }
    }
    
    private let pinnedMessagesKey = "pinnedMessagesKey"
    private let collapsedStateKey = "pinnedMessagesCollapsed"
    #if canImport(FirebaseFirestore)
    private var firestoreListener: ListenerRegistration?
    #endif
    
    init() {
        loadPinnedMessagesLocally()
        loadCollapsedState()
        startFirebaseListener()
    }
    
    deinit {
        firestoreListener?.remove()
    }
    
    // MARK: - Firebase Integration
    private func startFirebaseListener() {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        // Listen to dedicated pinnedMessages collection (persists even after original message deletion)
        let pinnedMessagesRef = db.collection("pinnedMessages")
        
        firestoreListener = pinnedMessagesRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ PinnedMessagesManager: Error listening to pinnedMessages: \(error.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ PinnedMessagesManager: No pinned messages found")
                return
            }
            
            print("📥 PinnedMessagesManager: Received \(documents.count) pinned messages")
            
            // Parse pinned messages from dedicated collection
            let pinnedMessages = documents.compactMap { document -> PinnedMessage? in
                let data = document.data()
                
                guard let messageIdString = data["messageId"] as? String,
                      let messageId = UUID(uuidString: messageIdString),
                      let text = data["text"] as? String,
                      let user = data["user"] as? String,
                      let timestampFirestore = data["timestamp"] as? Timestamp,
                      let pinnedBy = data["pinnedBy"] as? String,
                      let pinnedAtFirestore = data["pinnedAt"] as? Timestamp else {
                    print("⚠️ PinnedMessagesManager: Failed to parse pinned message: \(document.documentID)")
                    return nil
                }
                
                print("📌 Found pinned message: '\(text.prefix(30))...' by \(user), pinned by \(pinnedBy)")
                
                return PinnedMessage(
                    id: UUID(uuidString: document.documentID) ?? UUID(),
                    messageId: messageId,
                    text: text,
                    user: user,
                    timestamp: timestampFirestore.dateValue(),
                    pinnedBy: pinnedBy,
                    pinnedAt: pinnedAtFirestore.dateValue()
                )
            }.sorted { $0.pinnedAt > $1.pinnedAt } // Sort by pinnedAt descending
            
            DispatchQueue.main.async {
                print("✅ PinnedMessagesManager: Updated with \(pinnedMessages.count) pinned messages")
                self.pinnedMessages = pinnedMessages
            }
        }
        #endif
    }
    
    func pin(message: CommunityMessage, isAdmin: Bool, pinnedBy: String) {
        guard isAdmin else {
            print("PinnedMessagesManager: Non-admin user attempted to pin message")
            return
        }
        
        // Don't pin if already pinned
        if pinnedMessages.contains(where: { $0.messageId == message.id }) {
            print("PinnedMessagesManager: Message \(message.id) is already pinned")
            return
        }
        
        // Create a copy of the message in the pinnedMessages collection
        pinMessageInFirestore(message: message, pinnedBy: pinnedBy)
    }
    
    private func pinMessageInFirestore(message: CommunityMessage, pinnedBy: String) {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        
        // Create a new document in pinnedMessages collection with the message content
        let pinnedMessageRef = db.collection("pinnedMessages").document(message.id.uuidString)
        
        print("📌 PinnedMessagesManager: Creating pinned message copy")
        print("   Document path: pinnedMessages/\(message.id.uuidString)")
        print("   Message text: \(message.text.prefix(50))...")
        print("   Original author: \(message.user)")
        print("   Pinned by: \(pinnedBy)")
        
        // Create a persistent copy of the message data
        let pinnedMessageData: [String: Any] = [
            "messageId": message.id.uuidString,
            "text": message.text,
            "user": message.user,
            "timestamp": Timestamp(date: message.timestamp),
            "pinnedBy": pinnedBy,
            "pinnedAt": Timestamp(date: Date()),
            "messageType": message.messageType.rawValue,
            "imageURL": message.imageURL?.absoluteString ?? "",
            "fileURL": message.fileURL?.absoluteString ?? "",
            "audioURL": message.audioURL?.absoluteString ?? "",
            "fileName": message.fileName ?? ""
        ]
        
        pinnedMessageRef.setData(pinnedMessageData) { error in
            if let error = error {
                print("❌ PinnedMessagesManager: Error creating pinned message: \(error.localizedDescription)")
            } else {
                print("✅ PinnedMessagesManager: Successfully created pinned message copy")
                
                // Also update the original message to mark it as pinned
                let messageRef = db.collection("communityMessages").document(message.id.uuidString)
                messageRef.updateData([
                    "pinned": true,
                    "pinnedBy": pinnedBy,
                    "pinnedAt": Timestamp(date: Date())
                ]) { updateError in
                    if let updateError = updateError {
                        print("⚠️ PinnedMessagesManager: Error marking original message as pinned: \(updateError.localizedDescription)")
                    } else {
                        print("✅ PinnedMessagesManager: Original message marked as pinned")
                    }
                }
            }
        }
        #endif
    }
    
    func unpin(messageId: UUID, isAdmin: Bool) {
        guard isAdmin else {
            print("PinnedMessagesManager: Non-admin user attempted to unpin message")
            return
        }
        
        // Delete the pinned message from the pinnedMessages collection
        unpinMessageInFirestore(messageId: messageId)
    }
    
    private func unpinMessageInFirestore(messageId: UUID) {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        
        print("📍 PinnedMessagesManager: Attempting to unpin message \(messageId)")
        print("   Deleting from: pinnedMessages/\(messageId.uuidString)")
        
        // Delete the pinned message document
        let pinnedMessageRef = db.collection("pinnedMessages").document(messageId.uuidString)
        pinnedMessageRef.delete() { error in
            if let error = error {
                print("❌ PinnedMessagesManager: Error deleting pinned message: \(error.localizedDescription)")
            } else {
                print("✅ PinnedMessagesManager: Successfully deleted pinned message")
                
                // Also update the original message if it still exists
                let messageRef = db.collection("communityMessages").document(messageId.uuidString)
                messageRef.updateData([
                    "pinned": false,
                    "pinnedBy": FieldValue.delete(),
                    "pinnedAt": FieldValue.delete()
                ]) { updateError in
                    if let updateError = updateError {
                        print("⚠️ PinnedMessagesManager: Could not update original message (may be deleted): \(updateError.localizedDescription)")
                    } else {
                        print("✅ PinnedMessagesManager: Original message unmarked as pinned")
                    }
                }
            }
        }
        #endif
    }
    
    func isPinned(messageId: UUID) -> Bool {
        pinnedMessages.contains(where: { $0.messageId == messageId })
    }
    
    func toggleCollapsed() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isCollapsed.toggle()
        }
    }
    
    // MARK: - Local Storage (Backup)
    private func savePinnedMessagesLocally() {
        if let data = try? JSONEncoder().encode(pinnedMessages) {
            UserDefaults.standard.set(data, forKey: pinnedMessagesKey)
        }
    }
    
    private func loadPinnedMessagesLocally() {
        if let data = UserDefaults.standard.data(forKey: pinnedMessagesKey),
           let saved = try? JSONDecoder().decode([PinnedMessage].self, from: data) {
            // Only load locally if we don't have Firebase data yet
            if pinnedMessages.isEmpty {
                pinnedMessages = saved
            }
        }
    }
    
    private func saveCollapsedState() {
        UserDefaults.standard.set(isCollapsed, forKey: collapsedStateKey)
    }
    
    private func loadCollapsedState() {
        isCollapsed = UserDefaults.standard.bool(forKey: collapsedStateKey)
    }
}

struct PinnedMessagesView: View {
    @ObservedObject var manager: PinnedMessagesManager
    let isAdmin: Bool
    
    // Helper function to extract first name
    private func extractFirstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: " ")
        return components.first?.capitalized ?? trimmed
    }
    
    var body: some View {
        if !manager.pinnedMessages.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Compact header button when collapsed, full header when expanded
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        manager.toggleCollapsed()
                    }
                }) {
                    if manager.isCollapsed {
                        // Compact collapsed state - slightly larger minimal pill
                        HStack(spacing: 8) {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            
                            Text("\(manager.pinnedMessages.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                    } else {
                        // Full expanded header
                        HStack {
                            Image(systemName: "pin.fill")
                                .foregroundColor(.orange)
                                .font(.headline)
                            
                            Text("Pinned Messages")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Message count badge
                            Text("\(manager.pinnedMessages.count)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .cornerRadius(12)
                            
                            // Collapse chevron
                            Image(systemName: "chevron.up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                
                // Pinned messages content (collapsible)
                if !manager.isCollapsed {
                    // Make content scrollable when there are many pinned messages.
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
                            ForEach(manager.pinnedMessages) { pinned in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top, spacing: 12) {
                                        // Pin icon
                                        Image(systemName: "pin.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                            .padding(.top, 2)

                                        // Message content
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(pinned.text)
                                                .font(.body)
                                                .lineLimit(nil)
                                                .fixedSize(horizontal: false, vertical: true)

                                            HStack {
                                                Text("by ") + Text(extractFirstName(from: pinned.user)).bold()
                                                Spacer()
                                                Text(pinned.timestamp, style: .time)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            
                                            // Show who pinned and when
                                            HStack {
                                                Text("Pinned by ") + Text(extractFirstName(from: pinned.pinnedBy)).bold()
                                                Spacer()
                                                Text(pinned.pinnedAt, style: .relative)
                                                    .font(.caption2)
                                                    .foregroundColor(.orange.opacity(0.8))
                                            }
                                            .font(.caption2)
                                            .foregroundColor(.orange.opacity(0.7))
                                        }

                                        Spacer()

                                        // Admin-only unpin button
                                        if isAdmin {
                                            Button(action: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    manager.unpin(messageId: pinned.messageId, isAdmin: isAdmin)
                                                }
                                            }) {
                                                Image(systemName: "pin.slash.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.red)
                                                    .padding(8)
                                                    .background(Color.red.opacity(0.1))
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    // Divider between pinned messages (except last)
                                    if pinned.id != manager.pinnedMessages.last?.id {
                                        Divider()
                                            .background(Color.orange.opacity(0.2))
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }

                            // Admin help text
                            if isAdmin && manager.pinnedMessages.count < 5 {
                                HStack {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text("Long press any message to pin it for the community")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            }
                        }
                    }
                    .background(
                        // Use a translucent material so the popup is more transparent
                        RoundedRectangle(cornerRadius: 0)
                            .fill(.ultraThinMaterial)
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
            .background(manager.isCollapsed ? Color.clear : Color(.systemBackground))
            .cornerRadius(manager.isCollapsed ? 0 : 16)
            .overlay(
                RoundedRectangle(cornerRadius: manager.isCollapsed ? 0 : 16)
                    .stroke(manager.isCollapsed ? Color.clear : Color.orange.opacity(0.3), lineWidth: 1)
            )
            .shadow(
                color: manager.isCollapsed ? .clear : .black.opacity(0.1), 
                radius: manager.isCollapsed ? 0 : 4, 
                x: 0, 
                y: manager.isCollapsed ? 0 : 2
            )
            .padding(.horizontal, manager.isCollapsed ? 16 : 16)
            .padding(.vertical, manager.isCollapsed ? 4 : 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.isCollapsed)
        }
    }
}
