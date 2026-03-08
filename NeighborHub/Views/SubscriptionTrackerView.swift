import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif


// Wrapper for sheet binding using memberUID
struct MemberSheetItem: Identifiable, Equatable {
    let memberUID: String
    var id: String { memberUID }
}

// Wrapper for the household group sheet
struct AddressGroup: Identifiable {
    let id = UUID()
    let address: String
    let members: [MemberSubscription]
}

struct SubscriptionTrackerView: View {

    var skipAuthCheck: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SubscriptionTrackerViewModel()
    @State private var searchText: String = ""
    @State private var selectedFilter: SubscriptionFilter = .all
    @State private var showingAddPayment = false
    @State private var selectedMemberSheetItem: MemberSheetItem?
    @State private var addPaymentMemberSheetItem: MemberSheetItem?
    @State private var isLoading = false
    @State private var selectedMemberSnapshot: MemberSubscription?
    @State private var addPaymentMemberSnapshot: MemberSubscription?
    @State private var showingAddMember = false
    @State private var showingBulkPayment = false
    @State private var showingBulkEdit = false
    // Removed isRefreshing; no manual refresh
    @State private var selectedAddressGroup: AddressGroup? = nil
    @State private var showExportSheet = false
    @State private var exportURL: URL? = nil
    @State private var showMailSheet = false
    @State private var mailRecipients: [String] = []
    @State private var showMailErrorAlert = false
    @State private var mailAlertMessage: String? = nil
    @State private var showReminderDialog = false
    @State private var unpaidWithEmail: [MemberSubscription] = []
    @State private var unpaidWithoutEmail: [MemberSubscription] = []
    @State private var reminderEmailSubject: String = ""
    @State private var reminderEmailBody: String = ""

    var selectedMember: MemberSubscription? {
        guard let item = selectedMemberSheetItem else { return nil }
        return viewModel.subscriptions.first(where: { $0.memberUID == item.memberUID })
    }
    var addPaymentMember: MemberSubscription? {
        guard let item = addPaymentMemberSheetItem else { return nil }
        return viewModel.subscriptions.first(where: { $0.memberUID == item.memberUID })
    }

    private var isAuthorized: Bool {
        skipAuthCheck || viewModel.canListSubscriptions()
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var filteredSubscriptions: [MemberSubscription] {
        var filtered = viewModel.subscriptions
        
        // First, exclude users who are dependent members in households
        // Build set of all UIDs that appear in householdMembers arrays
        var dependentMemberUIDs = Set<String>()
        for subscription in viewModel.subscriptions {
            if let householdMembers = subscription.householdMembers {
                dependentMemberUIDs.formUnion(householdMembers)
            }
        }
        
        // Filter out dependent household members from the main list
        filtered = filtered.filter { subscription in
            !dependentMemberUIDs.contains(subscription.memberUID)
        }
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .paid:
            filtered = filtered.filter { $0.isPaidCurrentYear }
        case .unpaid:
            filtered = filtered.filter { !$0.isPaidCurrentYear }
        case .overdue:
            filtered = filtered.filter { $0.yearsUnpaid >= 2 }
        }
        // Apply search
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.fullName.localizedCaseInsensitiveContains(searchText) ||
                $0.address?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        return filtered.sorted { $0.fullName < $1.fullName }
    }

    /// Members grouped by address. Multiple residents at the same address are
    /// clustered together; members without an address each get their own entry.
    private var groupedSubscriptions: [(key: String, members: [MemberSubscription])] {
        var groups: [String: [MemberSubscription]] = [:]
        var noAddressMembers: [MemberSubscription] = []

        for member in filteredSubscriptions {
            if let addr = member.address?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty {
                let normalised = addr.lowercased()
                groups[normalised, default: []].append(member)
            } else {
                noAddressMembers.append(member)
            }
        }

        // Sort groups by the display address, then sort members within each group
        var result = groups
            .map { (key: $0.value.first?.address ?? $0.key,
                    members: $0.value.sorted { $0.fullName < $1.fullName }) }
            .sorted { $0.key.lowercased() < $1.key.lowercased() }

        // Append no-address members, each as their own group
        for member in noAddressMembers {
            result.append((key: member.fullName, members: [member]))
        }

        return result
    }

