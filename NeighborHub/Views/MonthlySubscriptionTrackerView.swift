import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

// Note: This view uses types from SubscriptionModels,  SubscriptionTrackerViewModel, and SubscriptionDetailViews

/// Monthly Subscription Tracker - R50 per single user, R99 per household (up to 5 users)
struct MonthlySubscriptionTrackerView: View {
    
    var skipAuthCheck: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SubscriptionTrackerViewModel()
    @State private var searchText: String = ""
    @State private var selectedFilter: MonthlySubscriptionFilter = .all
    @State private var selectedMemberUID: String?
    @State private var showingMemberDetail = false
    @State private var isLoading = false
    
    enum MonthlySubscriptionFilter: String, CaseIterable, Identifiable {
        case all = "All Members"
        case paidThisMonth = "Paid This Month"
        case unpaidThisMonth = "Unpaid This Month"
        case households = "Households (R99)"
        case singles = "Singles (R50)"
        case overdue = "2+ Months Overdue"
        
        var id: String { rawValue }
    }
    
    private var isAuthorized: Bool {
        skipAuthCheck || viewModel.canListSubscriptions()
    }
    
    private var filteredSubscriptions: [MemberSubscription] {
        var filtered = viewModel.subscriptions
        
        // Filter out dependent household members (users who are in another subscription's householdMembers array)
        let allHouseholdMemberUIDs = Set(viewModel.subscriptions.flatMap { $0.householdMembers ?? [] })
        filtered = filtered.filter { subscription in
            // Keep subscription if the memberUID is NOT in any other household's members list
            !allHouseholdMemberUIDs.contains(subscription.memberUID)
        }
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .paidThisMonth:
            filtered = filtered.filter { $0.isPaidCurrentMonth == true }
        case .unpaidThisMonth:
            filtered = filtered.filter { $0.isPaidCurrentMonth != true }
        case .households:
            filtered = filtered.filter { $0.isHousehold }
        case .singles:
            filtered = filtered.filter { !$0.isHousehold }
        case .overdue:
            filtered = filtered.filter { $0.monthsUnpaid >= 2 }
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
    
    private var statistics: (total: Int, households: Int, singles: Int, paidThisMonth: Int, unpaidThisMonth: Int, overdue: Int, monthlyRevenue: Double, outstandingRevenue: Double) {
        // Filter out dependent household members for accurate statistics
        let allHouseholdMemberUIDs = Set(viewModel.subscriptions.flatMap { $0.householdMembers ?? [] })
        let primarySubscriptions = viewModel.subscriptions.filter { subscription in
            !allHouseholdMemberUIDs.contains(subscription.memberUID)
        }
        
        let total = primarySubscriptions.count
        let households = primarySubscriptions.filter { $0.isHousehold }.count
        let singles = primarySubscriptions.filter { !$0.isHousehold }.count
        let paidThisMonth = primarySubscriptions.filter { $0.isPaidCurrentMonth == true }.count
        let unpaidThisMonth = primarySubscriptions.filter { $0.isPaidCurrentMonth != true }.count
        let overdue = primarySubscriptions.filter { $0.monthsUnpaid >= 2 }.count
        
        // Calculate monthly revenue potential
        let monthlyRevenue = primarySubscriptions.reduce(0.0) { $0 + $1.monthlyRate }
        
        // Calculate outstanding (unpaid months × rate)
        let outstandingRevenue = primarySubscriptions.reduce(0.0) { $0 + $1.totalOutstanding }
        
        return (total, households, singles, paidThisMonth, unpaidThisMonth, overdue, monthlyRevenue, outstandingRevenue)
    }
    
    var body: some View {
        Group {
            if !isAuthorized {
                unauthorizedView
            } else {
                authorizedView
            }
        }
        .onAppear {
            viewModel.reloadSubscriptions()
        }
        .sheet(isPresented: $showingMemberDetail) {
            if let memberUID = selectedMemberUID,
               let member = viewModel.subscriptions.first(where: { $0.memberUID == memberUID }) {
                NavigationView {
                    MemberDetailView(member: member, context: .monthly, subscriptions: viewModel.subscriptions) { updatedMember in
                        viewModel.updateMember(updatedMember)
                    } onDelete: { deletedMember in
                        viewModel.deleteMember(deletedMember)
                        selectedMemberUID = nil
                        showingMemberDetail = false
                    }
                }
            }
        }
    }
    
    // MARK: - Authorized View
    
    private var authorizedView: some View {
        VStack(spacing: 0) {
            // Statistics Bar
            statisticsBar
            
            Divider()
            
            // Search Bar
            searchBar
            
            // Filter Pills
            filterPills
            
            Divider()
            
            // Member List
            if filteredSubscriptions.isEmpty {
                emptyStateView
            } else {
                membersList
            }
        }
        .navigationTitle("Monthly Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var statisticsBar: some View {
        VStack(spacing: 8) {
            // Row 1: Member counts
            HStack(spacing: 16) {
                StatBox(title: "Total", value: "\(statistics.total)", color: Color.blue)
                StatBox(title: "Households", value: "\(statistics.households)", color: Color.purple)
                StatBox(title: "Singles", value: "\(statistics.singles)", color: Color.blue)
            }
            
            // Row 2: Revenue and status
            HStack(spacing: 16) {
                StatBox(title: "Monthly Potential", value: "R\(Int(statistics.monthlyRevenue))", color: Color.green)
                StatBox(title: "Outstanding", value: "R\(Int(statistics.outstandingRevenue))", color: Color.orange)
                StatBox(title: "Overdue 2+", value: "\(statistics.overdue)", color: Color.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search by name or address", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MonthlySubscriptionFilter.allCases) { filter in
                    FilterPill(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter,
                        action: { selectedFilter = filter }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private var membersList: some View {
        List {
            ForEach(filteredSubscriptions) { member in
                Button(action: {
                    selectedMemberUID = member.memberUID
                    showingMemberDetail = true
                }) {
                    MonthlyMemberCard(member: member)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteMember(member)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        selectedMemberUID = member.memberUID
                        showingMemberDetail = true
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
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Members Found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if !searchText.isEmpty {
                Text("Try adjusting your search or filter")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Unauthorized View
    
    private var unauthorizedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Access Denied")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("You need admin or committee privileges to view monthly subscriptions.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Views

struct MonthlyMemberCard: View {
    let member: MemberSubscription
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            // Member Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(member.fullName)
                        .font(.headline)
                    
                    // Subscription Type Badge
                    Text(member.effectiveSubscriptionType.displayRate)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(member.isHousehold ? Color.purple : Color.blue)
                        .cornerRadius(8)
                }
                
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
                    if member.isPaidCurrentMonth ?? false {
                        Label("Paid this month", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Unpaid", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        if member.monthsUnpaid > 0 {
                            Text("(\(member.monthsUnpaid)mo · R\(Int(member.totalOutstanding)) due)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Last Payment Info
            if let lastPayment = member.lastMonthPaid ?? member.lastPaymentDate {
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
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        if member.isPaidCurrentMonth ?? false {
            return .green
        } else if member.monthsUnpaid >= 2 {
            return .red
        } else {
            return .orange
        }
    }
}

// MARK: - Preview

struct MonthlySubscriptionTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MonthlySubscriptionTrackerView(skipAuthCheck: true)
        }
    }
}
