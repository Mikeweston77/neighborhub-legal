import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct AddPaymentView: View {
    let member: MemberSubscription
    let onSave: (MemberSubscription) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var month: Int = Calendar.current.component(.month, from: Date())
    @State private var monthsCovered: Int = 1
    @State private var amount: String = ""
    @State private var paymentDate = Date()
    @State private var paymentMethod: PaymentMethod = .cash
    @State private var receiptNumber: String = ""
    @State private var notes: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private var currentUserUID: String {
        #if canImport(FirebaseAuth)
        return Auth.auth().currentUser?.uid ?? ""
        #else
        return ""
        #endif
    }
    
    private var currentUserName: String {
        "\(userName) \(userSurname)".trimmingCharacters(in: .whitespaces)
    }
    
    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let date = Calendar.current.date(from: DateComponents(year: 2000, month: month, day: 1))!
        return formatter.string(from: date)
    }
    
    var body: some View {
            Form {
                Section {
                    Text(member.fullName)
                        .font(.headline)
                    
                    if let address = member.address {
                        Text(address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Member")
                }
                
                Section {
                    // Show subscription type and monthly rate
                    HStack {
                        Text("Subscription Type")
                        Spacer()
                        Text(member.effectiveSubscriptionType.displayRate)
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("Year", selection: $year) {
                        ForEach((2020...2030).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthName(month)).tag(month)
                        }
                    }
                    
                    Stepper(value: $monthsCovered, in: 1...12) {
                        Text("Months Covered: \(monthsCovered)")
                    }
                    .onChange(of: monthsCovered) {
                        // Auto-calculate suggested amount
                        let suggestedAmount = member.monthlyRate * Double(monthsCovered)
                        amount = String(format: "%.2f", suggestedAmount)
                    }
                    
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if let amountValue = Double(amount), monthsCovered > 0 {
                        HStack {
                            Text("Per Month")
                            Spacer()
                            Text("R\(String(format: "%.2f", amountValue / Double(monthsCovered)))")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                    
                    DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)
                    
                    Picker("Payment Method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                } header: {
                    Text("Payment Details")
                }
                
                Section {
                    TextField("Receipt #", text: $receiptNumber)
                    
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Additional Information")
                }
                
                Section {
                    HStack {
                        Text("Recorded By")
                        Spacer()
                        Text(currentUserName.isEmpty ? "Admin" : currentUserName)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Audit")
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePayment()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Pre-fill amount with monthly rate
                amount = String(format: "%.2f", member.monthlyRate)
            }
    }
    
    private var isValid: Bool {
        guard let amountValue = Double(amount), amountValue > 0 else {
            return false
        }
        return true
    }
    
    private func savePayment() {
        guard let amountValue = Double(amount) else {
            errorMessage = "Please enter a valid amount"
            showingError = true
            return
        }
        
        let payment = SubscriptionPayment(
            year: year,
            amount: amountValue,
            paymentDate: paymentDate,
            paymentMethod: paymentMethod,
            receiptNumber: receiptNumber.isEmpty ? nil : receiptNumber,
            notes: notes.isEmpty ? nil : notes,
            recordedBy: currentUserUID,
            recordedByName: currentUserName,
            month: month,
            monthsCovered: monthsCovered
        )
        
        var updatedMember = member
        updatedMember.paymentHistory.append(payment)
        
        // Update current year status
        let currentYear = Calendar.current.component(.year, from: Date())
        updatedMember.isPaidCurrentYear = updatedMember.paymentHistory.contains { $0.year == currentYear }
        
        // Update current month status
        let currentMonth = Calendar.current.component(.month, from: Date())
        let currentDate = Date()
        
        // Check if this payment covers the current month
        if year == currentYear && month == currentMonth {
            updatedMember.isPaidCurrentMonth = true
            updatedMember.lastMonthPaid = currentDate
        } else if monthsCovered > 1 {
            // Calculate if multi-month payment covers current month
            var coveredMonths: [DateComponents] = []
            for i in 0..<monthsCovered {
                let components = DateComponents(year: year, month: month + i)
                coveredMonths.append(components)
            }
            
            let coversCurrentMonth = coveredMonths.contains { components in
                components.year == currentYear && components.month == currentMonth
            }
            
            if coversCurrentMonth {
                updatedMember.isPaidCurrentMonth = true
                updatedMember.lastMonthPaid = currentDate
            }
        }
        
        // Update lastMonthPaid to the latest payment date if this is more recent
        if let lastPaid = updatedMember.lastMonthPaid {
            if paymentDate > lastPaid {
                updatedMember.lastMonthPaid = paymentDate
            }
        } else {
            updatedMember.lastMonthPaid = paymentDate
        }
        
        onSave(updatedMember)
        dismiss()
    }
}

enum SubscriptionTrackerContext {
    case yearly
    case monthly
}

struct MemberDetailView: View {
    let onUpdate: (MemberSubscription) -> Void
    let onDelete: ((MemberSubscription) -> Void)?
    let context: SubscriptionTrackerContext
    let subscriptions: [MemberSubscription]?
    
    @State private var localMember: MemberSubscription
    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath = NavigationPath()
    @State private var showEditMember = false
    @State private var showHouseholdManagement = false
    @State private var showEditPaymentStatus = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var selectedHouseholdMemberUID: String? = nil
    @State private var selectedHouseholdMemberSubscription: MemberSubscription? = nil
    
    init(member: MemberSubscription, context: SubscriptionTrackerContext = .yearly, subscriptions: [MemberSubscription]? = nil, onUpdate: @escaping (MemberSubscription) -> Void, onDelete: ((MemberSubscription) -> Void)? = nil) {
        _localMember = State(initialValue: member)
        self.context = context
        self.subscriptions = subscriptions
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }
    
    enum DetailDestination: Hashable {
        case addPayment
    }
    
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }
    
    private var sortedPayments: [SubscriptionPayment] {
        let filtered: [SubscriptionPayment]
        
        switch context {
        case .yearly:
            // Show only yearly payments (no month/monthsCovered)
            filtered = localMember.paymentHistory.filter { payment in
                payment.month == nil || payment.monthsCovered == nil
            }
        case .monthly:
            // Show only monthly payments (has month and monthsCovered)
            filtered = localMember.paymentHistory.filter { payment in
                payment.month != nil && payment.monthsCovered != nil
            }
        }
        
        return filtered.sorted { $0.paymentDate > $1.paymentDate }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Text(localMember.fullName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: { showEditMember = true }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(.systemGray6))

                // Main content
                List {
                Section {
                    LabeledContent("Name", value: localMember.fullName)
                    
                    if let address = localMember.address {
                        HStack {
                            Text("Address")
                            Spacer()
                            Menu {
                                Button(action: {
                                    UIPasteboard.general.string = address
                                }) {
                                    Label("Copy Address", systemImage: "doc.on.doc.fill")
                                }
                                Button(action: {
                                    if let url = URL(string: "maps://?q=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                                        UIApplication.shared.open(url) { success in
                                            if !success {
                                                if let url = URL(string: "https://maps.apple.com/?q=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                                                    UIApplication.shared.open(url)
                                                }
                                            }
                                        }
                                    }
                                }) {
                                    Label("Open in Maps", systemImage: "map.fill")
                                }
                            } label: {
                                Text(address)
                                    .foregroundColor(.blue)
                                Image(systemName: "ellipsis.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if let email = localMember.email {
                        HStack {
                            Text("Email")
                            Spacer()
                            Menu {
                                Button(action: {
                                    if let url = URL(string: "mailto:\(email)") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("Send Email", systemImage: "envelope.fill")
                                }
                                Button(action: {
                                    UIPasteboard.general.string = email
                                }) {
                                    Label("Copy Email", systemImage: "doc.on.doc.fill")
                                }
                            } label: {
                                Text(email)
                                    .foregroundColor(.blue)
                                Image(systemName: "ellipsis.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if let phone = localMember.phone {
                        HStack {
                            Text("Phone")
                            Spacer()
                            Menu {
                                Button(action: {
                                    if let url = URL(string: "tel:\(phone)") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("Call \(phone)", systemImage: "phone.fill")
                                }
                                Button(action: {
                                    var waNumber = phone.filter { $0.isNumber }
                                    if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                        waNumber = "27" + waNumber.dropFirst()
                                    }
                                    if let url = URL(string: "https://wa.me/\(waNumber)") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Label("WhatsApp", systemImage: "message.fill")
                                }
                                Button(action: {
                                    UIPasteboard.general.string = phone
                                }) {
                                    Label("Copy Phone", systemImage: "doc.on.doc.fill")
                                }
                            } label: {
                                Text(phone)
                                    .foregroundColor(.blue)
                                Image(systemName: "ellipsis.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Member Information")
                }
                
                Section {
                    // Show subscription type only for monthly tracker
                    if context == .monthly {
                        HStack {
                            Text("Subscription Type")
                            Spacer()
                            Text(localMember.effectiveSubscriptionType.displayRate)
                                .foregroundColor(localMember.isHousehold ? .purple : .blue)
                                .fontWeight(.semibold)
                        }
                        
                        // Household members management for monthly tracker
                        if localMember.isHousehold {
                            HStack {
                                Text("Household Size")
                                Spacer()
                                Text("\(localMember.householdSize) members")
                                    .foregroundColor(.purple)
                                    .fontWeight(.medium)
                            }
                            
                            // Manage Household Button
                            Button(action: {
                                showHouseholdManagement = true
                            }) {
                                HStack {
                                    Image(systemName: "person.2.fill")
                                        .foregroundColor(.purple)
                                    Text("Manage Household Members")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Add option to convert to household
                            Button(action: {
                                showHouseholdManagement = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Add Household Members")
                                    Spacer()
                                    Text("Upgrade to R99/month")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Show household members list only for yearly tracker
                    if context == .yearly {
                        // Build list of all members: primary + household members
                        let allMembers: [String] = {
                            var members = [localMember.memberUID] // Start with primary
                            if let householdMembers = localMember.householdMembers {
                                members.append(contentsOf: householdMembers)
                            }
                            return members
                        }()
                        
                        if !allMembers.isEmpty {
                            ForEach(Array(allMembers.enumerated()), id: \.offset) { index, userUID in
                                Button {
                                    handleHouseholdMemberTap(userUID: userUID)
                                } label: {
                                    HouseholdMemberDisplayRow(
                                        userUID: userUID,
                                        isPrimary: userUID == localMember.memberUID
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        } else {
                            HStack {
                                Text("No household members")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    
                    // Show monthly info only for monthly tracker
                    if context == .monthly {
                        HStack {
                            Text("Current Month")
                            Spacer()
                            Text((localMember.isPaidCurrentMonth ?? false) ? "Paid ✓" : "Unpaid")
                                .foregroundColor((localMember.isPaidCurrentMonth ?? false) ? .green : .orange)
                                .fontWeight(.semibold)
                        }
                        
                        // Months unpaid and amount due
                        if localMember.monthsUnpaid > 0 {
                            HStack {
                                Text("Months Unpaid")
                                Spacer()
                                Text("\(localMember.monthsUnpaid)")
                                    .foregroundColor(.red)
                                    .fontWeight(.semibold)
                            }
                            
                            HStack {
                                Text("Amount Outstanding")
                                Spacer()
                                Text("R\(Int(localMember.totalOutstanding))")
                                    .foregroundColor(.red)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    
                    // Show yearly info only for yearly tracker
                    if context == .yearly {
                        HStack {
                            Text("Current Year (\(currentYear))")
                            Spacer()
                            Text(localMember.isPaidCurrentYear ? "Paid ✓" : "Unpaid")
                                .foregroundColor(localMember.isPaidCurrentYear ? .green : .orange)
                                .fontWeight(.semibold)
                        }
                        
                        if localMember.yearsUnpaid > 0 {
                            HStack {
                                Text("Years Unpaid")
                                Spacer()
                                Text("\(localMember.yearsUnpaid)")
                                    .foregroundColor(.red)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    
                    if let lastPayment = localMember.lastMonthPaid ?? localMember.lastPaymentDate {
                        LabeledContent("Last Payment") {
                            Text(lastPayment.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    
                    LabeledContent("Total Payments") {
                        Text("\(sortedPayments.count)")
                    }
                } header: {
                    HStack {
                        Text("Status")
                        Spacer()
                        Button {
                            showEditPaymentStatus = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section {
                    if sortedPayments.isEmpty {
                        Text("No payment history")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(sortedPayments) { payment in
                            PaymentHistoryRow(
                                payment: payment,
                                onSaveAmount: { newAmount in
                                    if let index = localMember.paymentHistory.firstIndex(where: { $0.id == payment.id }) {
                                        localMember.paymentHistory[index].amount = newAmount
                                    }
                                    localMember.isPaidCurrentYear = localMember.paymentHistory.contains { $0.year == Calendar.current.component(.year, from: Date()) }
                                    onUpdate(localMember)
                                },
                                onDelete: {
                                    localMember.paymentHistory.removeAll { $0.id == payment.id }
                                    localMember.isPaidCurrentYear = localMember.paymentHistory.contains { $0.year == Calendar.current.component(.year, from: Date()) }
                                    onUpdate(localMember)
                                }
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text("Payment History")
                        Spacer()
                        Button {
                            navigationPath.append(DetailDestination.addPayment)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // Delete Section
                if onDelete != nil {
                    Section {
                        Button(role: .destructive, action: {
                            showDeleteConfirmation = true
                        }) {
                            HStack {
                                Spacer()
                                if isDeleting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("Delete Subscription", systemImage: "trash.fill")
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.red.opacity(0.1))
                    } footer: {
                        Text("This will permanently delete this subscription and all payment history.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
                .navigationDestination(for: DetailDestination.self) { _ in
                    AddPaymentView(member: localMember) { updatedMember in
                        localMember = updatedMember
                        onUpdate(localMember)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditMember) {
            EditMemberView(member: localMember) { updatedMember in
                localMember = updatedMember
                onUpdate(updatedMember)
            }
        }
        .sheet(isPresented: $showHouseholdManagement) {
            HouseholdMemberManagementView(member: $localMember) { updatedMember in
                localMember = updatedMember
                onUpdate(updatedMember)
            }
        }
        .sheet(isPresented: $showEditPaymentStatus) {
            EditPaymentStatusView(member: localMember, context: context) { updatedMember in
                localMember = updatedMember
                onUpdate(updatedMember)
            }
        }
        .alert("Delete Subscription?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSubscription()
            }
        } message: {
            Text("Are you sure you want to delete \(localMember.fullName)'s subscription? This action cannot be undone.")
        }
        .sheet(item: Binding(
            get: { selectedHouseholdMemberSubscription },
            set: { newValue in
                selectedHouseholdMemberSubscription = newValue
                if newValue == nil {
                    selectedHouseholdMemberUID = nil
                }
            }
        )) { memberSubscription in
            MemberDetailView(
                member: memberSubscription,
                context: context,
                subscriptions: subscriptions,
                onUpdate: { updatedMember in
                    onUpdate(updatedMember)
                    // Reload the member if they're the same as the current view
                    if updatedMember.id == localMember.id {
                        localMember = updatedMember
                    }
                },
                onDelete: onDelete
            )
        }
    }
    
    private func deleteSubscription() {
        #if canImport(FirebaseFirestore)
        isDeleting = true
        
        let db = Firestore.firestore()
        db.collection("subscriptions")
            .document(localMember.id.uuidString)
            .delete { error in
                isDeleting = false
                
                if let error = error {
                    print("Error deleting subscription: \(error.localizedDescription)")
                } else {
                    print("Successfully deleted subscription for \(localMember.fullName)")
                    onDelete?(localMember)
                    dismiss()
                }
            }
        #else
        onDelete?(localMember)
        dismiss()
        #endif
    }
    
    private func handleHouseholdMemberTap(userUID: String) {
        #if canImport(FirebaseFirestore)
        // If a subscriptions array was provided, look up the member's subscription
        if let subscriptions = subscriptions {
            if let memberSubscription = subscriptions.first(where: { $0.memberUID == userUID }) {
                selectedHouseholdMemberSubscription = memberSubscription
                return
            }
        }
        
        // If not found in provided array, fetch from Firestore
        let db = Firestore.firestore()
        db.collection("subscriptions")
            .whereField("memberUID", isEqualTo: userUID)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching household member subscription: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents, let doc = documents.first else {
                    print("No subscription found for household member: \(userUID)")
                    return
                }
                
                do {
                    let memberSubscription = try doc.data(as: MemberSubscription.self)
                    selectedHouseholdMemberSubscription = memberSubscription
                } catch {
                    print("Error decoding household member subscription: \(error.localizedDescription)")
                }
            }
        #endif
    }
}

// MARK: - Edit Member Details

struct EditMemberView: View {
    let onSave: (MemberSubscription) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var address: String
    @State private var email: String
    @State private var phone: String

    private let original: MemberSubscription

    init(member: MemberSubscription, onSave: @escaping (MemberSubscription) -> Void) {
        original = member
        self.onSave = onSave
        _firstName = State(initialValue: member.memberName)
        _lastName  = State(initialValue: member.memberSurname)
        _address   = State(initialValue: member.address ?? "")
        _email     = State(initialValue: member.email ?? "")
        _phone     = State(initialValue: member.phone ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Name")) {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }
                Section(header: Text("Address")) {
                    TextField("Street address", text: $address)
                        .autocorrectionDisabled()
                }
                Section(header: Text("Contact")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }
            }
            .navigationTitle("Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updated = original
                        updated.memberName    = firstName.trimmingCharacters(in: .whitespaces)
                        updated.memberSurname = lastName.trimmingCharacters(in: .whitespaces)
                        updated.address = address.trimmingCharacters(in: .whitespaces).isEmpty
                            ? nil : address.trimmingCharacters(in: .whitespaces)
                        updated.email = email.trimmingCharacters(in: .whitespaces).isEmpty
                            ? nil : email.trimmingCharacters(in: .whitespaces)
                        updated.phone = phone.trimmingCharacters(in: .whitespaces).isEmpty
                            ? nil : phone.trimmingCharacters(in: .whitespaces)
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Payment Status

struct EditPaymentStatusView: View {
    let context: SubscriptionTrackerContext
    let onSave: (MemberSubscription) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isPaidCurrentMonth: Bool
    @State private var isPaidCurrentYear: Bool
    @State private var lastMonthPaid: Date
    @State private var monthsUnpaid: Int
    
    private let original: MemberSubscription
    
    init(member: MemberSubscription, context: SubscriptionTrackerContext, onSave: @escaping (MemberSubscription) -> Void) {
        self.original = member
        self.context = context
        self.onSave = onSave
        
        _isPaidCurrentMonth = State(initialValue: member.isPaidCurrentMonth ?? false)
        _isPaidCurrentYear = State(initialValue: member.isPaidCurrentYear)
        _lastMonthPaid = State(initialValue: member.lastMonthPaid ?? Date())
        _monthsUnpaid = State(initialValue: member.monthsUnpaid)
    }
    
    var body: some View {
        NavigationView {
            Form {
                if context == .monthly {
                    Section {
                        Toggle("Paid Current Month", isOn: $isPaidCurrentMonth)
                        
                        DatePicker(
                            "Last Month Paid",
                            selection: $lastMonthPaid,
                            displayedComponents: [.date]
                        )
                        
                        Stepper("Months Unpaid: \(monthsUnpaid)", value: $monthsUnpaid, in: 0...120)
                    } header: {
                        Text("Monthly Subscription Status")
                    } footer: {
                        Text("Adjust the payment status for monthly subscription tracking")
                    }
                }
                
                if context == .yearly {
                    Section {
                        Toggle("Paid Current Year", isOn: $isPaidCurrentYear)
                        
                        if let lastPayment = original.lastPaymentDate {
                            LabeledContent("Last Payment Date") {
                                Text(lastPayment.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        LabeledContent("Years Unpaid") {
                            Text("\(original.yearsUnpaid)")
                                .foregroundColor(original.yearsUnpaid > 0 ? .red : .secondary)
                        }
                    } header: {
                        Text("Yearly Subscription Status")
                    } footer: {
                        Text("Payment dates and years unpaid are calculated from payment history. Use the Payment History section to add or edit actual payment records.")
                    }
                }
                
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Changes will be reflected immediately in the subscription tracker")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Payment Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
    }
    
    private func saveChanges() {
        var updated = original
        
        if context == .monthly {
            updated.isPaidCurrentMonth = isPaidCurrentMonth
            updated.lastMonthPaid = lastMonthPaid
            // Note: monthsUnpaid is a computed property based on lastMonthPaid
            // We update lastMonthPaid to reflect the unpaid months
            if monthsUnpaid > 0 {
                let calendar = Calendar.current
                updated.lastMonthPaid = calendar.date(byAdding: .month, value: -monthsUnpaid, to: Date())
            } else {
                updated.lastMonthPaid = Date()
            }
        }
        
        if context == .yearly {
            updated.isPaidCurrentYear = isPaidCurrentYear
            // Note: lastPaymentDate is computed from paymentHistory and cannot be set directly
            // Note: yearsUnpaid is also a computed property based on payment history
            // To update these, add actual payment records through the payment history section
        }
        
        onSave(updated)
        dismiss()
    }
}

struct PaymentHistoryRow: View {
    let payment: SubscriptionPayment
    let onSaveAmount: (Double) -> Void
    let onDelete: () -> Void
    
    @State private var isEditing = false
    @State private var editAmount: String = ""
    @FocusState private var amountFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let month = payment.month {
                        Text("\(monthName(month)) \(payment.year)")
                            .font(.headline)
                        
                        if let monthsCovered = payment.monthsCovered, monthsCovered > 1 {
                            Text("(\(monthsCovered) months)")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    } else {
                        Text("Year \(payment.year)")
                            .font(.headline)
                    }
                }
                
                Spacer()
                
                if isEditing {
                    HStack(spacing: 4) {
                        Text("R")
                            .font(.headline)
                            .foregroundColor(.green)
                        TextField("0.00", text: $editAmount)
                            .keyboardType(.decimalPad)
                            .font(.headline)
                            .foregroundColor(.green)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($amountFocused)
                    }
                } else {
                    Text("R\(String(format: "%.2f", payment.amount))")
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }
            
            HStack(spacing: 12) {
                Label(payment.paymentMethod.rawValue, systemImage: paymentMethodIcon(payment.paymentMethod))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(payment.paymentDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let receipt = payment.receiptNumber {
                Text("Receipt: \(receipt)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let notes = payment.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            Text("Recorded by \(payment.recordedByName)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Edit/Delete buttons
            HStack(spacing: 16) {
                if isEditing {
                    Button {
                        if let value = Double(editAmount), value > 0 {
                            onSaveAmount(value)
                        }
                        isEditing = false
                        amountFocused = false
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        isEditing = false
                        amountFocused = false
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        editAmount = String(format: "%.2f", payment.amount)
                        isEditing = true
                        amountFocused = true
                    } label: {
                        Label("Edit Amount", systemImage: "pencil")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
    
    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let date = Calendar.current.date(from: DateComponents(year: 2000, month: month, day: 1))!
        return formatter.string(from: date)
    }
    
    private func paymentMethodIcon(_ method: PaymentMethod) -> String {
        switch method {
        case .cash: return "banknote"
        case .eft: return "building.columns"
        case .card: return "creditcard"
        case .other: return "ellipsis.circle"
        }
    }
}

struct EditPaymentView: View {
    let member: MemberSubscription
    let payment: SubscriptionPayment
    let onSave: (MemberSubscription) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    
    @State private var year: Int
    @State private var amount: String
    @State private var paymentDate: Date
    @State private var paymentMethod: PaymentMethod
    @State private var receiptNumber: String
    @State private var notes: String
    
    init(member: MemberSubscription, payment: SubscriptionPayment, onSave: @escaping (MemberSubscription) -> Void) {
        self.member = member
        self.payment = payment
        self.onSave = onSave
        _year = State(initialValue: payment.year)
        _amount = State(initialValue: String(format: "%.2f", payment.amount))
        _paymentDate = State(initialValue: payment.paymentDate)
        _paymentMethod = State(initialValue: payment.paymentMethod)
        _receiptNumber = State(initialValue: payment.receiptNumber ?? "")
        _notes = State(initialValue: payment.notes ?? "")
    }
    
    var body: some View {
            Form {
                Section {
                    Text(member.fullName)
                        .font(.headline)
                    
                    if let address = member.address {
                        Text(address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Member")
                }
                
                Section {
                    Picker("Year", selection: $year) {
                        ForEach((2020...2030).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)
                    
                    Picker("Payment Method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                } header: {
                    Text("Payment Details")
                }
                
                Section {
                    TextField("Receipt #", text: $receiptNumber)
                    
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Additional Information")
                }
            }
            .navigationTitle("Edit Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard let amountValue = Double(amount) else { return }
                        
                        var updatedMember = member
                        if let index = updatedMember.paymentHistory.firstIndex(where: { $0.id == payment.id }) {
                            updatedMember.paymentHistory[index] = SubscriptionPayment(
                                year: year,
                                amount: amountValue,
                                paymentDate: paymentDate,
                                paymentMethod: paymentMethod,
                                receiptNumber: receiptNumber.isEmpty ? nil : receiptNumber,
                                notes: notes.isEmpty ? nil : notes,
                                recordedBy: payment.recordedBy,
                                recordedByName: payment.recordedByName
                            )
                        }
                        
                        onSave(updatedMember)
                        dismiss()
                    }
                    .disabled(amount.isEmpty)
                }
            }
    }
}

// MARK: - Previews

struct AddPaymentView_Previews: PreviewProvider {
    static var previews: some View {
        AddPaymentView(
            member: MemberSubscription(
                memberUID: "123",
                memberName: "John",
                memberSurname: "Doe",
                address: "123 Main St"
            )
        ) { _ in }
    }
}

// MARK: - Household Member Management View

struct HouseholdMemberManagementView: View {
    @Binding var member: MemberSubscription
    let onSave: (MemberSubscription) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var availableUsers: [RegisteredUser] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showAddMemberSection = false
    
    struct RegisteredUser: Identifiable {
        let id: String // UID
        let name: String
        let email: String
        let address: String?
    }
    
    private var filteredAvailableUsers: [RegisteredUser] {
        if searchText.isEmpty {
            return availableUsers
        }
        return availableUsers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Info
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Household Members")
                                .font(.headline)
                            Text("\(member.householdSize) of \(MemberSubscription.maxHouseholdMembers) slots used")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(member.effectiveSubscriptionType.displayRate)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(member.isHousehold ? Color.purple : Color.blue)
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                }
                
                Divider()
                
                List {
                    // Current Members Section
                    Section {
                        // Build list of all members: primary + household members
                        let allMembers: [String] = {
                            var members = [member.memberUID] // Start with primary
                            if let householdMembers = member.householdMembers {
                                members.append(contentsOf: householdMembers)
                            }
                            return members
                        }()
                        
                        if !allMembers.isEmpty {
                            ForEach(Array(allMembers.enumerated()), id: \.offset) { index, userUID in
                                HouseholdMemberRow(
                                    userUID: userUID,
                                    isPrimary: userUID == member.memberUID,
                                    onRemove: {
                                        // Only allow removing non-primary members
                                        if userUID != member.memberUID {
                                            member.removeHouseholdMember(userUID)
                                        }
                                    }
                                )
                            }
                        } else {
                            Text("No household members")
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    } header: {
                        Text("Current Members (\(member.householdSize))")
                    } footer: {
                        if member.canAddHouseholdMember {
                            Text("\(member.remainingHouseholdSlots) slot\(member.remainingHouseholdSlots == 1 ? "" : "s") remaining")
                                .font(.caption)
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Household is full (max 5 members)")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    // Add Member Section
                    if member.canAddHouseholdMember {
                        Section {
                            Button(action: {
                                showAddMemberSection.toggle()
                                if showAddMemberSection && availableUsers.isEmpty {
                                    Task {
                                        await loadAvailableUsersAtSameAddress()
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: showAddMemberSection ? "chevron.down" : "chevron.right")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    Text("Add Members at Same Address")
                                        .foregroundColor(.blue)
                                    Spacer()
                                    if isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            
                            if showAddMemberSection {
                                if isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView("Loading users...")
                                        Spacer()
                                    }
                                    .padding()
                                } else if filteredAvailableUsers.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.2.slash")
                                            .font(.largeTitle)
                                            .foregroundColor(.secondary)
                                        Text("No available users found")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        if let address = member.address {
                                            let firstLine = address.components(separatedBy: ",").first ?? address
                                            Text("Looking for users at: \(firstLine)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal)
                                            Text("Tip: Verify address format matches other users")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                } else {
                                    // Search bar
                                    HStack {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(.secondary)
                                        TextField("Search users...", text: $searchText)
                                            .textFieldStyle(.plain)
                                        if !searchText.isEmpty {
                                            Button(action: { searchText = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                    
                                    ForEach(filteredAvailableUsers) { user in
                                        Button(action: {
                                            addMemberToHousehold(user.id)
                                        }) {
                                            HStack {
                                                Circle()
                                                    .fill(Color.green)
                                                    .frame(width: 8, height: 8)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(user.name)
                                                        .foregroundColor(.primary)
                                                    Text(user.email)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "plus.circle.fill")
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        } header: {
                            Text("Add Household Members")
                        } footer: {
                            if showAddMemberSection && !filteredAvailableUsers.isEmpty {
                                Text("Users at the same street address who are not in other households")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    // Info Section
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            SubscriptionInfoRow(icon: "info.circle", text: "Household rate: R99/month")
                            SubscriptionInfoRow(icon: "person.fill", text: "Single rate: R50/month")
                            SubscriptionInfoRow(icon: "checkmark.circle", text: "Maximum 5 members per household")
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Information")
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Manage Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(member)
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadAvailableUsersAtSameAddress() async {
        #if canImport(FirebaseFirestore)
        isLoading = true
        defer { isLoading = false }
        
        // Build set of all members in current household (primary + household members)
        var existingMembers = Set<String>()
        existingMembers.insert(member.memberUID) // Add primary
        if let members = member.householdMembers {
            existingMembers.formUnion(members) // Add all household members
        }
        
        // Get current member's address for filtering
        guard let currentAddress = member.address, !currentAddress.isEmpty else {
            print("DEBUG [Admin]: No address set for current member")
            availableUsers = []
            return
        }
        
        print("DEBUG [Admin]: Original full address: '\(currentAddress)'")
        
        // Extract first line (street address) before comma
        let currentFirstLine = currentAddress.components(separatedBy: ",").first ?? currentAddress
        
        // Normalize the first address line for comparison
        let normalizedCurrentAddress = currentFirstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        print("DEBUG [Admin]: First address line (normalized): '\(normalizedCurrentAddress)'")
        
        guard !normalizedCurrentAddress.isEmpty else {
            print("DEBUG [Admin]: Address became empty after normalization")
            availableUsers = []
            return
        }
        
        print("DEBUG [Admin]: Searching for users at street address: \(normalizedCurrentAddress)")
        print("DEBUG [Admin]: Current member UID: \(member.memberUID)")
        
        do {
            // Step 1: Get all household members across all subscriptions
            // to exclude users who are already in other households.
            let allSubscriptions = try await Firestore.firestore()
                .collection("subscriptions")
                .getDocuments()
            
            var usersInOtherHouseholds = Set<String>()
            for doc in allSubscriptions.documents {
                if let members = doc.data()["householdMembers"] as? [String] {
                    usersInOtherHouseholds.formUnion(members)
                }
            }
            
            print("DEBUG [Admin]: Users already in households: \(usersInOtherHouseholds)")
            
            // Step 2: Load candidate users from users collection.
            // This ensures newly registered users are discoverable even if they have no
            // subscription record yet.
            let usersSnapshot = try await Firestore.firestore()
                .collection("users")
                .getDocuments()

            var allUsers: [RegisteredUser] = []
            for doc in usersSnapshot.documents {
                let data = doc.data()
                let uid = doc.documentID

                guard uid != member.memberUID else { continue }

                let userAddress = userAddressString(from: data)
                let normalizedUserAddress = normalizedStreetAddress(userAddress)
                guard !normalizedUserAddress.isEmpty,
                      normalizedUserAddress == normalizedCurrentAddress else {
                    continue
                }

                let firstName = (data["firstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let lastName = (data["lastName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let composedName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
                let email = (data["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let displayName = composedName.isEmpty ? (email.isEmpty ? uid : email) : composedName

                allUsers.append(
                    RegisteredUser(
                        id: uid,
                        name: displayName,
                        email: email,
                        address: userAddress
                    )
                )
            }
            
            print("DEBUG [Admin]: Total users loaded before filtering: \(allUsers.count)")
            print("DEBUG [Admin]: Existing household members: \(existingMembers)")
            print("DEBUG [Admin]: Users in other households: \(usersInOtherHouseholds)")
            
            // Filter out users who are already in current household OR in other households (as dependent members)
            let filteredUsers = allUsers.filter { user in
                let isInCurrentHousehold = existingMembers.contains(user.id)
                let isInOtherHousehold = usersInOtherHouseholds.contains(user.id)
                let shouldInclude = !isInCurrentHousehold && !isInOtherHousehold
                
                if !shouldInclude {
                    if isInCurrentHousehold {
                        print("DEBUG [Admin]: Filtering out \(user.name) (\(user.id)) - already in current household")
                    } else if isInOtherHousehold {
                        print("DEBUG [Admin]: Filtering out \(user.name) (\(user.id)) - already in another household")
                    }
                } else {
                    print("DEBUG [Admin]: ✅ Including \(user.name) (\(user.id)) in available users")
                }
                
                return shouldInclude
            }
            
            availableUsers = filteredUsers.sorted { $0.name < $1.name }
            print("DEBUG [Admin]: ===== FINAL RESULT =====")
            print("DEBUG [Admin]: Loaded \(availableUsers.count) available users at address: \(availableUsers.map { $0.name })")
            print("DEBUG [Admin]: ===========================")
        } catch {
            print("Error loading available users: \(error)")
            errorMessage = "Failed to load available users: \(error.localizedDescription)"
            showError = true
        }
        #endif
    }

    private func normalizedStreetAddress(_ address: String?) -> String {
        guard let address, !address.isEmpty else { return "" }
        let firstLine = address.components(separatedBy: ",").first ?? address
        return firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func userAddressString(from data: [String: Any]) -> String {
        if let fullAddress = data["address"] as? String,
           !fullAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fullAddress
        }

        let street = (data["street"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suburb = (data["suburb"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = (data["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let postalCode = (data["postalCode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let locality = [suburb, city].filter { !$0.isEmpty }.joined(separator: ", ")
        let localityWithPostal = [locality, postalCode].filter { !$0.isEmpty }.joined(separator: " ")
        return [street, localityWithPostal].filter { !$0.isEmpty }.joined(separator: ", ")
    }
    
    private func addMemberToHousehold(_ userUID: String) {
        let result = member.addHouseholdMember(userUID)
        
        switch result {
        case .success:
            // Remove from available users list
            availableUsers.removeAll { $0.id == userUID }
            // Don't auto-save here - user needs to click Save button
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct HouseholdMemberRow: View {
    let userUID: String
    let isPrimary: Bool
    let onRemove: () -> Void
    
    @State private var userName: String = ""
    @State private var isLoading: Bool = true
    
    var body: some View {
        HStack {
            Circle()
                .fill(isPrimary ? Color.purple : Color.blue)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                if isLoading {
                    Text("Loading...")
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    Text(userName)
                        .font(.body)
                }
                
                if isPrimary {
                    Text("Primary Member")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
            
            Spacer()
            
            if !isPrimary {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            await loadUserName()
        }
    }
    
    private func loadUserName() async {
        #if canImport(FirebaseFirestore)
        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(userUID)
                .getDocument()
            
            if let data = doc.data(),
               let firstName = data["firstName"] as? String,
               let lastName = data["lastName"] as? String {
                userName = "\(firstName) \(lastName)"
            } else {
                userName = userUID
            }
        } catch {
            print("Error loading user name: \(error)")
            userName = userUID
        }
        isLoading = false
        #else
        userName = userUID
        isLoading = false
        #endif
    }
}

// Display-only household member row (used in yearly tracker detail view)
struct HouseholdMemberDisplayRow: View {
    let userUID: String
    let isPrimary: Bool
    
    @State private var userName: String = ""
    @State private var isLoading: Bool = true
    
    var body: some View {
        HStack {
            Circle()
                .fill(isPrimary ? Color.purple : Color.blue)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                if isLoading {
                    Text("Loading...")
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    Text(userName)
                        .font(.body)
                }
                
                if isPrimary {
                    Text("Primary Member")
                        .font(.caption)
                        .foregroundColor(.purple)
                } else {
                    Text("Household Member")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
        }
        .task {
            await loadUserName()
        }
    }
    
    private func loadUserName() async {
        #if canImport(FirebaseFirestore)
        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(userUID)
                .getDocument()
            
            if let data = doc.data(),
               let firstName = data["firstName"] as? String,
               let lastName = data["lastName"] as? String {
                userName = "\(firstName) \(lastName)"
            } else {
                userName = userUID
            }
        } catch {
            print("Error loading user name: \(error)")
            userName = userUID
        }
        isLoading = false
        #else
        userName = userUID
        isLoading = false
        #endif
    }
}

struct SubscriptionInfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct MemberDetailView_Previews: PreviewProvider {
    static var previews: some View {
        MemberDetailView(
            member: MemberSubscription(
                memberUID: "123",
                memberName: "John",
                memberSurname: "Doe",
                address: "123 Main St",
                paymentHistory: [
                    SubscriptionPayment(
                        year: 2024,
                        amount: 500,
                        recordedBy: "admin",
                        recordedByName: "Admin User"
                    )
                ]
            )
        ) { _ in }
    }
}