    private var statistics: (total: Int, paid: Int, unpaid: Int, overdue: Int) {
        // Filter out dependent household members for accurate statistics
        var dependentMemberUIDs = Set<String>()
        for subscription in viewModel.subscriptions {
            if let householdMembers = subscription.householdMembers {
                dependentMemberUIDs.formUnion(householdMembers)
            }
        }
        
        let primarySubscriptions = viewModel.subscriptions.filter { subscription in
            !dependentMemberUIDs.contains(subscription.memberUID)
        }
        
        let total = primarySubscriptions.count
        let paid = primarySubscriptions.filter { $0.isPaidCurrentYear }.count
        let unpaid = primarySubscriptions.filter { !$0.isPaidCurrentYear }.count
        let overdue = primarySubscriptions.filter { $0.yearsUnpaid >= 2 }.count
        
        return (total, paid, unpaid, overdue)
    }
    
    var body: some View {
        Group {
            if !isAuthorized {
                unauthorizedView
            } else {
                authorizedView
            }
        }
        .navigationTitle("Subscription Tracker")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                        Text("Close")
                            .font(.subheadline)
                    }
                    .foregroundColor(.gray)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // (Sync/Refresh button removed for live updates)
                    
                    // Add button
                    Button(action: {
                        showingAddMember = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    
                    // Menu button
                    Menu {
                        Button(action: {
                            showingBulkPayment = true
                        }) {
                            Label("Bulk Payment Capture", systemImage: "creditcard.fill")
                        }
                        
                        Button(action: {
                            showingBulkEdit = true
                        }) {
                            Label("Bulk Edit Members", systemImage: "pencil.circle.fill")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            exportData()
                        }) {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: {
                            sendReminders()
                        }) {
                            Label("Send Reminders", systemImage: "envelope.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingAddMember) {
            AddMemberView { newMember in
                viewModel.updateMember(newMember)
                showingAddMember = false
            }
        }
        .fullScreenCover(isPresented: $showingBulkPayment) {
            BulkPaymentView(members: filteredSubscriptions) { updatedMembers in
                for updatedMember in updatedMembers {
                    viewModel.updateMember(updatedMember)
                }
                showingBulkPayment = false
            }
        }
        .fullScreenCover(isPresented: $showingBulkEdit) {
            BulkEditMembersView(members: filteredSubscriptions) { updatedMembers in
                for updatedMember in updatedMembers {
                    viewModel.updateMember(updatedMember)
                }
                showingBulkEdit = false
            }
        }
    }
    
    private var unauthorizedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Admin Access Only")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("This feature is only available to administrators and committee members.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var authorizedView: some View {
        VStack(spacing: 0) {
            // Statistics Bar
            statisticsBar
            
            // Filter Pills
            filterPills
            
            // Search Bar
            searchBar
            
            // Members List
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSubscriptions.isEmpty {
                emptyStateView
            } else {
                membersList
            }
        }
        .confirmationDialog(
            "Send Reminder Emails",
            isPresented: $showReminderDialog,
            titleVisibility: .visible
        ) {
            Button("Send Email to \(unpaidWithEmail.count) Members") {
                mailRecipients = unpaidWithEmail.compactMap { $0.email }
                showMailSheet = true
                showReminderDialog = false
            }
            if !unpaidWithoutEmail.isEmpty {
                Button("Show \(unpaidWithoutEmail.count) Without Email") {
                    mailAlertMessage = "The following members do not have an email address on file:\n\n" + unpaidWithoutEmail.map { $0.fullName }.joined(separator: "\n")
                    showMailErrorAlert = true
                    showReminderDialog = false
                }
            }
            Button("Cancel", role: .cancel) {
                showReminderDialog = false
            }
        }
        .alert(isPresented: $showMailErrorAlert) {
            Alert(title: Text("Missing Emails"), message: Text(mailAlertMessage ?? ""), dismissButton: .default(Text("OK")))
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedMemberSnapshot != nil },
            set: { if !$0 { selectedMemberSnapshot = nil; selectedMemberSheetItem = nil } }
        )) {
            if let member = selectedMemberSnapshot {
                MemberDetailView(member: member, context: .yearly, subscriptions: viewModel.subscriptions) { updatedMember in
                    viewModel.updateMember(updatedMember)
                    selectedMemberSnapshot = updatedMember
                } onDelete: { deletedMember in
                    viewModel.deleteMember(deletedMember)
                    selectedMemberSnapshot = nil
                    selectedMemberSheetItem = nil
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { addPaymentMemberSnapshot != nil },
            set: { if !$0 { addPaymentMemberSnapshot = nil; addPaymentMemberSheetItem = nil } }
        )) {
            if let member = addPaymentMemberSnapshot {
                AddPaymentView(member: member) { updatedMember in
                    viewModel.updateMember(updatedMember)
                    addPaymentMemberSnapshot = nil
                    addPaymentMemberSheetItem = nil
                }
            }
        }
        .sheet(item: $selectedAddressGroup) { group in
            AddressGroupSheet(group: group) { updatedMember in
                viewModel.updateMember(updatedMember)
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ActivityView(activityItems: [url])
            }
        }
        .sheet(isPresented: $showMailSheet) {
            if MailComposeView.canSendMail {
                MailComposeView(recipients: mailRecipients,
                                subject: reminderEmailSubject,
                                body: reminderEmailBody)
            } else {
                VStack(spacing: 20) {
                    Text("Mail services are not available on this device.")
                        .font(.headline)
                        .padding(.top)
                    Text("You can open the Mail app with the email pre-filled for up to 5 recipients.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Open Mail App") {
                        openMailAppFallback()
                        showMailSheet = false
                    }
                    .padding()
                    Button("Cancel") {
                        showMailSheet = false
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    private var statisticsBar: some View {
        HStack(spacing: 12) {
            StatBox(title: "Total", value: "\(statistics.total)", color: .blue)
            StatBox(title: "Paid", value: "\(statistics.paid)", color: .green)
            StatBox(title: "Unpaid", value: "\(statistics.unpaid)", color: .orange)
            StatBox(title: "Overdue 2+", value: "\(statistics.overdue)", color: .red)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }
    
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SubscriptionFilter.allCases) { filter in
                    FilterPill(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search by name or address...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
    
    private var membersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(groupedSubscriptions, id: \.key) { group in
                    if group.members.count > 1 {
                        // Multiple residents share this address — tap opens household sheet
                        AddressGroupCard(address: group.key, members: group.members) {
                            selectedAddressGroup = AddressGroup(address: group.key, members: group.members)
                        }
                        .contextMenu {
                            ForEach(group.members) { member in
                                Button {
                                    selectedMemberSnapshot = member
                                    selectedMemberSheetItem = MemberSheetItem(memberUID: member.memberUID)
                                } label: {
                                    Label(member.fullName, systemImage: "person")
                                }
                            }
                            
                            Divider()
                            
                            Menu {
                                ForEach(group.members) { member in
                                    Button(role: .destructive) {
                                        viewModel.deleteMember(member)
                                    } label: {
                                        Label("Delete \(member.fullName)", systemImage: "trash")
                                    }
                                }
                            } label: {
                                Label("Delete Members", systemImage: "trash")
                            }
                        }
                    } else if let member = group.members.first {
                        // Single resident
                        MemberSubscriptionCard(member: member)
                            .onTapGesture {
                                selectedMemberSnapshot = member
                                selectedMemberSheetItem = MemberSheetItem(memberUID: member.memberUID)
                            }
                            .contextMenu {
                                Button {
                                    addPaymentMemberSnapshot = member
                                    addPaymentMemberSheetItem = MemberSheetItem(memberUID: member.memberUID)
                                } label: {
                                    Label("Record Payment", systemImage: "dollarsign.circle")
                                }
                                Button {
                                    selectedMemberSnapshot = member
                                    selectedMemberSheetItem = MemberSheetItem(memberUID: member.memberUID)
                                } label: {
                                    Label("View Details", systemImage: "info.circle")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    viewModel.deleteMember(member)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No Members Found")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(searchText.isEmpty ? "No subscription records yet." : "Try adjusting your search.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Removed refreshData; no manual refresh
    
    private func exportData() {
        let csvString = generateCSV()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("subscriptions.csv")
        do {
            try csvString.write(to: tempURL, atomically: true, encoding: .utf8)
            exportURL = tempURL
            showExportSheet = true
        } catch {
            // Optionally show an error alert
        }
    }
    
    private func sendReminders() {
        let unpaid = viewModel.subscriptions.filter { !$0.isPaidCurrentYear }
        unpaidWithEmail = unpaid.filter { ($0.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }
        unpaidWithoutEmail = unpaid.filter { $0.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
        // Compose subject and body
        let year = Calendar.current.component(.year, from: Date())
        reminderEmailSubject = "Subscription Payment Reminder - \(year)"
        let memberList = unpaidWithEmail.map { "• \($0.fullName) (\($0.address ?? "No address"))" }.joined(separator: "\n")
        reminderEmailBody = "Dear neighbors,\n\nThe following members have not yet paid their annual subscription for \(year):\n\n\(memberList)\n\nPlease settle your payment at your earliest convenience. If you have already paid, please disregard this message.\n\nIf you have questions, contact the committee.\n\nThank you!\nWaterfall Committee"
        showReminderDialog = true
    }
    
    private func generateCSV() -> String {
        var csv = "Name,Address,Email,Phone,Paid This Year,Years Unpaid,Last Payment\n"
        
        for member in filteredSubscriptions {
            let line = "\(member.fullName),\(member.address ?? ""),\(member.email ?? ""),\(member.phone ?? ""),\(member.isPaidCurrentYear ? "Yes" : "No"),\(member.yearsUnpaid),\(member.lastPaymentDate?.formatted(date: .abbreviated, time: .omitted) ?? "N/A")\n"
            csv.append(line)
        }
        
        return csv
    }
}

// MARK: - Additional Views

struct AddMemberView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (MemberSubscription) -> Void
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var address = ""
    @State private var email = ""
    @State private var phone = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Add Member")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Form content
            Form {
                Section("Member Details") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("Address", text: $address)
                    TextField("Email", text: $email)
                    TextField("Phone", text: $phone)
                }
            }
            
            // Save button
            Button(action: {
                let newMember = MemberSubscription(
                    memberUID: UUID().uuidString,
                    memberName: firstName,
                    memberSurname: lastName,
                    address: address.isEmpty ? nil : address,
                    email: email.isEmpty ? nil : email,
                    phone: phone.isEmpty ? nil : phone
                )
                onSave(newMember)
                dismiss()
            }) {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                    .padding()
            }
            .disabled(firstName.isEmpty || lastName.isEmpty)
        }
    }
}

struct BulkPaymentView: View {
    @Environment(\.dismiss) private var dismiss
    let members: [MemberSubscription]
    let onSave: ([MemberSubscription]) -> Void
    
    @State private var selectedMembers = Set<String>()
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var amount = ""
    @State private var paymentDate = Date()
    @State private var paymentMethod: PaymentMethod = .cash
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Bulk Payment")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            Form {
                Section("Payment Details") {
                    Picker("Year", selection: $year) {
                        ForEach((2020...2030).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    DatePicker("Date", selection: $paymentDate, displayedComponents: .date)
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                }
                
                Section("Select Members") {
                    ForEach(members) { member in
                        CheckboxRow(
                            title: member.fullName,
                            isSelected: selectedMembers.contains(member.memberUID),
                            action: {
                                if selectedMembers.contains(member.memberUID) {
                                    selectedMembers.remove(member.memberUID)
                                } else {
                                    selectedMembers.insert(member.memberUID)
                                }
                            }
                        )
                    }
                }
            }
            
            // Save button
            Button(action: {
                var updatedMembers: [MemberSubscription] = []
                guard let amountValue = Double(amount) else { return }
                
                for member in members {
                    if selectedMembers.contains(member.memberUID) {
                        var updated = member
                        let payment = SubscriptionPayment(
                            year: year,
                            amount: amountValue,
                            paymentDate: paymentDate,
                            paymentMethod: paymentMethod,
                            recordedBy: UUID().uuidString,
                            recordedByName: "Admin"
                        )
                        updated.paymentHistory.append(payment)
                        updated.isPaidCurrentYear = true
                        updatedMembers.append(updated)
                    }
                }
                onSave(updatedMembers)
                dismiss()
            }) {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                    .padding()
            }
            .disabled(selectedMembers.isEmpty || amount.isEmpty)
        }
    }
}

struct BulkEditMembersView: View {
    @Environment(\.dismiss) private var dismiss
    let members: [MemberSubscription]
    let onSave: ([MemberSubscription]) -> Void
    
    @State private var selectedMembers = Set<String>()
    @State private var editField: EditField = .address
    @State private var editValue = ""
    
    enum EditField: String, CaseIterable {
        case address = "Address"
        case email = "Email"
        case phone = "Phone"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Bulk Edit")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            Form {
                Section("Select Members") {
                    ForEach(members) { member in
                        CheckboxRow(
                            title: member.fullName,
                            isSelected: selectedMembers.contains(member.memberUID),
                            action: {
                                if selectedMembers.contains(member.memberUID) {
                                    selectedMembers.remove(member.memberUID)
                                } else {
                                    selectedMembers.insert(member.memberUID)
                                }
                            }
                        )
                    }
                }
                
                Section("Edit") {
                    Picker("Field", selection: $editField) {
                        ForEach(EditField.allCases, id: \.self) { field in
                            Text(field.rawValue).tag(field)
                        }
                    }
                    TextField("New Value", text: $editValue)
                }
            }
            
            // Save button
            Button(action: {
                var updatedMembers: [MemberSubscription] = []
                
                for member in members {
                    if selectedMembers.contains(member.memberUID) {
                        var updated = member
                        switch editField {
                        case .address:
                            updated.address = editValue.isEmpty ? nil : editValue
                        case .email:
                            updated.email = editValue.isEmpty ? nil : editValue
                        case .phone:
                            updated.phone = editValue.isEmpty ? nil : editValue
                        }
                        updatedMembers.append(updated)
                    }
                }
                onSave(updatedMembers)
                dismiss()
            }) {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                    .padding()
            }
            .disabled(selectedMembers.isEmpty || editValue.isEmpty)
        }
    }
}

struct CheckboxRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(.blue)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
            }
        }
    }
}

// MARK: - Supporting Views

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }
}

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .cornerRadius(20)
        }
    }
}

