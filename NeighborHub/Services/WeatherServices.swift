import Combine
import CoreLocation
import Foundation
import SwiftUI

/// Lightweight location manager wrapper used by views that expect `WeatherLocationManager`.
final class WeatherLocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var currentCity: String = ""
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private let geocoder = CLGeocoder()
    private var isTrackingLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 100  // Update when user moves 100 meters
        authorizationStatus = manager.authorizationStatus
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func startLocationUpdates() {
        guard !isTrackingLocation else { return }
        guard
            authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        else {
            print("📍 Location not authorized, requesting permission")
            requestWhenInUse()
            return
        }

        print("📍 Starting continuous location updates")
        isTrackingLocation = true
        manager.startUpdatingLocation()
    }

    func stopLocationUpdates() {
        guard isTrackingLocation else { return }
        print("📍 Stopping continuous location updates")
        isTrackingLocation = false
        manager.stopUpdatingLocation()
    }

    func forceLocationRefresh() {
        print("📍 Force refreshing location")
        if isTrackingLocation {
            // If already tracking, request an immediate update
            manager.requestLocation()
        } else {
            // If not tracking, start tracking
            startLocationUpdates()
        }
    }
}

extension WeatherLocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        print("📍 Location updated: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
        currentLocation = loc

        // Update global app state
        DispatchQueue.main.async {
            AppState.shared.currentLocation = loc
        }

        // Reverse geocode to get detailed location name
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self = self, error == nil, let place = placemarks?.first else {
                print("📍 Geocoding failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            // Build a comprehensive location name
            var locationComponents: [String] = []

            // Add neighborhood or sub-locality if available
            if let subLocality = place.subLocality {
                locationComponents.append(subLocality)
            }

            // Add city/locality
            if let locality = place.locality {
                locationComponents.append(locality)
            } else if let subAdministrativeArea = place.subAdministrativeArea {
                locationComponents.append(subAdministrativeArea)
            } else if let administrativeArea = place.administrativeArea {
                locationComponents.append(administrativeArea)
            }

            let detailedLocation = locationComponents.joined(separator: ", ")
            let finalLocation = detailedLocation.isEmpty ? "Current Location" : detailedLocation

            print("📍 Detailed location resolved: \(finalLocation)")
            print(
                "📍 Available place info - Locality: \(place.locality ?? "nil"), SubLocality: \(place.subLocality ?? "nil"), SubAdmin: \(place.subAdministrativeArea ?? "nil"), Admin: \(place.administrativeArea ?? "nil")"
            )

            DispatchQueue.main.async {
                self.currentCity = finalLocation
                AppState.shared.currentLocation = loc
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 WeatherLocationManager error: \(error)")
    }

    func locationManager(
        _ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus
    ) {
        print("📍 Location authorization changed: \(status.rawValue)")
        authorizationStatus = status
        DispatchQueue.main.async {
            AppState.shared.authorizationStatus = status
        }

        // If authorized, start continuous location tracking
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            print("📍 Location authorized, starting continuous tracking")
            startLocationUpdates()
        } else if status == .denied || status == .restricted {
            print("📍 Location access denied/restricted, stopping updates")
            stopLocationUpdates()
        }
    }
}
