import Foundation

// MARK: - Subscription Type Enums

enum SubscriptionType: String, Codable, Hashable {
    case single = "Single User"      // R50/month
    case household = "Household"     // R99/month (up to 5 users)
    
    var monthlyRate: Double {
        switch self {
        case .single: return 50.0
        case .household: return 99.0
        }
    }
    
    var displayRate: String {
        switch self {
        case .single: return "R50/month"
        case .household: return "R99/month (up to 5 people)"
        }
    }
}

// MARK: - Subscription Payment Models

struct MemberSubscription: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var memberUID: String
    var memberName: String
    var memberSurname: String
    var address: String?
    var email: String?
    var phone: String?
    var paymentHistory: [SubscriptionPayment]
    var currentYear: Int
    var isPaidCurrentYear: Bool
    var lastContacted: Date?
    var adminNotes: String?
    
    // NEW: Monthly subscription tracking
    var subscriptionType: SubscriptionType?
    var householdMembers: [String]?  // UIDs of household members (max 5)
    var isPaidCurrentMonth: Bool?
    var lastMonthPaid: Date?
    
    init(id: UUID = UUID(),
         memberUID: String,
         memberName: String,
         memberSurname: String,
         address: String? = nil,
         email: String? = nil,
         phone: String? = nil,
         paymentHistory: [SubscriptionPayment] = [],
         currentYear: Int = Calendar.current.component(.year, from: Date()),
         isPaidCurrentYear: Bool = false,
         lastContacted: Date? = nil,
         adminNotes: String? = nil,
         subscriptionType: SubscriptionType? = nil,
         householdMembers: [String]? = nil,
         isPaidCurrentMonth: Bool? = nil,
         lastMonthPaid: Date? = nil) {
        self.id = id
        self.memberUID = memberUID
        self.memberName = memberName
        self.memberSurname = memberSurname
        self.address = address
        self.email = email
        self.phone = phone
        self.paymentHistory = paymentHistory
        self.currentYear = currentYear
        self.isPaidCurrentYear = isPaidCurrentYear
        self.lastContacted = lastContacted
        self.adminNotes = adminNotes
        self.subscriptionType = subscriptionType
        self.householdMembers = householdMembers
        self.isPaidCurrentMonth = isPaidCurrentMonth
        self.lastMonthPaid = lastMonthPaid
    }
    
    var fullName: String {
        "\(memberName) \(memberSurname)".trimmingCharacters(in: .whitespaces)
    }
    
    var lastPaymentDate: Date? {
        paymentHistory.sorted(by: { $0.paymentDate > $1.paymentDate }).first?.paymentDate
    }
    
    var yearsUnpaid: Int {
        let currentYear = Calendar.current.component(.year, from: Date())
        if isPaidCurrentYear { return 0 }
        
        if let lastYear = paymentHistory.last?.year {
            return currentYear - lastYear
        }
        return 0
    }
    
    // NEW: Monthly subscription helpers
    var effectiveSubscriptionType: SubscriptionType {
        if let type = subscriptionType {
            return type
        }
        // Auto-detect: if household members exist, it's household
        if let members = householdMembers, members.count > 1 {
            return .household
        }
        return .single
    }
    
    var monthlyRate: Double {
        effectiveSubscriptionType.monthlyRate
    }
    
    var householdSize: Int {
        // Always include primary user + additional household members
        1 + (householdMembers?.count ?? 0)
    }
    
    var isHousehold: Bool {
        effectiveSubscriptionType == .household
    }
    
    var monthsUnpaid: Int {
        guard let lastPaid = lastMonthPaid else {
            return 0
        }
        
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.month], from: lastPaid, to: now)
        return max(0, components.month ?? 0)
    }
    
    var totalOutstanding: Double {
        Double(monthsUnpaid) * monthlyRate
    }
    
    // MARK: - Household Member Management
    
    /// Maximum number of members allowed in a household
    static let maxHouseholdMembers = 5
    
    /// Check if household can accept more members
    var canAddHouseholdMember: Bool {
        householdSize < Self.maxHouseholdMembers
    }
    
    /// Remaining slots in household
    var remainingHouseholdSlots: Int {
        Self.maxHouseholdMembers - householdSize
    }
    
    /// Add a member to the household (with validation)
    mutating func addHouseholdMember(_ userUID: String) -> Result<Void, HouseholdError> {
        // Don't add self
        if userUID == memberUID {
            return .failure(.cannotAddSelf)
        }
        
        // Check if already in household
        if householdMembers?.contains(userUID) == true {
            return .failure(.memberAlreadyInHousehold)
        }
        
        // Check limit
        if !canAddHouseholdMember {
            return .failure(.householdFull)
        }
        
        // Initialize array if needed
        if householdMembers == nil {
            householdMembers = []
        }
        
        // Add member
        householdMembers?.append(userUID)
        
        // Auto-upgrade to household type when first additional member is added
        // (primary user + 1 member = 2 people = household subscription)
        if householdMembers?.count ?? 0 >= 1 && subscriptionType != .household {
            subscriptionType = .household
        }
        
        return .success(())
    }
    
    /// Remove a member from the household
    mutating func removeHouseholdMember(_ userUID: String) {
        householdMembers?.removeAll { $0 == userUID }
        
        // Downgrade to single if no additional members remain (only primary user)
        if (householdMembers?.count ?? 0) == 0 && subscriptionType == .household {
            subscriptionType = .single
        }
    }
}

enum HouseholdError: LocalizedError {
    case householdFull
    case memberAlreadyInHousehold
    case cannotAddSelf
    
    var errorDescription: String? {
        switch self {
        case .householdFull:
            return "Household is full. Maximum 5 members allowed."
        case .memberAlreadyInHousehold:
            return "This member is already in the household."
        case .cannotAddSelf:
            return "Cannot add yourself to your own household."
        }
    }
}

struct SubscriptionPayment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var year: Int
    var month: Int?  // NEW: Track month for monthly subscriptions
    var amount: Double
    var paymentDate: Date
    var paymentMethod: PaymentMethod
    var receiptNumber: String?
    var notes: String?
    var recordedBy: String // Admin UID who recorded the payment
    var recordedByName: String
    var monthsCovered: Int?  // NEW: How many months this payment covers
    
    init(id: UUID = UUID(),
         year: Int = Calendar.current.component(.year, from: Date()),
         amount: Double,
         paymentDate: Date = Date(),
         paymentMethod: PaymentMethod = .cash,
         receiptNumber: String? = nil,
         notes: String? = nil,
         recordedBy: String,
         recordedByName: String,
         month: Int? = Calendar.current.component(.month, from: Date()),
         monthsCovered: Int? = 1) {
        self.id = id
        self.year = year
        self.month = month
        self.amount = amount
        self.paymentDate = paymentDate
        self.paymentMethod = paymentMethod
        self.receiptNumber = receiptNumber
        self.notes = notes
        self.recordedBy = recordedBy
        self.recordedByName = recordedByName
        self.monthsCovered = monthsCovered
    }
}

enum PaymentMethod: String, CaseIterable, Codable, Hashable {
    case cash = "Cash"
    case eft = "EFT"
    case card = "Card"
    case other = "Other"
}

enum SubscriptionFilter: String, CaseIterable, Identifiable {
    case all = "All Members"
    case paid = "Paid This Year"
    case unpaid = "Unpaid"
    case overdue = "Overdue 2+ Years"
    
    var id: String { rawValue }
}