struct MemberSubscriptionCard: View {
    let member: MemberSubscription
    
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            // Member Info
            VStack(alignment: .leading, spacing: 4) {
                Text(member.fullName)
                    .font(.headline)
                
                if let address = member.address {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Household indicator
                if member.isHousehold {
                    Label("\(member.householdSize) member household", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
                
                HStack(spacing: 8) {
                    if member.isPaidCurrentYear {
                        Label("Paid \(currentYear)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Unpaid", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if member.yearsUnpaid >= 2 {
                        Text("(\(member.yearsUnpaid)yr overdue)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // Last Payment Info
            if let lastPayment = member.lastPaymentDate {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Last Paid")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(lastPayment.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        if member.isPaidCurrentYear {
            return .green
        } else if member.yearsUnpaid >= 2 {
            return .red
        } else {
            return .orange
        }
    }
}

// MARK: - Address Group Card

struct AddressGroupCard: View {
    let address: String
    let members: [MemberSubscription]
    let onTap: () -> Void

    private var paidCount: Int { members.filter { $0.isPaidCurrentYear }.count }
    private var allPaid: Bool { paidCount == members.count }
    private var nonePaid: Bool { paidCount == 0 }

    private var statusColor: Color {
        if allPaid { return .green }
        else if nonePaid { return .orange }
        else { return Color(red: 0.85, green: 0.60, blue: 0.0) }
    }

    private var statusLabel: String {
        if allPaid { return "All Paid ✓" }
        else if nonePaid { return "Unpaid" }
        else { return "\(paidCount)/\(members.count) Paid" }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Coloured accent bar
                Rectangle()
                    .fill(statusColor)
                    .frame(height: 3)

                HStack(spacing: 12) {
                    // House icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "house.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(address)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        // First-name pills with status dots
                        HStack(spacing: 4) {
                            ForEach(members.prefix(3)) { member in
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(member.isPaidCurrentYear ? Color.green :
                                              (member.yearsUnpaid >= 2 ? Color.red : Color.orange))
                                        .frame(width: 6, height: 6)
                                    Text(member.memberName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            }
                            if members.count > 3 {
                                Text("+\(members.count - 3) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(statusLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statusColor.opacity(0.12))
                            .cornerRadius(8)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Address Group Sheet

struct AddressGroupSheet: View {
    let onUpdate: (MemberSubscription) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var members: [MemberSubscription]
    @State private var selectedMemberForDetail: MemberSubscription?
    private let address: String

    private var paidCount: Int { members.filter { $0.isPaidCurrentYear }.count }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var totalCollected: Double {
        members
            .flatMap { $0.paymentHistory.filter { $0.year == currentYear } }
            .reduce(0) { $0 + $1.amount }
    }

    init(group: AddressGroup, onUpdate: @escaping (MemberSubscription) -> Void) {
        self.address = group.address
        _members = State(initialValue: group.members)
        self.onUpdate = onUpdate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // ── Household summary header ──
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "house.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.blue)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(address)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("\(members.count) resident\(members.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            let outstanding = members.count - paidCount
                            AddressStatPill(
                                value: "\(paidCount)/\(members.count)",
                                label: "Paid \(currentYear)",
                                color: paidCount == members.count ? .green : (paidCount == 0 ? .orange : Color(red: 0.85, green: 0.60, blue: 0.0))
                            )
                            AddressStatPill(
                                value: "R\(String(format: "%.0f", totalCollected))",
                                label: "Collected",
                                color: .blue
                            )
                            AddressStatPill(
                                value: "\(outstanding)",
                                label: "Outstanding",
                                color: outstanding == 0 ? .green : .red
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))

                    Divider()

                    // ── Member cards ──
                    VStack(spacing: 12) {
                        ForEach(members) { member in
                            Button {
                                selectedMemberForDetail = member
                            } label: {
                                MemberSubscriptionCard(member: member)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $selectedMemberForDetail) { member in
                MemberDetailView(member: member, context: .yearly, subscriptions: members) { updatedMember in
                    if let idx = members.firstIndex(where: { $0.id == updatedMember.id }) {
                        members[idx] = updatedMember
                    }
                    onUpdate(updatedMember)
                } onDelete: { deletedMember in
                    members.removeAll { $0.id == deletedMember.id }
                    if members.isEmpty {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AddressStatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Preview

struct SubscriptionTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SubscriptionTrackerView()
        }
    }
}

// MARK: - ActivityView for Export

import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - MailComposeView

import MessageUI

struct MailComposeView: UIViewControllerRepresentable {
    var recipients: [String]
    var subject: String
    var body: String

    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.setBccRecipients(recipients)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}

// MARK: - Confirmation Dialog for Bulk Reminder


extension SubscriptionTrackerView {
        private func openMailAppFallback() {
            // Limit to 5 recipients for mailto: URL
            let maxRecipients = 5
            let recipients = mailRecipients.prefix(maxRecipients).joined(separator: ",")
            let subject = reminderEmailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let body = reminderEmailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let mailtoURLString = "mailto:\(recipients)?subject=\(subject)&body=\(body)"
            if let url = URL(string: mailtoURLString) {
                UIApplication.shared.open(url)
            }
        }
    private func updateLastContactedForRemindedMembers() {
        let now = Date()
        for member in unpaidWithEmail {
            var updated = member
            updatedNotes(&updated, with: "Reminder sent on \(now.formatted(date: .abbreviated, time: .shortened))")
            updated.lastContacted = now
            viewModel.updateMember(updated)
        }
    }

    private func updatedNotes(_ member: inout MemberSubscription, with note: String) {
        if let existing = member.adminNotes, !existing.isEmpty {
            member.adminNotes = existing + "\n" + note
        } else {
            member.adminNotes = note
        }
    }
}

