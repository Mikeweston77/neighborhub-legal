import Combine
import CoreLocation
import Foundation
import SwiftUI

final class AppState: ObservableObject {
    // Controls global presentation of the settings sheet
    @Published var showingSettings: Bool = false

    // Selected tab index used by ContentView/TabView
    @Published var selectedTab: Int = 0

    // Location authorization and last known location (used by several views)
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?

    // Shared singleton for services and legacy callers that update global state
    static let shared = AppState()

    // Keep default initializer public so other files can create instances if required
    public init() {}

    func refreshLocationAndWeather() {
        // Notify all location managers to refresh their data
        NotificationCenter.default.post(name: .refreshLocationAndWeather, object: nil)
        print("📱 AppState: Posted location and weather refresh notification")
    }
}

extension Notification.Name {
    static let refreshLocationAndWeather = Notification.Name("refreshLocationAndWeather")
}
