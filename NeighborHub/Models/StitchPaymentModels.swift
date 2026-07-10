import Foundation

/// Notification names for Stitch payment events.
extension Notification.Name {
    static let stitchPaymentCallbackReceived = Notification.Name("stitchPaymentCallbackReceived")
}

/// Supported Stitch payment types.
enum StitchPaymentType: RawRepresentable, Codable {
    case subscription
    case listing

    var rawValue: String {
        switch self {
        case .subscription: return "subscription"
        case .listing: return "listing"
        }
    }

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "subscription": self = .subscription
        case "listing": self = .listing
        default: return nil
        }
    }

    /// Returns the backend-compatible string value.
    var backendValue: String {
        rawValue
    }
}

/// Supported subscription plan types.
enum StitchSubscriptionPlanType: RawRepresentable, Codable {
    case single
    case household

    var rawValue: String {
        switch self {
        case .single: return "single"
        case .household: return "household"
        }
    }

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "single": self = .single
        case "household": self = .household
        default: return nil
        }
    }

    /// Returns the backend-compatible string value.
    var backendValue: String {
        rawValue
    }

    /// Display-friendly name for the plan.
    var displayName: String {
        switch self {
        case .single: return "Single"
        case .household: return "Household"
        }
    }
}

enum StitchCheckoutMode: String, CaseIterable, Codable {
    case oneTime = "ONE_TIME"
    case recurring = "RECURRING"

    var backendValue: String {
        rawValue
    }

    var billingIntervalValue: String {
        switch self {
        case .oneTime: return "once"
        case .recurring: return "monthly"
        }
    }

    var autoPayEnabled: Bool {
        self == .recurring
    }

    var displayName: String {
        switch self {
        case .oneTime: return "Pay Once"
        case .recurring: return "Recurring"
        }
    }
}

enum StitchPreferredPaymentMethod: String, CaseIterable, Codable {
    case card = "card"
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    case capitecPay = "capitec_pay"
    case bnpl = "bnpl"

    var backendValue: String {
        rawValue
    }

    var title: String {
        switch self {
        case .card: return "Card Payment"
        case .applePay: return "Apple Pay"
        case .googlePay: return "Google Pay"
        case .capitecPay: return "Capitec Pay"
        case .bnpl: return "Buy Now, Pay Later"
        }
    }

    var subtitle: String {
        switch self {
        case .card: return "Pay securely via Stitch Express"
        case .applePay: return "Fast checkout with Apple Pay"
        case .googlePay: return "Quick payment with Google Pay"
        case .capitecPay: return "Pay via the Capitec app"
        case .bnpl: return "Flexible payment with Stitch"
        }
    }

    var iconName: String {
        switch self {
        case .card: return "creditcard.fill"
        case .applePay: return "apple.logo"
        case .googlePay: return "creditcard.fill"
        case .capitecPay: return "creditcard.fill"
        case .bnpl: return "creditcard.and.123"
        }
    }

    var isAvailableForRecurring: Bool {
        switch self {
        case .card: return true
        case .applePay, .googlePay, .capitecPay, .bnpl: return false
        }
    }
}

/// Request payload for initiating a Stitch payment.
struct StitchPaymentRequest: Codable {
    let paymentType: StitchPaymentType
    let amount: Double
    let currency: String
    let description: String
    let userId: String?
    let memberUID: String?
    let planType: StitchSubscriptionPlanType?
    let billingDay: Int?
    let autoPayEnabled: Bool?
    let checkoutMode: StitchCheckoutMode?
    let preferredPaymentMethod: StitchPreferredPaymentMethod?
    let billingStartDate: Date?
    let listingId: String?
    let subscriptionDocId: String?

    enum CodingKeys: String, CodingKey {
        case paymentType = "type"
        case amount, currency, description, userId, memberUID, planType
        case billingDay, autoPayEnabled, checkoutMode, preferredPaymentMethod
        case billingStartDate, listingId, subscriptionDocId
    }

    init(
        paymentType: StitchPaymentType,
        amount: Double,
        currency: String = "ZAR",
        description: String = "",
        userId: String? = nil,
        memberUID: String? = nil,
        planType: StitchSubscriptionPlanType? = nil,
        billingDay: Int? = nil,
        autoPayEnabled: Bool? = nil,
        checkoutMode: StitchCheckoutMode? = nil,
        preferredPaymentMethod: StitchPreferredPaymentMethod? = nil,
        billingStartDate: Date? = nil,
        listingId: String? = nil,
        subscriptionDocId: String? = nil
    ) {
        self.paymentType = paymentType
        self.amount = amount
        self.currency = currency
        self.description = description
        self.userId = userId
        self.memberUID = memberUID
        self.planType = planType
        self.billingDay = billingDay
        self.autoPayEnabled = autoPayEnabled
        self.checkoutMode = checkoutMode
        self.preferredPaymentMethod = preferredPaymentMethod
        self.billingStartDate = billingStartDate
        self.listingId = listingId
        self.subscriptionDocId = subscriptionDocId
    }
}

/// Response from a successful Stitch payment link creation.
struct StitchPaymentResponse: Codable {
    let reference: String
    let redirectUrl: URL
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case reference
        case redirectUrl = "checkoutUrl"
        case expiresAt
    }

    init(
        reference: String,
        redirectUrl: URL,
        expiresAt: Date? = nil
    ) {
        self.reference = reference
        self.redirectUrl = redirectUrl
        self.expiresAt = expiresAt
    }
}

/// Callback payload received from Stitch checkout redirect.
struct StitchPaymentCallbackPayload {
    let status: String
    let reference: String
    let trusted: String
    let error: String?

    /// Parses a neighborhub://stitch/callback URL into a payload.
    static func from(url: URL) -> StitchPaymentCallbackPayload? {
        guard url.scheme?.lowercased() == "neighborhub",
              url.host?.lowercased() == "stitch",
              url.path.lowercased() == "/callback"
        else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let status = components?.queryItems?.first(where: { $0.name == "status" })?
            .value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "pending"
        let reference = components?.queryItems?.first(where: { $0.name == "reference" })?
            .value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trusted = components?.queryItems?.first(where: { $0.name == "trusted" })?
            .value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1"
        let error = components?.queryItems?.first(where: { $0.name == "error" })?
            .value

        guard !reference.isEmpty else {
            return nil
        }

        return StitchPaymentCallbackPayload(status: status, reference: reference, trusted: trusted, error: error)
    }
}

/// Errors that can occur during Stitch payment operations.
enum StitchPaymentError: LocalizedError, Equatable {
    case network(String)
    case invalidResponse(String)
    case paymentCancelled
    case callbackTimeout
    case unauthenticated
    case invalidAmount
    case firebaseFunctionsUnavailable

    var description: String {
        switch self {
        case .network(let msg):
            return "Network error: \(msg)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .paymentCancelled:
            return "Payment was cancelled by user"
        case .callbackTimeout:
            return "Callback was not received within timeout period"
        case .unauthenticated:
            return "You need to be signed in before making a payment."
        case .invalidAmount:
            return "Payment amount is invalid."
        case .firebaseFunctionsUnavailable:
            return "Payments are temporarily unavailable on this device build."
        }
    }

    var errorDescription: String? {
        description
    }

    static func == (lhs: StitchPaymentError, rhs: StitchPaymentError) -> Bool {
        lhs.description == rhs.description
    }
}
