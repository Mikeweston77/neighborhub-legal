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
    @StateObject private var weatherService = WeatherKitService()
    
    @State private var showPaymentSheet: Bool = false
    @State private var showPaymentMethodSheet: Bool = false
    @State private var paymentReference: String?
    @State private var isInitiatingPayment: Bool = false
    @State private var paymentError: String?
    @State private var selectedPlanForPayment: SubscriptionType?
    @State private var selectedCheckoutMode: StitchCheckoutMode = .recurring

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
                weatherService.refreshWeather()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaymentSheet) {
                if let reference = paymentReference {
                    StitchPaymentResultSheet(reference: reference) { success in
                        if success {
                            // Refresh subscription status
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaymentMethodSheet) {
                if let plan = selectedPlanForPayment {
                    StitchPaymentMethodSelectorSheet(
                        title: "Subscription Payment",
                        amount: plan.monthlyRate,
                        allowsRecurringSelection: true,
                        checkoutMode: $selectedCheckoutMode
                    ) { method in
                        initiatePayment(for: plan, preferredPaymentMethod: method)
                    }
                }
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
            .onReceive(NotificationCenter.default.publisher(for: .stitchPaymentCallbackReceived)) { notification in
                guard let payload = notification.object as? StitchPaymentCallbackPayload else {
                    return
                }
                guard let reference = paymentReference, payload.reference == reference else {
                    return
                }
                showPaymentSheet = true
            }
        }
    }
    
    // MARK: - Payment Handler
    
    private func initiatePayment(for plan: SubscriptionType, preferredPaymentMethod: StitchPreferredPaymentMethod) {
        isInitiatingPayment = true
        
        Task {
            do {
                let amount = plan.monthlyRate
                let request = StitchPaymentRequest(
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
                
                let response = try await StitchPaymentManager.shared.initiatePayment(request: request)
                
                await MainActor.run {
                    paymentReference = response.reference
                    isInitiatingPayment = false
                    openCheckoutWithinApp(response.redirectUrl)
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
    private func openCheckoutWithinApp(_ checkoutURL: URL) {
        guard checkoutURL.scheme?.lowercased() == "https" else {
            paymentReference = nil
            paymentError = "Invalid checkout URL returned by Stitch."
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
            paymentError = "Unable to open Stitch checkout on this device."
            return
        }

        UIApplication.shared.open(checkoutURL, options: [:]) { didOpen in
            if !didOpen {
                paymentReference = nil
                paymentError = "Unable to open Stitch checkout on this device."
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
            onPayTapped: {
                selectedPlanForPayment = plan
                selectedCheckoutMode = .recurring
                showPaymentMethodSheet = true
            },
            isLoading: isInitiatingPayment
        )
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
            Text("For membership setup, please contact your committee admin.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://neighborhub.app/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://neighborhub.app/privacy")!)
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
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(isLoading)
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}


