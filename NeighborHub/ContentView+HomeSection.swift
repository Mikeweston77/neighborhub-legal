import Foundation
import SwiftUI

// Provide a lightweight HomeSection enum attached to ContentView so existing code compiles.
extension ContentView {
    enum HomeSection: Int, CaseIterable {
        case weather
        case polls
        case requestHelp
        case stats
        case reminders
        case events
        case localAdverts
        case newsletters
        case community
        case marketplace
    }
}
