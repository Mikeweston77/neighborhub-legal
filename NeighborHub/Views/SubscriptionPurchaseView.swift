import SwiftUI
import SafariServices
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct StitchPaymentMethodSelectorSheet: View {
    let title: String
    let amount: Double
    let allowsRecurringSelection: Bool
    @Binding var checkoutMode: StitchCheckoutMode
    let onSelect: (StitchPreferredPaymentMethod) -> Void

    @Environment(\.dismiss) private var dismiss
    
    private var availablePaymentMethods: [StitchPreferredPaymentMethod] {
        StitchPreferredPaymentMethod.allCases.filter { method in
            checkoutMode == .recurring ? method.isAvailableForRecurring : true
        }
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: "Amount: R%.2f", amount))
                    .font(.headline)

                if allowsRecurringSelection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Billing")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("Billing", selection: $checkoutMode) {
                            ForEach(StitchCheckoutMode.allCases, id: \.self) { mode in
                                Text(mode.displayName)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Text("Select payment method")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if checkoutMode == .recurring {
                    Text("Recurring payments require a card")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, -8)
                }

                ForEach(availablePaymentMethods, id: \.self) { method in
                    Button {
                        onSelect(method)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: method.iconName)
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(method.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text(method.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SubscriptionPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var householdViewModel = UserHouseholdViewModel()
    @StateObject private var weatherService = WeatherKitService()
    
    @State private var paymentReference: String?
    @State private var isInitiatingPayment: Bool = false
    @State private var paymentError: String?
    @State private var selectedCheckoutMode: StitchCheckoutMode = .recurring
    @State private var showCommitteeContacts = false
    @State private var selectedLegalPage: LegalPage?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Edge-to-edge gradient hero
                    heroSection

                    VStack(spacing: 24) {
                        plansSection
                        footerSection
                    }
                    .padding()
                    .padding(.top, 8)
                    .background(Color(.systemGroupedBackground))
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await householdViewModel.loadMySubscription()
                }
                weatherService.refreshWeather()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showCommitteeContacts) {
                CommitteeContactsSheet()
            }
            .sheet(item: $selectedLegalPage) { page in
                WebsiteWebPortalView(urlString: page.url.absoluteString, title: page.title)
            }
            .alert("Payment Error", isPresented: .constant(paymentError != nil), actions: {
                Button("OK") {
                    paymentError = nil
                    isInitiatingPayment = false
                }
            }, message: {
                if let error = paymentError {
                    Text(error)
                }
            })
            .onReceive(NotificationCenter.default.publisher(for: .paystackPaymentCallbackReceived)) { notification in
                guard let payload = notification.object as? PaystackPaymentCallbackPayload else {
                    return
                }
                guard let reference = paymentReference, payload.reference == reference else {
                    return
                }
                if payload.status == "success" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Payment Handler
    
    private func initiatePayment(for plan: SubscriptionType, preferredPaymentMethod: StitchPreferredPaymentMethod = .card) {
        isInitiatingPayment = true
        
        Task {
            do {
                let amount = plan.monthlyRate
                let request = PaystackPaymentRequest(
                    paymentType: .subscription,
                    amount: amount,
                    description: "\(plan == .household ? "Household" : "Single") Subscription - R\(Int(amount))/month",
                    planType: plan == .household ? .household : .single,
                    billingDay: Calendar.current.component(.day, from: Date()),
                    autoPayEnabled: selectedCheckoutMode.autoPayEnabled,
                    checkoutMode: selectedCheckoutMode,
                    preferredPaymentMethod: preferredPaymentMethod,
                    billingStartDate: Date()
                )
                
                let response = try await PaystackPaymentManager.shared.initiatePayment(request: request)
                
                await MainActor.run {
                    paymentReference = response.reference
                    isInitiatingPayment = false
                    openCheckoutWithinApp(accessCode: response.accessCode, fallbackURL: response.authorizationUrl ?? response.redirectUrl)
                }
            } catch let error as StitchPaymentError {
                await MainActor.run {
                    paymentError = error.errorDescription ?? "Payment failed"
                    isInitiatingPayment = false
                }
            } catch {
                await MainActor.run {
                    paymentError = error.localizedDescription
                    isInitiatingPayment = false
                }
            }
        }
    }

    @MainActor
    private func openCheckoutWithinApp(accessCode: String?, fallbackURL: URL?) {
        if let accessCode = accessCode, !accessCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let didPresent = PaystackCheckoutPresentation.presentNativeCheckout(
                accessCode: accessCode,
                onSuccess: { reference in
                    paymentReference = reference
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                },
                onCancelled: {
                    paymentError = "Payment was cancelled."
                    isInitiatingPayment = false
                },
                onError: { message in
                    paymentError = message
                    isInitiatingPayment = false
                }
            )

            if didPresent {
                return
            }
        }

        guard let checkoutURL = fallbackURL else {
            paymentReference = nil
            paymentError = "Paystack checkout could not be started."
            return
        }

        guard checkoutURL.scheme?.lowercased() == "https" else {
            paymentReference = nil
            paymentError = "Invalid checkout URL returned by Paystack."
            return
        }

        #if canImport(UIKit)
        let safariVC = SFSafariViewController(url: checkoutURL)
        safariVC.dismissButtonStyle = .close
        safariVC.preferredControlTintColor = .systemBlue

        if let presenter = topMostViewController() {
            presenter.present(safariVC, animated: true)
            return
        }
        #endif

        guard UIApplication.shared.canOpenURL(checkoutURL) else {
            paymentReference = nil
            paymentError = "Unable to open Paystack checkout on this device."
            return
        }

        UIApplication.shared.open(checkoutURL, options: [:]) { didOpen in
            if !didOpen {
                paymentReference = nil
                paymentError = "Unable to open Paystack checkout on this device."
            }
        }
    }

    #if canImport(UIKit)
    private func topMostViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController
        else {
            return nil
        }

        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
    #endif
    
    private func handlePaymentCompletion(success: Bool) {
        if success {
            // Give a moment for subscription status to update
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }
    
    // MARK: - Sub-views
    
    private func planCard(for plan: SubscriptionType) -> some View {
        PlanCard(
            plan: plan,
            isEnabled: isPlanRelevant(plan),
            onPayTapped: {
                selectedCheckoutMode = .recurring
                initiatePayment(for: plan)
            },
            isLoading: isInitiatingPayment
        )
    }

    private func isPlanRelevant(_ plan: SubscriptionType) -> Bool {
        guard let currentSubscription = householdViewModel.mySubscription else {
            return true
        }

        return currentSubscription.isHousehold == (plan == .household)
    }

    // MARK: - Sections

    private var heroSection: some View {
        ZStack {
            HomeView.LiveWeatherUnderlayView(weather: weatherService.currentWeather)
                .ignoresSafeArea(edges: .top)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.20),
                    Color.black.opacity(0.38),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {
                Image(systemName: "house.circle.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Text("NeighborHub Membership")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Full access to your neighborhood — safety, community, marketplace & more.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 20) {
                    heroStat(icon: "shield.checkered", label: "Verified\nNeighbors")
                    heroStat(icon: "map.fill", label: "Local\nAlerts")
                    heroStat(icon: "cart.fill", label: "Marketplace\nAccess")
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 32)
        }
    }

    private func heroStat(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 72)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available plans")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach([SubscriptionType.single, SubscriptionType.household], id: \.self) { plan in
                planCard(for: plan)
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 10) {
            Button {
                showCommitteeContacts = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                    Text("For membership setup, please contact your committee admins")
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.blue)
                .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                Button {
                    selectedLegalPage = .terms
                } label: {
                    Text("Terms of Use")
                }

                Button {
                    selectedLegalPage = .privacy
                } label: {
                    Text("Privacy Policy")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

}

// MARK: - PlanCard

private struct PlanCard: View {
    let plan: SubscriptionType
    let isEnabled: Bool
    var onPayTapped: (() -> Void)?
    var isLoading: Bool = false

    private var isPopular: Bool { plan == .household }

    private var features: [String] {
        switch plan {
        case .single:
            return [
                "Neighborhood watch & alerts",
                "Community social feed",
                "Local marketplace",
                "Event calendar & RSVPs",
                "Lost & found board"
            ]
        case .household:
            return [
                "Everything in Single",
                "Up to 5 household members",
                "Shared safety dashboard",
                "Household resource sharing",
                "Priority support"
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 52, height: 52)
                    Image(systemName: plan == .household ? "person.3.fill" : "person.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan == .household ? "Household" : "Single User")
                            .font(.headline)
                        if isPopular {
                            Text("POPULAR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.07, green: 0.38, blue: 0.95))
                                .clipShape(Capsule())
                        }
                    }
                    Text(plan == .household ? "Up to 5 household members" : "One resident")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "R%.0f", plan.monthlyRate))
                        .font(.title3.bold())
                        .foregroundColor(.primary)
                    Text("/ month")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)

            // Divider + feature list
            Divider()
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text(feature)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(16)
            
            // Payment Button
            Divider()
                .padding(.horizontal, 16)
            
            Button(action: {
                guard isEnabled else { return }
                onPayTapped?()
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Pay R\(Int(plan.monthlyRate))")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(isEnabled ? Color.blue : Color.gray.opacity(0.45))
                .foregroundColor(isEnabled ? .white : .secondary)
                .cornerRadius(8)
            }
            .disabled(isLoading || !isEnabled)
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .opacity(isEnabled ? 1 : 0.65)
    }
}

// MARK: - Committee Contacts Sheet

private struct CommitteeContactsSheet: View {
    @StateObject private var viewModel = CommitteeContactsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading contacts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.contacts.isEmpty {
                    ContentUnavailableView(
                        "No committee contacts found",
                        systemImage: "person.3.fill",
                        description: Text("Committee and admin contacts will appear here when they are available.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(viewModel.contacts) { contact in
                                CommitteeContactCard(contact: contact)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Committee Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadContacts()
            }
        }
    }
}

private struct CommitteeContactCard: View {
    let contact: CommitteeContact
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(contact.roleColor.opacity(0.16))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: contact.roleIcon)
                            .foregroundColor(contact.roleColor)
                            .font(.headline)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(contact.roleLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(contact.roleColor.opacity(0.14))
                            .foregroundColor(contact.roleColor)
                            .clipShape(Capsule())

                        if contact.isPrimaryContact {
                            Text("Primary")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.14))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()
            }

            if !contact.phoneNumber.isEmpty {
                Text(contact.phoneNumber)
                    .font(.body.monospacedDigit())
                    .foregroundColor(.primary)
            }

            HStack(spacing: 12) {
                Button {
                    openCall(contact.phoneNumber)
                } label: {
                    Label("Call", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CommitteeActionButtonStyle(color: .blue))

                Button {
                    openWhatsApp(contact.phoneNumber)
                } label: {
                    Label("WhatsApp", systemImage: "message.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CommitteeActionButtonStyle(color: Color.green))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func openCall(_ phoneNumber: String) {
        let cleaned = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(cleaned)") else { return }
        openURL(url)
    }

    private func openWhatsApp(_ phoneNumber: String) {
        var waNumber = phoneNumber.filter { $0.isNumber }
        if waNumber.hasPrefix("0") && waNumber.count == 10 {
            waNumber = "27" + waNumber.dropFirst()
        }
        guard !waNumber.isEmpty, let url = URL(string: "https://wa.me/\(waNumber)") else { return }
        openURL(url)
    }
}

private struct CommitteeActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundColor(.white)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum LegalPage: Identifiable {
    case terms
    case privacy

    var id: String {
        switch self {
        case .terms: return "terms"
        case .privacy: return "privacy"
        }
    }

    var title: String {
        switch self {
        case .terms: return "Terms of Use"
        case .privacy: return "Privacy Policy"
        }
    }

    var url: URL {
        switch self {
        case .terms:
            return URL(string: "https://mikeweston77.github.io/neighborhub-legal/terms.html")!
        case .privacy:
            return URL(string: "https://mikeweston77.github.io/neighborhub-legal/privacy.html")!
        }
    }
}

private struct CommitteeContact: Identifiable {
    let id: String
    let name: String
    let phoneNumber: String
    let roleLabel: String
    let roleIcon: String
    let roleColor: Color
    let isPrimaryContact: Bool
}

@MainActor
private final class CommitteeContactsViewModel: ObservableObject {
    @Published var contacts: [CommitteeContact] = []
    @Published var isLoading = false

    #if canImport(FirebaseFirestore)
    private let db = Firestore.firestore()
    #endif

    func loadContacts() async {
        guard contacts.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        #if canImport(FirebaseFirestore)
        do {
            let snapshot = try await db.collection("users").getDocuments()
            let loaded = snapshot.documents.compactMap { document -> CommitteeContact? in
                let data = document.data()
                let isAdmin = data["isAdmin"] as? Bool ?? false
                let isCommittee = data["isCommittee"] as? Bool ?? false
                guard isAdmin || isCommittee else { return nil }

                let firstName = (data["firstName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let lastName = (data["lastName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let combinedName = (data["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackName = document.documentID
                let primaryName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
                let name = !primaryName.isEmpty ? primaryName : (!combinedName.isEmpty ? combinedName : fallbackName)
                let phone = (data["phone"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let roleLabel = isAdmin && isCommittee ? "Admin / Committee" : isAdmin ? "Admin" : "Committee"
                let roleIcon = isAdmin && isCommittee ? "person.2.fill" : isAdmin ? "shield.lefthalf.filled" : "person.3.fill"
                let roleColor: Color = isAdmin && isCommittee ? .purple : isAdmin ? .red : .blue

                return CommitteeContact(
                    id: document.documentID,
                    name: name,
                    phoneNumber: phone,
                    roleLabel: roleLabel,
                    roleIcon: roleIcon,
                    roleColor: roleColor,
                    isPrimaryContact: isAdmin && isCommittee
                )
            }

            contacts = loaded.sorted { lhs, rhs in
                if lhs.roleLabel != rhs.roleLabel { return lhs.roleLabel < rhs.roleLabel }
                return lhs.name < rhs.name
            }
        } catch {
            contacts = []
        }
        #endif
    }
}


