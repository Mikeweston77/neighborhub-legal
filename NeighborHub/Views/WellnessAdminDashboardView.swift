import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

// MARK: - Main Dashboard
struct WellnessAdminDashboardView: View {
    @State private var selectedTab: WellnessAdminTab = .needHelp
    @State private var escalations: [WellnessEscalation] = []
    @State private var missedCheckins: [WellnessMissedUser] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    enum WellnessAdminTab: String, CaseIterable {
        case needHelp = "Need Help"
        case missed = "Missed Check-ins"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(WellnessAdminTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.title).foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if selectedTab == .needHelp {
                needHelpList
            } else {
                missedList
            }
        }
        .onAppear { loadData() }
        .onChange(of: selectedTab) { _ in loadData() }
    }

    // MARK: - Need Help Tab
    private var needHelpList: some View {
        Group {
            if escalations.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundColor(.green)
                    Text("No active help requests").font(.headline)
                    Text("All residents are accounted for.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    Section(header: Text("\(escalations.count) Active Request(s)").foregroundColor(.red)) {
                        ForEach(escalations) { esc in
                            WellnessEscalationRow(escalation: esc) { resolve(esc) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Missed Check-ins Tab
    private var missedList: some View {
        Group {
            if missedCheckins.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundColor(.green)
                    Text("No missed check-ins").font(.headline)
                    Text("All opted-in residents have responded.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    Section(header: Text("\(missedCheckins.count) Missing Response(s)")) {
                        ForEach(missedCheckins) { user in
                            WellnessMissedRow(user: user)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Data Loading
    private func loadData() {
        if selectedTab == .needHelp { loadEscalations() } else { loadMissedCheckins() }
    }

    private func loadEscalations() {
        isLoading = true; errorMessage = nil
        Firestore.firestore().collection("wellnessEscalations")
            .whereField("resolved", isEqualTo: false)
            .order(by: "timestamp", descending: true)
            .getDocuments { snap, error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.escalations = (snap?.documents ?? []).compactMap { WellnessEscalation(doc: $0) }
                }
            }
    }

    private func loadMissedCheckins() {
        isLoading = true; errorMessage = nil
        let db = Firestore.firestore()
        // Fetch all opted-in users
        db.collection("users").whereField("wellnessOptIn", isEqualTo: true).getDocuments { snap, error in
            guard let docs = snap?.documents, error == nil else {
                DispatchQueue.main.async { self.isLoading = false; self.errorMessage = error?.localizedDescription }
                return
            }
            let users = docs.compactMap { WellnessMissedUser(doc: $0) }
            let todayKey = self.todayKey()
            let yesterdayKey = self.dateKey(daysAgo: 1)
            let group = DispatchGroup()
            var missed: [WellnessMissedUser] = []
            for user in users {
                group.enter()
                db.collection("wellnessCheckins").document(user.uid).getDocument { checkSnap, _ in
                    let data = checkSnap?.data() ?? [:]
                    if data[todayKey] == nil && data[yesterdayKey] == nil {
                        missed.append(user)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.missedCheckins = missed
                self.isLoading = false
            }
        }
    }

    // MARK: - Resolve Escalation
    private func resolve(_ esc: WellnessEscalation) {
        Firestore.firestore().collection("wellnessEscalations").document(esc.uid)
            .setData(["resolved": true, "resolvedAt": Timestamp(date: Date())], merge: true) { _ in
                DispatchQueue.main.async {
                    self.escalations.removeAll { $0.uid == esc.uid }
                }
            }
    }

    // MARK: - Helpers
    private func todayKey() -> String { dateKey(daysAgo: 0) }
    private func dateKey(daysAgo: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return f.string(from: d)
    }
}

// MARK: - Models
struct WellnessEscalation: Identifiable {
    let id: String
    let uid: String
    let type: String
    let timestamp: Date
    let displayName: String
    let address: String
    let emergencyContact: String
    let emergencyPhone: String

    init?(doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let uid = d["uid"] as? String else { return nil }
        self.id = doc.documentID; self.uid = uid
        self.type = d["type"] as? String ?? "NeedHelp"
        self.timestamp = (d["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        self.displayName = d["displayName"] as? String ?? "Resident"
        self.address = d["address"] as? String ?? ""
        self.emergencyContact = d["emergencyContactName"] as? String ?? ""
        self.emergencyPhone = d["emergencyContactPhone"] as? String ?? ""
    }
}

struct WellnessMissedUser: Identifiable {
    let id: String
    let uid: String
    let displayName: String
    let address: String
    let emergencyContact: String
    let emergencyPhone: String

    init?(doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let uid = d["uid"] as? String else { return nil }
        self.id = doc.documentID; self.uid = uid
        self.displayName = d["displayName"] as? String ?? d["name"] as? String ?? "Resident"
        self.address = d["address"] as? String ?? ""
        self.emergencyContact = d["emergencyContactName"] as? String ?? ""
        self.emergencyPhone = d["emergencyContactPhone"] as? String ?? ""
    }
}

// MARK: - Row Views
struct WellnessEscalationRow: View {
    let escalation: WellnessEscalation
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.fill").foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(escalation.displayName).font(.headline)
                    if !escalation.address.isEmpty {
                        Text(escalation.address).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Need Help").font(.caption.bold()).foregroundColor(.red)
                    Text(escalation.timestamp, style: .relative)
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            if !escalation.emergencyContact.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill").font(.caption).foregroundColor(.green)
                    Text("\(escalation.emergencyContact)").font(.caption)
                    if !escalation.emergencyPhone.isEmpty {
                        Text("· \(escalation.emergencyPhone)").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Button(action: onResolve) {
                Label("Mark Resolved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold()).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.blue).cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WellnessMissedRow: View {
    let user: WellnessMissedUser

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "person.fill").foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName).font(.headline)
                    if !user.address.isEmpty {
                        Text(user.address).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text("No check-in").font(.caption).foregroundColor(.orange)
            }
            if !user.emergencyContact.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill").font(.caption).foregroundColor(.green)
                    Text(user.emergencyContact).font(.caption)
                    if !user.emergencyPhone.isEmpty {
                        Text("· \(user.emergencyPhone)").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
