import SwiftUI

struct NotificationSettingsView: View {
    @AppStorage("notifyEvents") private var notifyEvents: Bool = true
    @AppStorage("notifyIssues") private var notifyIssues: Bool = true
    @AppStorage("notifyAssistance") private var notifyAssistance: Bool = true
    @AppStorage("notifyMarketplace") private var notifyMarketplace: Bool = true
    @AppStorage("notifyAll") private var notifyAll: Bool = true

    var body: some View {
        Form {
            Section(header: Text("Notification Preferences")) {
                // Removed 'Enable All Notifications' toggle
                Toggle("Event Notifications", isOn: $notifyEvents)
                Toggle("Issue Notifications", isOn: $notifyIssues)
                Toggle("Assistance Notifications", isOn: $notifyAssistance)
                Toggle("Marketplace Item Notifications", isOn: $notifyMarketplace)
            }
            // Emergency group management is now available from the Watch Admin screen to keep a single admin entry point.
        }
        .navigationTitle("Notifications")
    }
}
