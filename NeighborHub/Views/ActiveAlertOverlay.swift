import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ActiveAlertOverlay: View {
    @State private var alerts: [FirebaseManager.ActiveAlert] = []
    @State private var showingFull: Bool = false
    // Persist dismissed alert ids as a comma-separated list for multi-dismiss support
    @AppStorage("dismissedActiveAlertIDs") private var dismissedActiveAlertIDsRaw: String = ""
    
    // Helper computed property to get dismissed IDs
    private var dismissedActiveAlertIDs: Set<String> {
        Set(dismissedActiveAlertIDsRaw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty })
    }
    
    // Helper function to add a dismissed ID
    private func dismissAlert(_ id: String) {
        var s = dismissedActiveAlertIDs
        s.insert(id)
        dismissedActiveAlertIDsRaw = s.joined(separator: ",")
    }
    
    // Helper function to remove a dismissed ID
    private func undismissAlert(_ id: String) {
        var s = dismissedActiveAlertIDs
        s.remove(id)
        dismissedActiveAlertIDsRaw = s.joined(separator: ",")
    }
    
    @State private var isAdmin: Bool = false // will be resolved via FirebaseManager
    @State private var showAdminConfirm: Bool = false
    @State private var showingMinimized: Bool = false
    @State private var selectedAlert: FirebaseManager.ActiveAlert? = nil

    private let manager = FirebaseManager.shared

    var body: some View {
        Group {
            if alerts.isEmpty == false {
                // If user minimized, show a small badge/button listing count
                if showingMinimized {
                    HStack {
                        Spacer()
                        Button(action: { showingMinimized = false }) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.white)
                                Text("Active Alerts \(alerts.count)")
                                    .foregroundColor(.white)
                                    .font(.subheadline)
                            }
                            .padding(8)
                            .background(Color.red)
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                } else if let top = alerts.first(where: { !dismissedActiveAlertIDs.contains($0.id) }) {
                    ZStack(alignment: .topTrailing) {
                        // Main tappable banner
                            Button(action: {
                                let g = UIImpactFeedbackGenerator(style: .heavy); g.impactOccurred()
                                // set the selected alert so the sheet has context, then present
                                selectedAlert = top
                                showingFull = true
                            }) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(top.title)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    if let message = top.message {
                                        Text(message)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                    }
                                    if let contact = top.contactName ?? top.contactPhone {
                                        Text(contact)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                }
                                Spacer()
                                if let img = top.imageURL, let url = URL(string: img) {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 64, height: 64)
                                                .clipped()
                                                .cornerRadius(8)
                                        } else if phase.error != nil {
                                            Color.gray.frame(width: 64, height: 64).cornerRadius(8)
                                        } else {
                                            ProgressView().frame(width: 64, height: 64)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                            .shadow(radius: 6)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.spring(), value: alerts.count)
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Top-right controls: dismiss for me & minimize
                        VStack(spacing: 6) {
                            Button(action: {
                                dismissAlert(top.id)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(8)
                            }
                            .accessibilityLabel("Dismiss alert for me")

                            Button(action: { showingMinimized = true }) {
                                Image(systemName: "minus.circle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(8)
                            }
                            .accessibilityLabel("Minimize active alerts")
                        }
                        .padding(6)
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingFull) {
            if let top = selectedAlert {
                VStack(spacing: 12) {
                    HStack { Spacer(); Button("Close") { showingFull = false; selectedAlert = nil } }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(top.title).font(.title).bold()
                            if let message = top.message { Text(message) }
                            if let loc = top.location { Text("Location: \(loc)").font(.caption) }
                            if let cn = top.contactName { Text("Contact: \(cn)") }
                            if let cp = top.contactPhone { Text("Phone: \(cp)") }
                            if let img = top.imageURL, let url = URL(string: img) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFit()
                                    } else if phase.error != nil {
                                        Color.gray.frame(height: 200)
                                    } else { ProgressView().frame(height: 200) }
                                }
                            }
                        }
                        .padding()
                    }
                    if isAdmin {
                        HStack {
                            Button(role: .destructive) {
                                // ask for confirmation
                                showAdminConfirm = true
                            } label: { Text("Dismiss for All") }
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)

                            Button { dismissAlert(top.id) } label: { Text("Dismiss for Me") }
                                .padding().background(Color.gray.opacity(0.2)).cornerRadius(8)
                        }
                        .padding()
                    } else {
                        Button {
                            if let id = top.id as String? {
                                dismissAlert(id)
                            }
                        } label: { Text("Dismiss") }
                            .padding().background(Color.white).cornerRadius(8)
                    }
                }
            } else {
                EmptyView()
            }
        }
        .alert("Dismiss for All?", isPresented: $showAdminConfirm, actions: {
            Button("Cancel", role: .cancel) { showAdminConfirm = false }
            Button("Confirm", role: .destructive) {
                if let top = alerts.first {
                    manager.deleteActiveAlert(id: top.id) { err in
                        if err == nil {
                            // remove from local dismissed set if present
                            undismissAlert(top.id)
                        }
                    }
                }
            }
        }, message: { Text("This will remove the alert for all users.") })
        .onAppear {
            manager.watchActiveAlerts { items in
                DispatchQueue.main.async { self.alerts = items }
            }
            // Resolve admin state from FirebaseManager
            manager.isCurrentUserAdmin { val in
                DispatchQueue.main.async { self.isAdmin = val }
            }
        }
        .onDisappear { manager.stopWatchingActiveAlerts() }
    }
}

// Preview
struct ActiveAlertOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ActiveAlertOverlay()
    }
}
