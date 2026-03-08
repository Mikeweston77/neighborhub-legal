import SwiftUI
import UserNotifications
import FirebaseFirestore
import FirebaseAuth

struct WellnessSettingsView: View {
    @AppStorage("userUID") private var userUID: String = ""
    @State private var wellnessOptIn: Bool = true
    @State private var visibilityOption: String = "community"
    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var saveSuccess: Bool = false

    private let visibilityOptions: [(label: String, value: String, description: String)] = [
        ("Only Me", "private", "No one will be notified if you miss a check-in."),
        ("Committee Only", "committee", "Your HOA committee members will be notified."),
        ("Community", "community", "Your emergency contact and committee will be notified.")
    ]

    var body: some View {
        Form {
            Section(header: Text("Daily Check-ins")) {
                Toggle(isOn: $wellnessOptIn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Wellness Check-ins")
                            .font(.body).fontWeight(.semibold)
                        Text("Receive a daily prompt at 9 AM to confirm your wellbeing.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if wellnessOptIn {
                Section(header: Text("Missed Check-in Visibility"),
                        footer: Text("Who can see if you miss a check-in or request help.")) {
                    ForEach(visibilityOptions, id: \.value) { option in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label).font(.body)
                                Text(option.description).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if visibilityOption == option.value {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { visibilityOption = option.value }
                    }
                }
            }

            if let error = errorMessage {
                Section { Text(error).foregroundColor(.red).font(.caption) }
            }

            if saveSuccess {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Settings saved").foregroundColor(.green).font(.subheadline)
                    }
                }
            }

            Section {
                Button(action: saveSettings) {
                    if isSaving {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Text("Save Settings").frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Wellness Settings")
        .onAppear(perform: loadSettings)
    }

    // MARK: - Helpers
    private func resolvedUID() -> String? {
        if !userUID.isEmpty { return userUID }
        return Auth.auth().currentUser?.uid
    }

    // MARK: - Load
    private func loadSettings() {
        guard let uid = resolvedUID() else { return }
        Firestore.firestore().collection("users").document(uid).getDocument { snap, error in
            DispatchQueue.main.async {
                if let error = error { self.errorMessage = error.localizedDescription }
                if let data = snap?.data() {
                    self.wellnessOptIn = data["wellnessOptIn"] as? Bool ?? true
                    self.visibilityOption = data["wellnessVisibility"] as? String ?? "community"
                }
            }
        }
    }

    // MARK: - Save
    private func saveSettings() {
        guard let uid = resolvedUID() else {
            errorMessage = "Unable to identify user. Please log out and back in."
            return
        }
        isSaving = true
        Firestore.firestore().collection("users").document(uid)
            .setData(["wellnessOptIn": wellnessOptIn,
                      "wellnessVisibility": visibilityOption], merge: true) { error in
                DispatchQueue.main.async {
                    self.isSaving = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.errorMessage = nil
                        self.saveSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.saveSuccess = false }
                        if !self.wellnessOptIn {
                            UNUserNotificationCenter.current()
                                .removePendingNotificationRequests(withIdentifiers: ["wellnessCheckinDaily"])
                        }
                    }
                }
            }
    }
}
