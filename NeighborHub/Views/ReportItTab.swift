import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Report It Tab (moved from EventsView Report Issues section)
struct ReportItTab: View {
    // Event data storage
    @AppStorage("eventsData") private var eventsData: String = ""
    @State private var events: [LocalEvent] = []
    
    // UI state
    @State private var reportIssuesExpanded: Bool = true
    @State private var showingAddEvent = false
    @State private var expandedEventID: UUID? = nil
    @State private var editingEvent: LocalEvent? = nil
    
    // Admin check
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("committeeMembers") private var committeeMembers: String = ""
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    private var isAdmin: Bool {
        if userIsAdmin || userIsCommittee {
            return true
        }
        return isAdminByName_Legacy
    }
    
    private var isAdminByName_Legacy: Bool {
        let userFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let userSurnameFull = userSurname.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let members = committeeMembers.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces).capitalized
        }
        
        for member in members {
            let comps = member.split(separator: " ").map {
                String($0).trimmingCharacters(in: .whitespaces).capitalized
            }
            guard let first = comps.first else { continue }
            
            if comps.count > 1 {
                let last = comps.dropFirst().joined(separator: " ")
                if userFirst == first && userSurnameFull == last {
                    return true
                }
            } else if comps.count == 1 {
                if userFirst == first && userSurnameFull.isEmpty {
                    return true
                }
            }
        }
        return false
    }
    
    // Bulk management state
    @State private var isSelectingBulk: Bool = false
    @State private var selectedEventIDs: Set<UUID> = []
    @State private var showBulkActionSheet: Bool = false
    @State private var showBulkDeleteConfirmation: Bool = false
    @State private var showSuccessMessage: Bool = false
    @State private var successMessage: String = ""
    
    // Contact popup state (moved to top level)
    @State private var showContactPopup = false
    @State private var contactPopupEventID: UUID? = nil
    
    // Category contacts from Firestore
    @State private var categoryContacts: [CategoryContact] = []
    
    // Computed property: only report-type events
    private var reportOnlyEvents: [LocalEvent] {
        events.filter { $0.eventType == .report }
            .sorted { $0.date > $1.date }
    }
    
    // Helper: is current user the creator of an event?
    private func isEventCreator(_ event: LocalEvent) -> Bool {
        guard
            let creatorName = event.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines).capitalized,
            let creatorSurname = event.creatorSurname?.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        else { return false }
        let userFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let userSurnameVal = userSurname.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        return creatorName == userFirst && creatorSurname == userSurnameVal
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Statistics Header Card
                    if !reportOnlyEvents.isEmpty {
                        VStack(spacing: 8) {
                            HStack(spacing: 16) {
                                // Total Reports
                                ReportStatCard(
                                    icon: "doc.text.fill",
                                    count: reportOnlyEvents.count,
                                    label: "Total",
                                    color: .blue
                                )
                                
                                // Active Reports (last 7 days)
                                ReportStatCard(
                                    icon: "clock.fill",
                                    count: reportOnlyEvents.filter {
                                        Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear)
                                    }.count,
                                    label: "This Week",
                                    color: .orange
                                )
                                
                                // Selected count (when in bulk mode)
                                if isSelectingBulk && !selectedEventIDs.isEmpty {
                                    ReportStatCard(
                                        icon: "checkmark.circle.fill",
                                        count: selectedEventIDs.count,
                                        label: "Selected",
                                        color: .green
                                    )
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        }
                        .background(
                            LinearGradient(
                                colors: [Color(.systemBackground), Color(.systemGray6).opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                    }
                    
                    // Reports List
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                if !reportOnlyEvents.isEmpty {
                                    ForEach(Array(reportOnlyEvents.enumerated()), id: \.element.id) {
                                        offset, event in
                                    let eventBinding = Binding<LocalEvent>(
                                        get: { event },
                                        set: { updated in
                                            if let realIdx = events.firstIndex(where: {
                                                $0.id == updated.id
                                            }) {
                                                events[realIdx] = updated
                                                saveEvents()
                                            }
                                        }
                                    )
                                    let isExpanded = Binding<Bool>(
                                        get: { expandedEventID == event.id },
                                        set: { newValue in
                                            let wasExpanded = expandedEventID == event.id
                                            expandedEventID = newValue ? event.id : nil
                                            
                                            if newValue {
                                                // Scroll to card when expanded with a slight delay
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    withAnimation(.easeInOut(duration: 0.4)) {
                                                        scrollProxy.scrollTo(event.id, anchor: .top)
                                                    }
                                                }
                                            } else if wasExpanded {
                                                // Card was closed, scroll back to first card
                                                if let firstCard = reportOnlyEvents.first {
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                        withAnimation(.easeInOut(duration: 0.4)) {
                                                            scrollProxy.scrollTo(firstCard.id, anchor: .top)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    )
                                    
                                    // Check if this card is the active one (expanded or showing contact popup)
                                    let isActiveCard = (expandedEventID == event.id) || (showContactPopup && contactPopupEventID == event.id)
                                    
                                    // Determine which event is currently active (prioritize contact popup, then expanded)
                                    let activeEventID: UUID? = {
                                        if showContactPopup, let popupID = contactPopupEventID {
                                            return popupID
                                        }
                                        return expandedEventID
                                    }()
                                    
                                    // Check if this card should be pushed down
                                    let shouldPushDown: Bool = {
                                        guard let activeID = activeEventID else { return false }
                                        guard activeID != event.id else { return false } // Active card itself doesn't push down
                                        
                                        // Find offset of the active card
                                        guard let activeOffset = reportOnlyEvents.firstIndex(where: { $0.id == activeID }) else { return false }
                                        
                                        // Push down if this card is below the active one
                                        return offset > activeOffset
                                    }()
                                    
                                    // Calculate push down amount based on what's shown
                                    let pushDownAmount: CGFloat = {
                                        if !shouldPushDown { return 0 }
                                        
                                        // Check what type of content is showing on the active card
                                        if let activeID = activeEventID {
                                            // If the active card is showing contact popup, need more space
                                            if showContactPopup && contactPopupEventID == activeID {
                                                return 280
                                            }
                                            // If the active card is just expanded, need less space
                                            if expandedEventID == activeID {
                                                return 180
                                            }
                                        }
                                        return 0
                                    }()
                                    
                                    ModernReportCard(
                                        event: eventBinding,
                                        isSelected: selectedEventIDs.contains(event.id),
                                        isSelecting: isSelectingBulk,
                                        isExpanded: isExpanded,
                                        canEdit: isAdmin || isEventCreator(event),
                                        showContactPopup: Binding(
                                            get: { showContactPopup && contactPopupEventID == event.id },
                                            set: { newValue in
                                                let wasShowingPopup = showContactPopup && contactPopupEventID == event.id
                                                showContactPopup = newValue
                                                contactPopupEventID = newValue ? event.id : nil
                                                
                                                if newValue {
                                                    // Scroll to card when contact popup opens with a slight delay
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                        withAnimation(.easeInOut(duration: 0.4)) {
                                                            scrollProxy.scrollTo(event.id, anchor: .top)
                                                        }
                                                    }
                                                } else if wasShowingPopup {
                                                    // Contact popup was closed, scroll back to first card
                                                    if let firstCard = reportOnlyEvents.first {
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                            withAnimation(.easeInOut(duration: 0.4)) {
                                                                scrollProxy.scrollTo(firstCard.id, anchor: .top)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        ),
                                        categoryContacts: $categoryContacts,
                                        onToggleSelection: {
                                            if selectedEventIDs.contains(event.id) {
                                                selectedEventIDs.remove(event.id)
                                            } else {
                                                selectedEventIDs.insert(event.id)
                                            }
                                        },
                                        onEdit: {
                                            editingEvent = event
                                        },
                                        onDelete: {
                                            if let realIdx = events.firstIndex(where: {
                                                $0.id == event.id
                                            }) {
                                                let removed = events.remove(at: realIdx)
                                                saveEvents()
                                                FirebaseManager.shared.deleteEvent(
                                                    id: removed.id.uuidString
                                                ) { err in
                                                    if let err = err {
                                                        #if DEBUG
                                                            print(
                                                                "Failed to delete event in Firebase: \(err)"
                                                            )
                                                        #endif
                                                    }
                                                }
                                            }
                                        },
                                        onUpdate: { updatedEvent in
                                            if let realIdx = events.firstIndex(where: {
                                                $0.id == updatedEvent.id
                                            }) {
                                                events[realIdx] = updatedEvent
                                                saveEvents()
                                                
                                                // Push update to Firestore so all users see the change
                                                FirebaseManager.shared.createOrUpdateEvent(updatedEvent) { error in
                                                    if let error = error {
                                                        print("Error syncing resolved status to Firestore: \(error)")
                                                    }
                                                }
                                            }
                                        }
                                    )
                                    .id(event.id)
                                    .padding(.top, pushDownAmount)
                                    .zIndex(isActiveCard ? 10000 : Double(reportOnlyEvents.count - offset))
                                    .scaleEffect(isActiveCard ? 1.02 : 1.0)
                                    .shadow(color: isActiveCard ? Color.black.opacity(0.2) : Color.black.opacity(0.05), radius: isActiveCard ? 16 : 4, x: 0, y: isActiveCard ? 8 : 2)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isActiveCard)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: pushDownAmount)
                                }
                            } else {
                                // Modern Empty State
                                VStack(spacing: 24) {
                                    Spacer()
                                    
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.05)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 120, height: 120)
                                        
                                        Image(systemName: "checkmark.shield.fill")
                                            .font(.system(size: 50))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [Color.orange, Color.orange.opacity(0.7)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                    
                                    VStack(spacing: 8) {
                                        Text("No Issues Reported")
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(.primary)
                                        
                                        Text("Your neighborhood is looking good!")
                                            .font(.system(size: 16))
                                            .foregroundColor(.secondary)
                                        
                                        Text("Report issues to help keep the community safe and well-maintained")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 32)
                                            .padding(.top, 4)
                                    }
                                    
                                    Button(action: { showingAddEvent = true }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 18))
                                            Text("Report an Issue")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 28)
                                        .padding(.vertical, 14)
                                        .background(
                                            LinearGradient(
                                                colors: [Color.orange, Color.orange.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .cornerRadius(12)
                                        .shadow(color: Color.orange.opacity(0.3), radius: 12, x: 0, y: 6)
                                    }
                                    .padding(.top, 8)
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 500)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, reportOnlyEvents.isEmpty ? 0 : 16)
                        .padding(.bottom, {
                            // Dynamic bottom padding to ensure last card can scroll to top
                            if showContactPopup && contactPopupEventID != nil {
                                return 600 // Extra space when contact popup is open
                            } else if expandedEventID != nil {
                                return 500 // Extra space when card is expanded
                            }
                            return 300 // Default spacing for normal state
                        }())
                    }
                    }
                }
            }
            .navigationTitle("Report It")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isAdmin {
                        Button(action: {
                            if isSelectingBulk {
                                // Exit bulk mode
                                isSelectingBulk = false
                                selectedEventIDs.removeAll()
                            } else {
                                // Enter bulk mode
                                isSelectingBulk = true
                            }
                        }) {
                            Text(isSelectingBulk ? "Done" : "Select")
                                .font(.body)
                                .foregroundColor(isSelectingBulk ? .orange : .accentColor)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Bulk actions button (only show when selecting)
                        if isSelectingBulk && !selectedEventIDs.isEmpty {
                            Button(action: {
                                showBulkActionSheet = true
                            }) {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(Color.orange))
                                    .shadow(
                                        color: Color.orange.opacity(0.25), radius: 8, x: 0, y: 4
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("Bulk Actions")
                        }
                        // Add issue button
                        Button(action: { showingAddEvent = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.orange))
                                .shadow(
                                    color: Color.orange.opacity(0.25), radius: 8, x: 0,
                                    y: 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Report Issue")
                    }
                }
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventView(onAdd: { newEvent in
                    // Attach creator info
                    var eventWithCreator = newEvent
                    eventWithCreator.creatorName = userName
                    eventWithCreator.creatorSurname = userSurname
                    eventWithCreator.creatorUID = UserDefaults.standard.string(forKey: "userUID")
                    // Optimistic UI: append locally first
                    events.append(eventWithCreator)
                    saveEvents()
                    // Persist to Firestore / Storage
                    FirebaseManager.shared.createOrUpdateEvent(eventWithCreator) { err in
                        if let err = err {
                            #if DEBUG
                                print("Failed to create event in Firebase: \(err)")
                            #endif
                        }
                    }
                    // Send notification
                    sendReportIssueNotification(for: eventWithCreator)
                }, allowedEventTypes: [.report])
            }
            // Edit event sheet
            .sheet(item: $editingEvent) { eventToEdit in
                AddEventView(
                    event: eventToEdit,
                    onSave: { updatedEvent in
                        if let idx = events.firstIndex(where: { $0.id == updatedEvent.id }) {
                            // Preserve creator info
                            var updated = updatedEvent
                            updated.creatorName = events[idx].creatorName
                            updated.creatorSurname = events[idx].creatorSurname
                            events[idx] = updated
                            saveEvents()
                            // Persist updates to Firestore / Storage
                            FirebaseManager.shared.createOrUpdateEvent(updated) { err in
                                if let err = err {
                                    #if DEBUG
                                        print("Failed to update event in Firebase: \(err)")
                                    #endif
                                }
                            }
                        }
                        editingEvent = nil
                    },
                    onCancel: { editingEvent = nil }
                )
            }
            .onAppear {
                // Track screen view
                AnalyticsService.shared.trackScreenView("ReportIt")
                
                // Load local cache first
                loadEvents()
                
                // Start live updates from Firestore (will override local cache)
                FirebaseManager.shared.watchEvents { fetched in
                    DispatchQueue.main.async {
                        // Always trust Firestore updates for proper sync (including deletions)
                        // Only ignore the first empty snapshot if we just loaded from cache
                        // and haven't received any Firestore updates yet
                        let isInitialLoad = self.events.isEmpty
                        
                        if fetched.isEmpty && !self.events.isEmpty && isInitialLoad {
                            #if DEBUG
                                print(
                                    "[ReportItTab] Initial Firestore snapshot empty; keeping local cache of \(self.events.count) events temporarily."
                                )
                            #endif
                            // Don't return - this should rarely happen, and we'll get another update
                        }
                        
                        // Update local state to match Firestore (this syncs deletions across users)
                        self.events = fetched
                        saveEvents()
                        
                        #if DEBUG
                            print("[ReportItTab] Synced \(fetched.count) events from Firestore")
                        #endif
                    }
                }
                
                // Watch category contacts from Firestore
                FirebaseManager.shared.watchCategoryContacts { contacts in
                    DispatchQueue.main.async {
                        self.categoryContacts = contacts
                    }
                }
                
                // Request notification permission
                UNUserNotificationCenter.current().requestAuthorization(options: [
                    .alert, .sound, .badge,
                ]) { granted, error in
                    // Handle permission if needed
                }
            }
            .onDisappear {
                FirebaseManager.shared.stopWatchingEvents()
            }
            // Enhanced bulk action dialog
            .confirmationDialog(
                "Bulk Actions",
                isPresented: $showBulkActionSheet,
                titleVisibility: .visible
            ) {
                Button("🗂️ Archive Selected (\(selectedEventIDs.count))") {
                    performBulkArchive()
                }
                
                Button("🗑️ Delete Selected (\(selectedEventIDs.count))", role: .destructive) {
                    showBulkDeleteConfirmation = true
                }
                
                Button("Cancel", role: .cancel) {
                    // Keep selection for further actions
                }
            } message: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Choose an action for \(selectedEventIDs.count) selected incident report\(selectedEventIDs.count == 1 ? "" : "s"):"
                    )
                    .font(.body)
                    
                    Text("• Archive: Move to archived section (can be restored)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• Delete: Permanently remove (cannot be undone)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            // Enhanced delete confirmation dialog
            .alert("⚠️ Confirm Bulk Delete", isPresented: $showBulkDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    // Keep selection active
                }
                Button(
                    "Delete \(selectedEventIDs.count) Report\(selectedEventIDs.count == 1 ? "" : "s")",
                    role: .destructive
                ) {
                    performBulkDelete()
                }
            } message: {
                Text(
                    "This will permanently delete \(selectedEventIDs.count) incident report\(selectedEventIDs.count == 1 ? "" : "s"). This action cannot be undone.\n\nConsider using Archive instead to preserve the reports for future reference."
                )
            }
            // Success feedback alert
            .alert(successMessage, isPresented: $showSuccessMessage) {
                Button("OK") {}
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func sendReportIssueNotification(for event: LocalEvent) {
        let content = UNMutableNotificationContent()
        content.title = "New Issue Reported"
        content.body = "A new issue was reported: \(event.title)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "report-issue-\(event.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    private func performBulkDelete() {
        let eventsToDelete = events.filter { selectedEventIDs.contains($0.id) }
        let count = eventsToDelete.count
        
        // Delete locally first for responsive UI
        for event in eventsToDelete {
            deleteEventAndAttachments(event)
        }
        
        // Delete from Firebase in background
        for event in eventsToDelete {
            FirebaseManager.shared.deleteEvent(id: event.id.uuidString) { err in
                if let err = err {
                    #if DEBUG
                        print("Failed to delete event \(event.id) in Firebase: \(err)")
                    #endif
                }
            }
        }
        
        // Clear selection and exit bulk mode
        selectedEventIDs.removeAll()
        isSelectingBulk = false
        
        // Show success message
        successMessage = "✅ Successfully deleted \(count) incident report\(count == 1 ? "" : "s")"
        showSuccessMessage = true
    }
    
    private func performBulkArchive() {
        let eventsToArchive = events.filter { selectedEventIDs.contains($0.id) }
        let count = eventsToArchive.count
        
        // Archive to Firebase (move to archived collection)
        for event in eventsToArchive {
            FirebaseManager.shared.archiveIncident(event) { err in
                if let err = err {
                    #if DEBUG
                        print("Failed to archive event \(event.id) in Firebase: \(err)")
                    #endif
                }
            }
        }
        
        // Remove from local events array
        events.removeAll { selectedEventIDs.contains($0.id) }
        saveEvents()
        
        // Clear selection and exit bulk mode
        selectedEventIDs.removeAll()
        isSelectingBulk = false
        
        // Show success message
        successMessage = "🗂️ Successfully archived \(count) incident report\(count == 1 ? "" : "s")"
        showSuccessMessage = true
    }
    
    private func deleteEventAndAttachments(_ event: LocalEvent) {
        // Remove stored attachment files if present
        let fileManager = FileManager.default
        if let url = event.fileURL {
            // Only delete files that are inside our Documents/Attachments folder for safety
            if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let attachmentsDir = docs.appendingPathComponent("Attachments", isDirectory: true)
                if url.path.hasPrefix(attachmentsDir.path) {
                    do {
                        if fileManager.fileExists(atPath: url.path) {
                            try fileManager.removeItem(at: url)
                        }
                    } catch {
                        #if DEBUG
                            print("Failed to delete attachment at \(url): \(error)")
                        #endif
                    }
                }
            }
        }
        // Remove event from the events array
        events.removeAll { $0.id == event.id }
        saveEvents()
    }
    
    // MARK: - Persistence
    private func saveEvents() {
        // Strip large binary data (images/files) before saving to AppStorage/UserDefaults
        let sanitized = events.map { ev -> LocalEvent in
            var copy = ev
            copy.imageData = nil
            return copy
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            eventsData = String(data: data, encoding: .utf8) ?? ""
        }
    }
    
    private func loadEvents() {
        guard let data = eventsData.data(using: .utf8), !eventsData.isEmpty else { return }
        if let decoded = try? JSONDecoder().decode([LocalEvent].self, from: data) {
            events = decoded
        }
    }
}

// MARK: - View Extension for Conditional Modifiers
extension View {
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Modern UI Components

/// Statistics Card Component
struct ReportStatCard: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.15), color.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .shadow(color: color.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }
}

/// Modern Report Card Component
struct ModernReportCard: View {
    @Binding var event: LocalEvent
    let isSelected: Bool
    let isSelecting: Bool
    @Binding var isExpanded: Bool
    let canEdit: Bool
    @Binding var showContactPopup: Bool
    @Binding var categoryContacts: [CategoryContact]
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onUpdate: (LocalEvent) -> Void
    
    @State private var showDeleteAlert = false
    @State private var showCategoryContactEdit = false
    
    // Admin status
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    private var eventTypeColor: Color {
        // Use metadata category for color, fallback to pink for reports
        guard let category = event.metadata?["category"] else {
            return .pink
        }
        switch category {
        case "Safety": return .red
        case "Infrastructure": return .blue
        case "Environment": return .green
        case "Community": return .orange
        case "Electricity": return .yellow
        case "Water": return .cyan
        default: return .pink
        }
    }
    
    private var cardGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                eventTypeColor.opacity(0.18),
                Color(.systemBackground).opacity(0.92),
                eventTypeColor.opacity(0.14),
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var categoryName: String {
        event.metadata?["category"] ?? "General"
    }
    
    private var priorityLevel: String {
        // Determine priority based on category
        guard let category = event.metadata?["category"] else {
            return "Medium"
        }
        switch category {
        case "Safety": return "High"
        case "Infrastructure": return "Medium"
        default: return "Low"
        }
    }
    
    private var priorityColor: Color {
        switch priorityLevel {
        case "High": return .red
        case "Medium": return .orange
        default: return .blue
        }
    }
    
    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.25)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(alignment: .top, spacing: 10) {
                    // Selection checkbox (when in bulk mode)
                    if isSelecting {
                        Button(action: onToggleSelection) {
                            Image(
                                systemName: isSelected
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.system(size: 24))
                            .foregroundColor(isSelected ? eventTypeColor : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Main icon with glassmorphic effect (matching EventsView)
                    ZStack {
                        Circle()
                            .foregroundColor(.clear)
                            .frame(width: 46, height: 46)
                            .background(
                                BlurView(style: .systemUltraThinMaterial)
                                    .clipShape(Circle())
                            )
                            .overlay(
                                Circle()
                                    .stroke(eventTypeColor.opacity(0.18), lineWidth: 2)
                            )
                        Image(systemName: categoryIcon)
                            .foregroundColor(eventTypeColor)
                            .font(.title2)
                    }
                    
                    // Title and metadata (matching EventsView layout)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.eventType.rawValue)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(eventTypeColor)
                        Text(event.title)
                            .fontWeight(.bold)
                            .font(.headline)
                            .lineLimit(2)
                        // Category name in bold
                        Text(categoryName)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(eventTypeColor.opacity(0.8))
                        if let location = event.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                Text(location)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    
                    // Action menu (when not selecting) and expand arrow
                    HStack(spacing: 8) {
                        if !isSelecting && canEdit {
                            Menu {
                                // Mark as Resolved option (admin only)
                                if (userIsAdmin || userIsCommittee) && !event.isResolved {
                                    Button(action: {
                                        var updatedEvent = event
                                        updatedEvent.isResolved = true
                                        updatedEvent.resolvedAt = Date()
                                        updatedEvent.resolvedBy = FirebaseManager.shared.getCurrentUserUID() ?? ""
                                        onUpdate(updatedEvent)
                                    }) {
                                        Label("Mark as Resolved", systemImage: "checkmark.seal.fill")
                                    }
                                }
                                
                                // Reopen option (admin only)
                                if (userIsAdmin || userIsCommittee) && event.isResolved {
                                    Button(action: {
                                        var updatedEvent = event
                                        updatedEvent.isResolved = false
                                        updatedEvent.resolvedAt = nil
                                        updatedEvent.resolvedBy = nil
                                        onUpdate(updatedEvent)
                                    }) {
                                        Label("Reopen Issue", systemImage: "arrow.counterclockwise")
                                    }
                                }
                                
                                Divider()
                                
                                Button(action: onEdit) {
                                    Label("Edit Report", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive, action: {
                                    showDeleteAlert = true
                                }) {
                                    Label("Delete Report", systemImage: "trash")
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .foregroundColor(.clear)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            BlurView(style: .systemThinMaterial)
                                                .clipShape(Circle())
                                        )
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Expand/collapse chevron (matching EventsView)
                        ZStack {
                            Circle()
                                .foregroundColor(.clear)
                                .frame(width: 28, height: 28)
                                .background(
                                    BlurView(style: .systemThinMaterial)
                                        .clipShape(Circle())
                                )
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(.accentColor)
                                .font(.headline)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardGradient)
                    .background(
                        BlurView(style: .systemUltraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    )
                    .shadow(color: eventTypeColor.opacity(0.13), radius: 10, x: 0, y: 4)
                    .shadow(color: Color.primary.opacity(0.06), radius: 2, x: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        eventTypeColor.opacity(0.22), .clear,
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
            )
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .overlay(
                // Floating Contact Button (for all categories)
                Group {
                    if !categoryName.isEmpty && categoryName != "General" {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        showContactPopup = true
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: categoryContactIcon)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Contact")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [eventTypeColor, eventTypeColor.opacity(0.8)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .shadow(color: eventTypeColor.opacity(0.4), radius: 8, x: 0, y: 4)
                                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .scaleEffect(showContactPopup ? 0.95 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showContactPopup)
                                .padding(.trailing, 16)
                                .padding(.top, 75)
                            }
                            Spacer()
                        }
                    }
                }
            )
            
            // Expanded content (matching EventsView style)
            if isExpanded {
                // Spacer to push content below floating contact button
                if !categoryName.isEmpty && categoryName != "General" {
                    Spacer()
                        .frame(height: 20)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    if let imageData = event.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .cornerRadius(12)
                            .padding(.top, 2)
                    }
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                            .padding(.leading, 4)
                    }
                    
                    // File attachment preview
                    if let fileURL = event.fileURL {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.accentColor)
                            Text(fileURL.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: {
                                UIApplication.shared.open(fileURL)
                            }) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 4)
                        .padding(.leading, 4)
                    }

                    // Contact details
                    if let contactName = event.contactName, !contactName.isEmpty,
                        let contactCell = event.contactCell, !contactCell.isEmpty
                    {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Contact: \(contactName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                            HStack {
                                Text("Phone: ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Menu {
                                    Button(action: {
                                        if let url = URL(string: "tel:\(contactCell)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Label("Call \(contactCell)", systemImage: "phone.fill")
                                    }
                                    Button(action: {
                                        var waNumber = contactCell.filter { $0.isNumber }
                                        if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                            waNumber = "27" + waNumber.dropFirst()
                                        }
                                        // Pre-fill WhatsApp message with incident details
                                        let userName = UserDefaults.standard.string(forKey: "userName") ?? "User"
                                        let userSurname = UserDefaults.standard.string(forKey: "userSurname") ?? ""
                                        let userAddress = UserDefaults.standard.string(forKey: "userStreet") ?? ""
                                        let userCell = UserDefaults.standard.string(forKey: "userCellNumber") ?? ""
                                        
                                        var message = "Hi, I'm contacting you regarding an incident/report.%0A%0A"
                                        message += "*Issue:* \(event.title)%0A"
                                        if let desc = event.description, !desc.isEmpty {
                                            let cleanDesc = desc.replacingOccurrences(of: "%", with: "").prefix(100)
                                            message += "*Details:* \(cleanDesc)%0A"
                                        }
                                        message += "%0A*Reported by:*%0A"
                                        message += "Name: \(userName) \(userSurname)%0A"
                                        if !userAddress.isEmpty {
                                            message += "Address: \(userAddress)%0A"
                                        }
                                        if !userCell.isEmpty {
                                            message += "Contact: \(userCell)%0A"
                                        }
                                        message += "%0APlease assist. Thank you."
                                        
                                        if let url = URL(string: "https://wa.me/\(waNumber)?text=\(message)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Label(
                                            "WhatsApp with Pre-filled Report",
                                            systemImage: "message.circle.fill")
                                    }
                                    Divider()
                                    Button(action: {
                                        UIPasteboard.general.string = contactCell
                                    }) {
                                        Label("Copy Number", systemImage: "doc.on.doc")
                                    }
                                } label: {
                                    Text(contactCell)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .underline()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .menuStyle(.borderlessButton)
                                .menuOrder(.priority)
                            }
                            .padding(.leading, 4)
                        }
                    } else if let contactName = event.contactName, !contactName.isEmpty {
                        Text("Contact: \(contactName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                            .padding(.leading, 4)
                    }

                    HStack(spacing: 8) {
                        // Priority Badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(priorityColor)
                                .frame(width: 6, height: 6)
                            Text(priorityLevel)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(priorityColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(priorityColor.opacity(0.12))
                        .cornerRadius(6)
                        .padding(.leading, 10)
                        
                        Text(event.date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.primary)
                        Text(event.date, style: .time)
                            .font(.caption2)
                            .foregroundColor(.primary)
                        Spacer()
                        // Share button with extra right padding
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                    }
                    
                    // Messages/Chat Section
                    IncidentMessagesView(
                        event: $event,
                        canMessage: true,  // Allow all users to send messages
                        onUpdate: onUpdate
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.85))
                        .background(
                            BlurView(style: .systemUltraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        )
                )
                .cornerRadius(20)
                .padding(.horizontal, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .contentShape(Rectangle())
            }
        }
        .zIndex(1)
        
        // RESOLVED Stamp Overlay (on top of everything)
        if event.isResolved {
            GeometryReader { geometry in
                ZStack {
                    // Stamp effect positioned in center
                    Text("RESOLVED")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.green.opacity(0.55))
                        .rotationEffect(.degrees(-20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.green.opacity(0.55), lineWidth: 5)
                                .frame(width: 200, height: 70)
                                .rotationEffect(.degrees(-20))
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(2)
            .zIndex(10)
        }
        }
        // Contact popup overlay (inline with card)
        .overlay(alignment: .topTrailing) {
            if showContactPopup && !categoryName.isEmpty && categoryName != "General" {
                VStack(spacing: 0) {
                    // Arrow pointer connecting to button
                    HStack {
                        Spacer()
                        Triangle()
                            .fill(
                                LinearGradient(
                                    colors: [eventTypeColor.opacity(0.3), Color(.systemBackground)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 20, height: 12)
                            .shadow(color: eventTypeColor.opacity(0.3), radius: 4, x: 0, y: -2)
                            .padding(.trailing, 32)
                    }
                    
                    // Main popup card
                    VStack(alignment: .leading, spacing: 0) {
                        // Header with close button and glow effect
                        ZStack {
                            // Glow background
                            LinearGradient(
                                colors: [eventTypeColor.opacity(0.15), eventTypeColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Contact Information")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    Text(categoryName)
                                        .font(.caption)
                                        .foregroundColor(eventTypeColor)
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        showContactPopup = false
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(.systemGray6))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding()
                        }
                        .frame(height: 60)
                        
                        Divider()
                            .overlay(eventTypeColor.opacity(0.2))
                        
                        // Contact Card Content
                        CategoryContactCard(
                            category: categoryName,
                            contactName: categoryContactName,
                            contactNumber: categoryContactNumber,
                            isAdmin: userIsAdmin || userIsCommittee,
                            onEdit: {
                                showCategoryContactEdit = true
                            }
                        )
                        .padding(.bottom, 16)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(.systemBackground),
                                        Color(.systemBackground).opacity(0.98)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        eventTypeColor.opacity(0.6),
                                        eventTypeColor.opacity(0.2),
                                        eventTypeColor.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: eventTypeColor.opacity(0.25), radius: 20, x: 0, y: -8)
                    .shadow(color: eventTypeColor.opacity(0.15), radius: 40, x: 0, y: 10)
                    .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                }
                .frame(width: UIScreen.main.bounds.width * 0.85)
                .padding(.trailing, 20)
                .padding(.top, 70)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.7, anchor: .topTrailing)
                        .combined(with: .opacity)
                        .combined(with: .move(edge: .top)),
                    removal: .scale(scale: 0.8, anchor: .topTrailing)
                        .combined(with: .opacity)
                ))
                .zIndex(20000)
            }
        }
        .alert("Delete Report", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete this report? This action cannot be undone.")
        }
        .sheet(isPresented: $showCategoryContactEdit) {
            CategoryContactEditView(
                category: categoryName,
                contactName: bindingForContactName(categoryName),
                contactNumber: bindingForContactNumber(categoryName)
            )
        }
    }
    
    // Helper computed properties for category contacts
    private var categoryContactIcon: String {
        switch categoryName {
        case "Electricity": return "bolt.fill"
        case "Water": return "drop.fill"
        case "Lighting": return "lightbulb.fill"
        case "Safety": return "shield.fill"
        case "Infrastructure": return "wrench.and.screwdriver.fill"
        case "Environment": return "leaf.fill"
        case "Community": return "person.3.fill"
        default: return "phone.fill"
        }
    }
    
    private var categoryContactName: String {
        categoryContacts.first(where: { $0.id == categoryName })?.name ?? ""
    }
    
    private var categoryContactNumber: String {
        categoryContacts.first(where: { $0.id == categoryName })?.number ?? ""
    }
    
    private func bindingForContactName(_ category: String) -> Binding<String> {
        Binding(
            get: {
                categoryContacts.first(where: { $0.id == category })?.name ?? ""
            },
            set: { newValue in
                if let index = categoryContacts.firstIndex(where: { $0.id == category }) {
                    categoryContacts[index].name = newValue
                }
            }
        )
    }
    
    private func bindingForContactNumber(_ category: String) -> Binding<String> {
        Binding(
            get: {
                categoryContacts.first(where: { $0.id == category })?.number ?? ""
            },
            set: { newValue in
                if let index = categoryContacts.firstIndex(where: { $0.id == category }) {
                    categoryContacts[index].number = newValue
                }
            }
        )
    }
    
    // Share text for the report
    private var shareText: String {
        var text = "NeighborHub Report: \(event.title)\n"
        if let desc = event.description, !desc.isEmpty {
            text += "\n\(desc)\n"
        }
        if let loc = event.location, !loc.isEmpty {
            text += "\nLocation: \(loc)\n"
        }
        text += "\nDate: \(event.date.formatted(date: .abbreviated, time: .shortened))"
        text += "\nCategory: \(categoryName)"
        return text
    }
    
    private var categoryIcon: String {
        guard let category = event.metadata?["category"] else {
            return "exclamationmark.triangle.fill"
        }
        switch category {
        case "Safety": return "shield.fill"
        case "Infrastructure": return "wrench.and.screwdriver.fill"
        case "Environment": return "leaf.fill"
        case "Community": return "person.3.fill"
        case "Electricity": return "bolt.fill"
        case "Water": return "drop.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Incident Messages View
struct IncidentMessagesView: View {
    @Binding var event: LocalEvent
    let canMessage: Bool
    let onUpdate: (LocalEvent) -> Void
    
    @State private var newMessage: String = ""
    @State private var isKeyboardVisible = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var editingMessage: IncidentMessage?
    @State private var showEditSheet = false
    @State private var editedText: String = ""
    @State private var messageListener: ListenerRegistration?
    
    @AppStorage("userUID") private var userUID: String = ""
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    private var currentUserUID: String {
        // Use Firebase Auth UID for reliable matching
        FirebaseManager.shared.getCurrentUserUID() ?? userUID
    }
    
    private var currentUserName: String {
        "\(userName) \(userSurname)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var isAdmin: Bool {
        userIsAdmin || userIsCommittee
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.blue)
                Text("Messages")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !event.messages.isEmpty {
                    Text("\(event.messages.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Messages list
            if !event.messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(event.messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
                                MessageBubble(
                                    message: message,
                                    isCurrentUser: message.senderUID == currentUserUID,
                                    isAdmin: isAdmin,
                                    onEdit: {
                                        editMessage(message)
                                    },
                                    onDelete: {
                                        deleteMessage(message)
                                    }
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxHeight: 200)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
                    .onAppear {
                        scrollProxy = proxy
                        scrollToLastMessage(proxy: proxy)
                        startListeningForMessages()
                    }
                    .onDisappear {
                        stopListeningForMessages()
                    }
                    .onChange(of: event.messages.count) { oldValue, newValue in
                        scrollToLastMessage(proxy: proxy)
                    }
                }
            } else {
                Text("No messages yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
            }
            
            // Message input (only if user can message)
            if canMessage {
                Divider()
                    .padding(.horizontal, 12)
                
                HStack(spacing: 8) {
                    TextField("Type a message...", text: $newMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                    }
                    .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(12)
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationView {
                VStack {
                    TextEditor(text: $editedText)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .padding()
                }
                .navigationTitle("Edit Message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showEditSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveEditedMessage()
                        }
                        .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
    
    // MARK: - Real-time Message Listener
    
    private func startListeningForMessages() {
        let db = Firestore.firestore()
        let ref = db.collection("events").document(event.id.uuidString)
        
        messageListener = ref.addSnapshotListener { snapshot, error in
            guard let data = snapshot?.data(),
                  let messagesArray = data["messages"] as? [[String: Any]] else {
                return
            }
            
            var updatedMessages: [IncidentMessage] = []
            for msgDict in messagesArray {
                if let id = msgDict["id"] as? String,
                   let senderUID = msgDict["senderUID"] as? String,
                   let senderName = msgDict["senderName"] as? String,
                   let messageText = msgDict["message"] as? String,
                   let timestamp = msgDict["timestamp"] as? Timestamp,
                   let isAdmin = msgDict["isAdmin"] as? Bool {
                    let msg = IncidentMessage(
                        id: UUID(uuidString: id) ?? UUID(),
                        senderUID: senderUID,
                        senderName: senderName,
                        message: messageText,
                        timestamp: timestamp.dateValue(),
                        isAdmin: isAdmin
                    )
                    updatedMessages.append(msg)
                }
            }
            
            // Only update if messages actually changed
            if updatedMessages.count != event.messages.count ||
               updatedMessages.map({ $0.id }) != event.messages.map({ $0.id }) {
                print("🔄 Real-time update: Messages changed from \(event.messages.count) to \(updatedMessages.count)")
                var updatedEvent = event
                updatedEvent.messages = updatedMessages.sorted { $0.timestamp < $1.timestamp }
                event = updatedEvent
                onUpdate(updatedEvent)
            }
        }
    }
    
    private func stopListeningForMessages() {
        messageListener?.remove()
        messageListener = nil
    }
    
    private func sendMessage() {
        print("🔵 sendMessage() called")
        let trimmedMessage = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            print("❌ Message is empty after trimming")
            return
        }
        
        print("📝 Creating message - UID: \(currentUserUID), Name: \(currentUserName)")
        
        let message = IncidentMessage(
            senderUID: currentUserUID,
            senderName: currentUserName.isEmpty ? "User" : currentUserName,
            message: trimmedMessage,
            isAdmin: isAdmin
        )
        
        // Add message to local event and sort by timestamp
        var updatedEvent = event
        updatedEvent.messages.append(message)
        updatedEvent.messages.sort { $0.timestamp < $1.timestamp }
        
        // Update local state immediately
        self.event = updatedEvent
        self.onUpdate(updatedEvent)
        self.newMessage = ""
        
        // Save only messages to Firestore
        let db = Firestore.firestore()
        let ref = db.collection("events").document(event.id.uuidString)
        
        // Convert messages to dict format
        var messagesArray: [[String: Any]] = []
        for msg in updatedEvent.messages {
            messagesArray.append([
                "id": msg.id.uuidString,
                "senderUID": msg.senderUID,
                "senderName": msg.senderName,
                "message": msg.message,
                "timestamp": Timestamp(date: msg.timestamp),
                "isAdmin": msg.isAdmin
            ])
        }
        
        // Update only the messages field
        ref.updateData(["messages": messagesArray]) { error in
            if let error = error {
                print("❌ Error saving message: \(error)")
            } else {
                print("✅ Message saved successfully")
                
                // Scroll to new message
                DispatchQueue.main.async {
                    if let proxy = self.scrollProxy {
                        self.scrollToLastMessage(proxy: proxy)
                    }
                }
            }
        }
    }
    
    private func scrollToLastMessage(proxy: ScrollViewProxy) {
        if let lastMessage = event.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func editMessage(_ message: IncidentMessage) {
        editingMessage = message
        editedText = message.message
        showEditSheet = true
    }
    
    private func saveEditedMessage() {
        guard let editingMessage = editingMessage,
              !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // Update the message in local event
        var updatedEvent = event
        if let index = updatedEvent.messages.firstIndex(where: { $0.id == editingMessage.id }) {
            updatedEvent.messages[index] = IncidentMessage(
                id: editingMessage.id,
                senderUID: editingMessage.senderUID,
                senderName: editingMessage.senderName,
                message: editedText.trimmingCharacters(in: .whitespacesAndNewlines),
                timestamp: editingMessage.timestamp,
                isAdmin: editingMessage.isAdmin
            )
            
            // Sort by timestamp to ensure chronological order
            updatedEvent.messages.sort { $0.timestamp < $1.timestamp }
            
            // Update local state
            self.event = updatedEvent
            self.onUpdate(updatedEvent)
            self.showEditSheet = false
            self.editingMessage = nil
            
            // Save only messages to Firestore
            let db = Firestore.firestore()
            let ref = db.collection("events").document(event.id.uuidString)
            
            // Convert messages to dict format
            var messagesArray: [[String: Any]] = []
            for msg in updatedEvent.messages {
                messagesArray.append([
                    "id": msg.id.uuidString,
                    "senderUID": msg.senderUID,
                    "senderName": msg.senderName,
                    "message": msg.message,
                    "timestamp": Timestamp(date: msg.timestamp),
                    "isAdmin": msg.isAdmin
                ])
            }
            // Update only the messages field
            ref.updateData(["messages": messagesArray]) { error in
                if let error = error {
                    print("❌ Error saving edited message: \(error)")
                } else {
                    print("✅ Message edited successfully")
                }
            }
        }
    }
    
    private func deleteMessage(_ message: IncidentMessage) {
        // Remove message from local event
        var updatedEvent = event
        updatedEvent.messages.removeAll { $0.id == message.id }
        
        // Sort by timestamp to ensure chronological order
        updatedEvent.messages.sort { $0.timestamp < $1.timestamp }
        
        // Update local state
        self.event = updatedEvent
        self.onUpdate(updatedEvent)
        
        // Save only messages to Firestore
        let db = Firestore.firestore()
        let ref = db.collection("events").document(event.id.uuidString)
        
        // Convert messages to dict format
        var messagesArray: [[String: Any]] = []
        for msg in updatedEvent.messages {
            messagesArray.append([
                "id": msg.id.uuidString,
                "senderUID": msg.senderUID,
                "senderName": msg.senderName,
                "message": msg.message,
                "timestamp": Timestamp(date: msg.timestamp),
                "isAdmin": msg.isAdmin
            ])
        }
        
        // Update only the messages field
        ref.updateData(["messages": messagesArray]) { error in
            if let error = error {
                print("❌ Error deleting message: \(error)")
            } else {
                print("✅ Message deleted successfully")
            }
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: IncidentMessage
    let isCurrentUser: Bool
    let isAdmin: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name with admin badge
                HStack(spacing: 4) {
                    Text(message.senderName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    if message.isAdmin {
                        Text("ADMIN")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
                
                // Message text
                Text(message.message)
                    .font(.callout)
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.message
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        
                        if isCurrentUser {
                            Button(action: onEdit) {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        } else if isAdmin {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        if isCurrentUser {
                            Button(action: onEdit) {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        } else if isAdmin {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isCurrentUser {
                Spacer(minLength: 50)
            }
        }
    }
}

// MARK: - Category Contact Card
struct CategoryContactCard: View {
    let category: String
    let contactName: String
    let contactNumber: String
    let isAdmin: Bool
    let onEdit: () -> Void
    
    private var categoryColor: Color {
        switch category {
        case "Electricity": return .yellow
        case "Water": return .cyan
        case "Lighting": return .orange
        default: return .blue
        }
    }
    
    private var categoryIcon: String {
        switch category {
        case "Electricity": return "bolt.fill"
        case "Water": return "drop.fill"
        case "Lighting": return "lightbulb.fill"
        default: return "phone.fill"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: categoryIcon)
                    .font(.title2)
                    .foregroundColor(categoryColor)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(categoryColor.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report \(category) Fault")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("One-tap WhatsApp report with your details")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isAdmin {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contactName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Menu {
                        Button(action: {
                            if let url = URL(string: "tel:\(contactNumber)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Label("Call \(contactNumber)", systemImage: "phone.fill")
                        }
                        
                        Button(action: {
                            var waNumber = contactNumber.filter { $0.isNumber }
                            if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                waNumber = "27" + waNumber.dropFirst()
                            }
                            // Pre-fill WhatsApp message with report details
                            let userName = UserDefaults.standard.string(forKey: "userName") ?? "User"
                            let userSurname = UserDefaults.standard.string(forKey: "userSurname") ?? ""
                            let userAddress = UserDefaults.standard.string(forKey: "userStreet") ?? ""
                            let userCell = UserDefaults.standard.string(forKey: "userCellNumber") ?? ""
                            
                            var message = "Hi, I would like to report a *\(category)* issue.%0A%0A"
                            message += "*Reporter Details:*%0A"
                            message += "Name: \(userName) \(userSurname)%0A"
                            if !userAddress.isEmpty {
                                message += "Address: \(userAddress)%0A"
                            }
                            if !userCell.isEmpty {
                                message += "Contact: \(userCell)%0A"
                            }
                            message += "%0APlease assist with this matter. Thank you."
                            
                            if let url = URL(string: "https://wa.me/\(waNumber)?text=\(message)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Label("WhatsApp with Pre-filled Report", systemImage: "message.circle.fill")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            UIPasteboard.general.string = contactNumber
                        }) {
                            Label("Copy Number", systemImage: "doc.on.doc")
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.caption)
                            Text(contactNumber)
                                .font(.subheadline)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [categoryColor, categoryColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}

// MARK: - Contact Popup Content
// MARK: - Category Contact Edit View (Admin Only)
struct CategoryContactEditView: View {
    @Environment(\.dismiss) private var dismiss
    let category: String
    @Binding var contactName: String
    @Binding var contactNumber: String
    
    @State private var editName: String = ""
    @State private var editNumber: String = ""
    
    private var categoryColor: Color {
        switch category {
        case "Electricity": return .yellow
        case "Water": return .cyan
        case "Lighting": return .orange
        default: return .blue
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Department/Organization Name")) {
                    TextField("Contact Name", text: $editName)
                }
                
                Section(header: Text("Contact Number")) {
                    TextField("Phone Number", text: $editNumber)
                        .keyboardType(.phonePad)
                }
                
                Section {
                    Text("This contact will be shown to users when they report \(category) issues. When users tap WhatsApp, a pre-filled message with their details and the issue type will be sent automatically - no manual typing needed!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit \(category) Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Save to Firestore - snapshot listener will auto-update UI
                        print("📝 Attempting to save category contact: \(category)")
                        print("   Name: \(editName)")
                        print("   Number: \(editNumber)")
                        print("   Current UID: \(FirebaseManager.shared.getCurrentUserUID() ?? "NONE")")
                        
                        let contact = CategoryContact(
                            id: category,
                            name: editName,
                            number: editNumber
                        )
                        FirebaseManager.shared.updateCategoryContact(contact) { result in
                            switch result {
                            case .success:
                                print("✅ Category contact updated successfully")
                                // Dismiss immediately - Firestore snapshot will update the UI
                                DispatchQueue.main.async {
                                    dismiss()
                                }
                            case .failure(let error):
                                print("❌ Failed to update category contact: \(error)")
                                print("❌ Error details: \(error.localizedDescription)")
                                if let nsError = error as NSError? {
                                    print("❌ Error code: \(nsError.code)")
                                    print("❌ Error domain: \(nsError.domain)")
                                    if nsError.code == 7 {
                                        print("⚠️ PERMISSION DENIED - You need isAdmin or isCommittee set to true in Firestore")
                                        print("⚠️ Go to Firebase Console → Firestore → users/{your-uid} → Set isAdmin: true")
                                    }
                                }
                                // Still dismiss on error so user can see the error in console
                                DispatchQueue.main.async {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .disabled(editName.isEmpty || editNumber.isEmpty)
                }
            }
            .onAppear {
                editName = contactName
                editNumber = contactNumber
            }
        }
    }
}

// MARK: - Triangle Arrow Shape
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
