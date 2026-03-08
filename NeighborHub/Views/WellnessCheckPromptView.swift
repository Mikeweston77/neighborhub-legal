import SwiftUI
import UserNotifications
import FirebaseFirestore

struct WellnessCheckPromptView: View {
    @AppStorage("userUID") private var userUID: String = ""
    @State private var wellnessOptIn: Bool = false
    @State private var checkedInToday: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var lastResponse: String? = nil
    @State private var lastResponseDate: Date? = nil
    @State private var showNeedHelpConfirm: Bool = false

    var body: some View {
        Group {
            if wellnessOptIn && !checkedInToday {
                checkInCard
            } else if wellnessOptIn && checkedInToday {
                checkedInCard
            }
        }
        .onAppear { loadOptInAndStatus() }
    }

    // MARK: - Check-in Prompt Card
    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "heart.circle.fill")
                    .foregroundColor(.pink)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Wellness Check-in").font(.headline)
                    Text("How are you feeling today?")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                Button(action: { submitResponse("OK") }) {
                    Label("I'm OK", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold()).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.green).cornerRadius(10)
                }
                .disabled(isLoading)
                Button(action: { showNeedHelpConfirm = true }) {
                    Label("Need Help", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold()).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.red).cornerRadius(10)
                }
                .disabled(isLoading)
            }
            if let error = errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .confirmationDialog("Request Help?", isPresented: $showNeedHelpConfirm, titleVisibility: .visible) {
            Button("Yes, I Need Help", role: .destructive) { submitResponse("Need Help") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your emergency contact and committee will be notified.")
        }
    }

    // MARK: - Already Checked-in Card
    private var checkedInCard: some View {
        HStack(spacing: 12) {
            Image(systemName: lastResponse == "Need Help" ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundColor(lastResponse == "Need Help" ? .red : .green)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wellness check-in complete").font(.subheadline.bold())
                if let r = lastResponse, let d = lastResponseDate {
                    Text("\(r) · \(d.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle").foregroundColor(.green)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Data Loading
    private func loadOptInAndStatus() {
        guard !userUID.isEmpty else { return }
        Firestore.firestore().collection("users").document(userUID).getDocument { snap, _ in
            let optedIn = snap?.data()?["wellnessOptIn"] as? Bool ?? true
            DispatchQueue.main.async {
                self.wellnessOptIn = optedIn
                if optedIn { self.scheduleNotificationIfNeeded(); self.loadTodayCheckin() }
            }
        }
    }

    private func loadTodayCheckin() {
        guard !userUID.isEmpty else { return }
        Firestore.firestore().collection("wellnessCheckins").document(userUID).getDocument { snap, _ in
            if let entry = snap?.data()?[todayKey()] as? [String: Any] {
                DispatchQueue.main.async {
                    self.lastResponse = entry["response"] as? String
                    self.lastResponseDate = (entry["timestamp"] as? Timestamp)?.dateValue()
                    self.checkedInToday = true
                }
            }
        }
    }

    // MARK: - Submit Response
    private func submitResponse(_ response: String) {
        guard !userUID.isEmpty else { return }
        isLoading = true
        let now = Date()
        Firestore.firestore().collection("wellnessCheckins").document(userUID)
            .setData([todayKey(): ["response": response, "timestamp": Timestamp(date: now), "uid": userUID]], merge: true) { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.lastResponse = response; self.lastResponseDate = now
                    self.checkedInToday = true; self.errorMessage = nil
                    if response == "Need Help" { self.flagForEscalation() }
                }
            }
    }

    // MARK: - Escalation
    private func flagForEscalation() {
        guard !userUID.isEmpty else { return }
        Firestore.firestore().collection("wellnessEscalations").document(userUID).setData([
            "uid": userUID, "type": "NeedHelp",
            "timestamp": Timestamp(date: Date()), "resolved": false
        ], merge: true)
    }

    // MARK: - Daily Notification
    private func scheduleNotificationIfNeeded() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            guard !requests.contains(where: { $0.identifier == "wellnessCheckinDaily" }) else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = "Daily Wellness Check-in"
                content.body = "How are you feeling today? Open the app to respond."
                content.sound = .default
                var comps = DateComponents(); comps.hour = 9; comps.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "wellnessCheckinDaily", content: content, trigger: trigger)
                )
            }
        }
    }

    // MARK: - Helpers
    private func todayKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
}
