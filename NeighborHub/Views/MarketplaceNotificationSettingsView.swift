import SwiftUI

struct MarketplaceNotificationSettingsView: View {
    @AppStorage("notifyMarketplace") private var notifyMarketplace: Bool = true
    var body: some View {
        Form {
            Section(header: Text("Marketplace Notifications")) {
                Toggle("Item Added Notifications", isOn: $notifyMarketplace)
            }
        }
        .navigationTitle("Marketplace Notifications")
    }
}
