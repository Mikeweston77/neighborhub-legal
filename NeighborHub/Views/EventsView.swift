import CoreLocation
import EventKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Notification for saving event to calendar
extension Notification.Name {
    static let saveEventToCalendar = Notification.Name("saveEventToCalendar")
}

// MARK: - Events View
struct EventsView: View {
    private func sendEventNotification(for event: LocalEvent) {
        let content = UNMutableNotificationContent()
        content.title = "New Community Event"
        content.body = "A new event was created: \(event.title)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "event-\(event.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    // Notification helper
    private func sendRequestAssistanceNotification(for event: LocalEvent) {
        let content = UNMutableNotificationContent()
        content.title = "Request Assistance Alert"
        content.body = "A new request for assistance was created: \(event.title)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "request-assistance-\(event.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    // Request Assistance events are now shown in the Watch UI. (Moved out of EventsView)
    // For full-screen event view
    @State private var selectedEventForFullScreen: LocalEvent? = nil
    // Editing event state
    @State private var editingEvent: LocalEvent? = nil

    // Calendar integration
    @State private var calendarExpanded: Bool = false
    @State private var calendarEvents: [EKEvent] = []
    @State private var calendarAccessGranted: Bool = false
    private let eventStore = EKEventStore()

    @AppStorage("eventsData") private var eventsData: String = ""
    @State private var events: [LocalEvent] = [] {
        didSet {
            removeExpiredEvents()
        }
    }

    // Helper: is current user the creator of an event?
    private func isEventCreator(_ event: LocalEvent) -> Bool {
        guard
            let creatorName = event.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines)
                .capitalized,
            let creatorSurname = event.creatorSurname?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).capitalized
        else { return false }
        let userFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let userSurnameVal = userSurname.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        return creatorName == userFirst && creatorSurname == userSurnameVal
    }
    @State private var showingAddEvent = false
    @State private var expandedEventID: UUID? = nil
    @State private var filterTodayOnly: Bool = false

    // Computed property: all event-type and report-type events
    @State private var eventsExpanded: Bool = true
    private var eventOnlyEvents: [LocalEvent] {
        let filtered = events.filter { $0.eventType == .event }
        let sorted = filtered.sorted { $0.date < $1.date }
        
        if filterTodayOnly {
            return sorted.filter { Calendar.current.isDateInToday($0.date) }
        }
        return sorted
    }

    // Helper: is event expired (within grace period)?
    private func isEventExpired(_ event: LocalEvent) -> Bool {
        // Only apply expiry to non-report events
        guard event.eventType != .report else { return false }
        let now = Date()
        let gracePeriod: TimeInterval = 2 * 60 * 60  // 2 hours
        return event.date < now && event.date >= now.addingTimeInterval(-gracePeriod)
    }
    // (alertEvents moved to WatchView)

    // Committee member admin check
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("committeeMembers") private var committeeMembers: String = ""
    
    // Cached admin/committee status from Firestore
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    private var isAdmin: Bool {
        // Primary check: Firestore roles (cached in UserDefaults)
        if userIsAdmin || userIsCommittee {
            return true
        }
        
        // Legacy fallback: name-based check (for backward compatibility during migration)
        return isAdminByName_Legacy
    }
    
    // LEGACY: Name-based admin check (kept for backward compatibility)
    private var isAdminByName_Legacy: Bool {
        let userFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let userSurnameFull = userSurname.trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
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
                // Handle single name matches
                if userFirst == first && userSurnameFull.isEmpty {
                    return true
                }
            }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Futuristic gradient background
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.03),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Events ScrollView
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if eventOnlyEvents.isEmpty {
                                // Modern Empty State
                                FuturisticEmptyState()
                                    .padding(.top, 60)
                            } else {
                                ForEach(Array(eventOnlyEvents.enumerated()), id: \.element.id) {
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
                                            expandedEventID = newValue ? event.id : nil
                                        }
                                    )
                                    
                                    ModernEventCard(
                                        event: eventBinding,
                                        isExpanded: isExpanded,
                                        canEdit: isAdmin || isEventCreator(event),
                                        isEventExpired: isEventExpired,
                                        onEdit: { editingEvent = event },
                                        onDelete: {
                                            deleteEventAndAttachments(event)
                                            FirebaseManager.shared.deleteEvent(
                                                id: event.id.uuidString
                                            ) { err in
                                                if let err = err {
                                                    #if DEBUG
                                                        print(
                                                            "Failed to delete event in Firebase: \(err)"
                                                        )
                                                    #endif
                                                }
                                            }
                                        },
                                        onFullScreen: {
                                            selectedEventForFullScreen = event
                                        },
                                        onUpdate: { updatedEvent in
                                            if let realIdx = events.firstIndex(where: {
                                                $0.id == updatedEvent.id
                                            }) {
                                                events[realIdx] = updatedEvent
                                                saveEvents()
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        // Add event button
                        Button(action: { showingAddEvent = true }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(Color.accentColor))
                                    .shadow(
                                        color: Color.accentColor.opacity(0.25), radius: 8, x: 0,
                                        y: 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("Add Event")
                        }
                    }
                }
                .sheet(isPresented: $showingAddEvent) {
                    AddEventView(onAdd: { newEvent in
                        // Attach creator info
                        var eventWithCreator = newEvent
                        eventWithCreator.creatorName = userName
                        eventWithCreator.creatorSurname = userSurname
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
                        // Send notification if it's a request assistance event
                        if eventWithCreator.eventType == .request {
                            sendRequestAssistanceNotification(for: eventWithCreator)
                        }
                        // Send notification if it's a normal event
                        if eventWithCreator.eventType == .event {
                            sendEventNotification(for: eventWithCreator)
                        }
                    }, allowedEventTypes: [.event])
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
                    // Start live updates from Firestore; falls back to local storage if empty
                    FirebaseManager.shared.watchEvents { fetched in
                        DispatchQueue.main.async {
                            // Guard against transient empty remote snapshots which can overwrite a valid local cache.
                            // If the remote fetch returned empty but we already have cached events, keep the local cache.
                            if fetched.isEmpty && !self.events.isEmpty {
                                #if DEBUG
                                    print(
                                        "[EventsView] Ignoring empty remote events snapshot; retaining local cache of \(self.events.count) events."
                                    )
                                #endif
                                return
                            }
                            // Otherwise replace local events (either remote has items or local was empty)
                            self.events = fetched
                            // Persist local cache
                            saveEvents()
                        }
                    }
                    loadEvents()
                    requestCalendarAccess()
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
                // Full screen event popup
                .fullScreenCover(item: $selectedEventForFullScreen) { event in
                    EventFullScreenView(event: event) {
                        selectedEventForFullScreen = nil
                    }
                }
        }
    
    // Request calendar access
    private func requestCalendarAccess() {
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    calendarAccessGranted = granted
                    if granted {
                        fetchCalendarEvents()
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    calendarAccessGranted = granted
                    if granted {
                        fetchCalendarEvents()
                    }
                }
            }
        }
    }

    // Fetch events from the app's calendar (for demo, fetch all events in next 30 days)
    private func fetchCalendarEvents() {
        let calendars = eventStore.calendars(for: .event)
        let oneMonth = Date().addingTimeInterval(60 * 60 * 24 * 30)
        let predicate = eventStore.predicateForEvents(
            withStart: Date(), end: oneMonth, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        calendarEvents = events.filter { $0.calendar.allowsContentModifications }
    }

    // Save event to calendar when expanded
    private func saveEventToCalendar(_ event: LocalEvent) {
        guard calendarAccessGranted else { return }
        let calendars = eventStore.calendars(for: .event)
        let calendar =
            calendars.first { $0.allowsContentModifications }
            ?? eventStore.defaultCalendarForNewEvents
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = event.title
        ekEvent.startDate = event.date
        ekEvent.endDate = event.date.addingTimeInterval(60 * 60)  // 1 hour default
        ekEvent.calendar = calendar
        if let desc = event.description { ekEvent.notes = desc }
        if let loc = event.location { ekEvent.location = loc }
        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            fetchCalendarEvents()
        } catch {
            // Handle error if needed
        }
    }
    // AlertsSection struct removed; alert events are now handled inline in the List above.

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
            removeExpiredEvents()
        }
    }

    // Remove expired events (date < now - grace period)
    private func removeExpiredEvents() {
        let now = Date()
        let gracePeriod: TimeInterval = 2 * 60 * 60  // 2 hours in seconds
        let filtered = events.filter {
            // Always keep .report events, only expire others
            $0.eventType == .report || $0.date >= now.addingTimeInterval(-gracePeriod)
        }
        if filtered.count != events.count {
            events = filtered
            saveEvents()
        }
    }
    private func deleteEvent(_ event: LocalEvent) {
        deleteEventAndAttachments(event)
    }

    // Delete event and any associated attachment file(s)
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
                        // Ignore deletion errors but log in debug
                        #if DEBUG
                            print("Failed to delete attachment at \(url): \(error)")
                        #endif
                    }
                }
            }
        }

        // Remove the event from the list and persist
        events.removeAll { $0.id == event.id }
        saveEvents()

        // Remove any scheduled reminder for this event
        EventFullScreenView.removeScheduledReminder(for: event.id)
    }
}

// Redesigned EventRow with local comment open/close state and clean UI
struct EventRow: View {
    @Binding var event: LocalEvent
    var onUpdate: (LocalEvent) -> Void
    @Binding var expanded: Bool
    var showDeleteButton: Bool = false
    var onDelete: (() -> Void)? = nil
    var onFullScreen: (() -> Void)? = nil
    // Comments removed
    var isEventExpired: ((LocalEvent) -> Bool)? = nil
    init(
        event: Binding<LocalEvent>, onUpdate: @escaping (LocalEvent) -> Void,
        expanded: Binding<Bool>, showDeleteButton: Bool = false, onDelete: (() -> Void)? = nil,
        onFullScreen: (() -> Void)? = nil, isEventExpired: ((LocalEvent) -> Bool)? = nil
    ) {
        self._event = event
        self.onUpdate = onUpdate
        self._expanded = expanded
        self.showDeleteButton = showDeleteButton
        self.onDelete = onDelete
        self.onFullScreen = onFullScreen
        self.isEventExpired = isEventExpired
    }
    private var eventTypeColor: Color {
        switch event.eventType {
        case .event:
            return .blue
        case .report:
            return .pink
        case .request:
            return .red
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
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.25)) {
                    expanded.toggle()
                    if expanded {
                        // Auto-save to calendar when expanded
                        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows
                            .first?.rootViewController?.presentedViewController?.dismiss(
                                animated: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            // Use NotificationCenter to call parent saveEventToCalendar
                            NotificationCenter.default.post(
                                name: .saveEventToCalendar, object: event)
                        }
                    }
                }
            }) {
                HStack(alignment: .top, spacing: 10) {
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
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(eventTypeColor)
                            .font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.eventType.rawValue)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(eventTypeColor)
                        // Strikethrough if expired (within grace period)
                        Text(event.title)
                            .fontWeight(.bold)
                            .font(.headline)
                            .lineLimit(2)
                            .strikethrough(isEventExpired?(event) ?? false, color: .red)
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
                    ZStack {
                        Circle()
                            .foregroundColor(.clear)
                            .frame(width: 28, height: 28)
                            .background(
                                BlurView(style: .systemThinMaterial)
                                    .clipShape(Circle())
                            )
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.accentColor)
                            .font(.headline)
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
            if expanded {
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
                                        // WhatsApp requires country code, assume South Africa (+27) if number is 10 digits and starts with 0
                                        var waNumber = contactCell.filter { $0.isNumber }
                                        if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                            waNumber = "27" + waNumber.dropFirst()
                                        }
                                        if let url = URL(string: "https://wa.me/\(waNumber)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Label(
                                            "WhatsApp Call / Message",
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
                        // Save to Calendar button (left, replaces clock)
                        Button(action: {
                            NotificationCenter.default.post(
                                name: .saveEventToCalendar, object: event)
                        }) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.caption2)
                                .foregroundColor(eventTypeColor)
                        }
                        .padding(.leading, 10)
                        .buttonStyle(.plain)
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
                .onTapGesture {
                    onFullScreen?()
                }
            }

        }
    }

    // Share text for the event
    private var shareText: String {
        var text = "NeighborHub Event: \(event.title)\n"
        if let desc = event.description, !desc.isEmpty {
            text += "\n\(desc)\n"
        }
        if let loc = event.location, !loc.isEmpty {
            text += "\nLocation: \(loc)\n"
        }
        text += "\nDate: \(event.date.formatted(date: .abbreviated, time: .shortened))"
        return text
    }
    // MARK: - Glassmorphic BlurView Helper

    struct BlurView: UIViewRepresentable {
        var style: UIBlurEffect.Style
        func makeUIView(context: Context) -> UIVisualEffectView {
            return UIVisualEffectView(effect: UIBlurEffect(style: style))
        }
        func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
    }
}

// MARK: - Add Event View
struct AddEventView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var pastedImage: UIImage? = nil
    @State private var pastedFileURL: URL? = nil
    @State private var showAttachmentSheet = false
    @State private var showAttachmentPicker = false
    @State private var showDocumentPicker = false
    @State private var showAttachmentInfo = false
    @State private var attachmentPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var location: String = ""
    @State private var date: Date = Date()
    @State private var eventType: EventType = .event
    @State private var reportCategory: String = "General"
    // Note: request-assistance creation was moved to HomeView. AddEventView no longer auto-fills location for requests.
    // Contact details state
    @State private var useCustomContact = false
    @State private var customContact = ""
    @State private var useCustomCell = false
    @State private var customCell = ""
    // User data from AppStorage
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userCell") private var userCell: String = ""
    // Admin status
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    // Category-specific contact numbers (admin-editable)
    @AppStorage("electricityContactName") private var electricityContactName: String = "Electricity Department"
    @AppStorage("electricityContactNumber") private var electricityContactNumber: String = "0800 111 300"
    @AppStorage("waterContactName") private var waterContactName: String = "Water Department"
    @AppStorage("waterContactNumber") private var waterContactNumber: String = "0800 111 300"
    @AppStorage("lightingContactName") private var lightingContactName: String = "Street Lighting Department"
    @AppStorage("lightingContactNumber") private var lightingContactNumber: String = "0800 111 300"
    @State private var showCategoryContactEdit = false
    @State private var editingContactCategory = ""
    // For editing
    var event: LocalEvent? = nil
    var onSave: ((LocalEvent) -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onAdd: ((LocalEvent) -> Void)? = nil
    var allowedEventTypes: [EventType]? = nil  // If nil, allow all types

    var body: some View {
        NavigationView {
            Form {
                // Only show type picker if allowedEventTypes includes multiple types
                if let allowed = allowedEventTypes, allowed.count > 1 {
                    Section {
                        Picker("Type", selection: $eventType) {
                            ForEach(allowed) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                // Report Category Picker (enabled for reports)
                if eventType == .report {
                    Section(header: Text("Report Category")) {
                        Picker("Category", selection: $reportCategory) {
                            Text("General").tag("General")
                            Text("Electricity").tag("Electricity")
                            Text("Water").tag("Water")
                            Text("Roads & Infrastructure").tag("Infrastructure")
                            Text("Safety & Security").tag("Safety")
                            Text("Waste Management").tag("Waste")
                            Text("Street Lighting").tag("Lighting")
                            Text("Environment").tag("Environment")
                            Text("Community Issue").tag("Community")
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                // Removed Event Title section for report popup
                if !(eventType == .report) {
                    Section(header: Text("Event Title")) {
                        SmartTextField(
                            "Title",
                            text: $title,
                            keyboardType: .default,
                            autocapitalization: .words,
                            autocorrection: true,
                            submitLabel: .next
                        )
                    }
                }
                Section(header: Text("Description")) {
                    SmartTextEditor(
                        text: $description,
                        placeholder: "Describe your event...",
                        minHeight: 80,
                        autocapitalization: .sentences,
                        autocorrection: true
                    )
                    if let img = pastedImage {
                        ZoomableImageView(image: img)
                            .frame(maxHeight: 220)
                            .cornerRadius(10)
                            .padding(.top, 4)
                    } else if let fileURL = pastedFileURL {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            Text(fileURL.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }

                // Attach button: much smaller, left-aligned, under description
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: { showAttachmentSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperclip")
                                    .font(.body)
                                    .foregroundColor(.accentColor)
                                Text("Attach Image or File")
                                    .font(.callout)
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Attach Image or File")

                        // Short helper text to guide users about accepted types and preview behavior
                        Text(
                            "Capture with camera or choose from photo library. Accepted: images (jpg, png, heic) and documents (pdf, docx, txt). Images display inline; other files show a filename and can be opened."
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)

                        Button(action: { showAttachmentInfo = true }) {
                            Text("How attachments look")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }
                .padding(.leading, 4)
                .padding(.top, -8)
                .actionSheet(isPresented: $showAttachmentSheet) {
                    ActionSheet(
                        title: Text("Attach"),
                        buttons: [
                            .default(Text("Camera")) {
                                attachmentPickerSource = .camera
                                showAttachmentPicker = true
                            },
                            .default(Text("Photo Library")) {
                                attachmentPickerSource = .photoLibrary
                                showAttachmentPicker = true
                            },
                            .default(Text("Files")) {
                                showDocumentPicker = true
                            },
                            .cancel(),
                        ])
                }
                .sheet(isPresented: $showAttachmentPicker) {
                    ImagePicker(image: $pastedImage, sourceType: attachmentPickerSource)
                }
                .sheet(isPresented: $showDocumentPicker) {
                    EventDocumentPicker(fileURL: $pastedFileURL, image: $pastedImage)
                }

                // Attachment info example sheet
                .sheet(isPresented: $showAttachmentInfo) {
                    AttachmentInfoView()
                }

                Section(header: Text("Location")) {
                    // Location is entered manually in Add Event UI. Request Assistance uses HomeView's Request Help flow.
                    SmartTextField(
                        "Location (optional)",
                        text: $location,
                        keyboardType: .default,
                        autocapitalization: .words,
                        autocorrection: true,
                        submitLabel: .done
                    )
                }
                Section(header: Text("Date & Time")) {
                    DatePicker(
                        "Date & Time", selection: $date,
                        displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("Contact Details")) {
                    Toggle("Use custom contact name", isOn: $useCustomContact)
                    if useCustomContact {
                        SmartTextField(
                            "Contact name",
                            text: $customContact,
                            keyboardType: .default,
                            autocapitalization: .words,
                            autocorrection: true,
                            submitLabel: .next
                        )
                    } else {
                        Text(userName.isEmpty ? "Default contact name" : userName)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Use custom cellphone", isOn: $useCustomCell)
                    if useCustomCell {
                        SmartTextField(
                            "Cellphone",
                            text: $customCell,
                            keyboardType: .phonePad,
                            autocapitalization: .none,
                            autocorrection: false,
                            submitLabel: .done
                        )
                    } else {
                        Text(userCell.isEmpty ? "No cellphone set" : userCell)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            )
            .navigationTitle("Add Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel = onCancel {
                            onCancel()
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(event != nil ? "Save" : "Add") {
                        // Compress image for Firestore storage (instant loading)
                        let imageData: Data? =
                            pastedImage != nil
                            ? pastedImage?.compressedForFirestore() : (event?.imageData)

                        // Determine contact details
                        let contactName = useCustomContact ? customContact : userName
                        let contactCell = useCustomCell ? customCell : userCell

                        var newEvent = LocalEvent(
                            id: event?.id ?? UUID(),
                            title: title,
                            description: description.isEmpty ? nil : description,
                            location: location.isEmpty ? nil : location,
                            date: date,
                            eventType: eventType,
                            comments: event?.comments ?? [],
                            imageData: imageData,
                            fileURL: pastedFileURL,
                            contactName: contactName.isEmpty ? nil : contactName,
                            contactCell: contactCell.isEmpty ? nil : contactCell
                        )
                        // Preserve or set creator info
                        if let event = event {
                            newEvent.creatorName = event.creatorName
                            newEvent.creatorSurname = event.creatorSurname
                        }
                        // Save report category to metadata (preserve existing metadata when editing)
                        if eventType == .report {
                            var metadata = event?.metadata ?? [:]
                            metadata["category"] = reportCategory
                            newEvent.metadata = metadata
                        }
                        if let onSave = onSave {
                            onSave(newEvent)
                        } else if let onAdd = onAdd {
                            onAdd(newEvent)
                        }
                        dismiss()
                    }
                    .disabled(eventType != .report && title.isEmpty)
                }
            }
            .onAppear {
                // Track screen view
                AnalyticsService.shared.trackScreenView("Events")
                if let event = event {
                    title = event.title
                    description = event.description ?? ""
                    location = event.location ?? ""
                    date = event.date
                    eventType = event.eventType
                    // Load report category from metadata
                    if let category = event.metadata?["category"] {
                        reportCategory = category
                    }
                    if let imgData = event.imageData, let img = UIImage(data: imgData) {
                        pastedImage = img
                    }
                    if let file = event.fileURL {
                        // If the stored fileURL points to an image, load it into pastedImage so the UI treats it like a photo
                        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
                            pastedImage = img
                            pastedFileURL = nil
                        } else {
                            pastedFileURL = file
                        }
                    }

                    // Populate contact fields
                    if let contactName = event.contactName, !contactName.isEmpty,
                        contactName != userName
                    {
                        useCustomContact = true
                        customContact = contactName
                    }
                    if let contactCell = event.contactCell, !contactCell.isEmpty,
                        contactCell != userCell
                    {
                        useCustomCell = true
                        customCell = contactCell
                    }
                } else {
                    // When creating a new event, set the default type based on allowedEventTypes
                    if let allowed = allowedEventTypes, let firstType = allowed.first {
                        eventType = firstType
                    }
                }
            }
            // Removed request-assistance specific behaviour from AddEventView
            .sheet(isPresented: $showCategoryContactEdit) {
                CategoryContactEditView(
                    category: editingContactCategory,
                    contactName: bindingForContactName(editingContactCategory),
                    contactNumber: bindingForContactNumber(editingContactCategory)
                )
            }
        }
    }
    
    // Helper computed properties for category contacts
    private var categoryContactName: String {
        switch reportCategory {
        case "Electricity": return electricityContactName
        case "Water": return waterContactName
        case "Lighting": return lightingContactName
        default: return ""
        }
    }
    
    private var categoryContactNumber: String {
        switch reportCategory {
        case "Electricity": return electricityContactNumber
        case "Water": return waterContactNumber
        case "Lighting": return lightingContactNumber
        default: return ""
        }
    }
    
    private func bindingForContactName(_ category: String) -> Binding<String> {
        switch category {
        case "Electricity": return $electricityContactName
        case "Water": return $waterContactName
        case "Lighting": return $lightingContactName
        default: return .constant("")
        }
    }
    
    private func bindingForContactNumber(_ category: String) -> Binding<String> {
        switch category {
        case "Electricity": return $electricityContactNumber
        case "Water": return $waterContactNumber
        case "Lighting": return $lightingContactNumber
        default: return .constant("")
        }
    }

    // geocoding helper removed — AddEventView no longer performs automatic reverse-geocoding for requests
}
// MARK: - ZoomableImageView for Pinch-to-Zoom

struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newScale = lastScale * value
                            scale = min(max(newScale, 1.0), 4.0)
                        }
                        .onEnded { value in
                            let newScale = lastScale * value
                            scale = min(max(newScale, 1.0), 4.0)
                            lastScale = scale
                            if scale == 1.0 {
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                let maxX = (geometry.size.width * (scale - 1)) / 2
                                let maxY = (geometry.size.height * (scale - 1)) / 2
                                offset.width = min(max(offset.width, -maxX), maxX)
                                offset.height = min(max(offset.height, -maxY), maxY)
                                lastOffset = offset
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            let newOffset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
                            let maxX = (geometry.size.width * (scale - 1)) / 2
                            let maxY = (geometry.size.height * (scale - 1)) / 2
                            offset.width = min(max(newOffset.width, -maxX), maxX)
                            offset.height = min(max(newOffset.height, -maxY), maxY)
                        }
                        .onEnded { value in
                            guard scale > 1.0 else { return }
                            let newOffset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
                            let maxX = (geometry.size.width * (scale - 1)) / 2
                            let maxY = (geometry.size.height * (scale - 1)) / 2
                            offset.width = min(max(newOffset.width, -maxX), maxX)
                            offset.height = min(max(newOffset.height, -maxY), maxY)
                            lastOffset = offset
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                )
        }
        .frame(height: 220)
    }
}

// MARK: - Attachment Info View
struct AttachmentInfoView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Accepted file types")
                        .font(.headline)
                    Text(
                        "Camera: Capture photos directly with your device camera.\nImages: JPG, PNG, HEIC from photo library (display inline).\nDocuments: PDF, DOCX, TXT, and other file types (display as a filename and can be opened)."
                    )
                    .font(.body)
                    .foregroundColor(.secondary)

                    Divider()

                    Text("How attachments appear")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inline image")
                            .font(.subheadline)
                            .bold()
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .cornerRadius(10)
                            .padding(.bottom, 6)
                        Text(
                            "When you attach an image, it will display directly inside the event card and the detailed view."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("File attachment")
                            .font(.subheadline)
                            .bold()
                        HStack {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text("ExampleDocument.pdf")
                                    .font(.subheadline)
                                Text("Tap to open the file")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                        Text(
                            "Other file types will show as a filename with an open button — tap to preview or open in another app."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Attachment Info")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Document Picker for Events
struct EventDocumentPicker: UIViewControllerRepresentable {
    @Binding var fileURL: URL?
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.data, UTType.content, UTType.item, UTType.image],
            asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController, context: Context
    ) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: EventDocumentPicker

        init(_ parent: EventDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
        ) {
            guard let src = urls.first else {
                parent.fileURL = nil
                parent.image = nil
                return
            }

            // Use centralized DocumentStorageManager for file storage
            guard let copiedURL = DocumentStorageManager.shared.storeDocument(from: src, subdirectory: "Events") else {
                print("EventDocumentPicker: Failed to store document")
                parent.fileURL = nil
                parent.image = nil
                return
            }

            // If the copied URL is an image, load it into the image binding and clear fileURL so UI treats it like a photo
            if let data = try? Data(contentsOf: copiedURL), let uiimg = UIImage(data: data) {
                parent.image = uiimg
                parent.fileURL = nil
                return
            }

            parent.fileURL = copiedURL
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.fileURL = nil
        }
    }
}

// MARK: - Modern Event Components

/// Modern Stats Header
struct ModernEventStatsHeader: View {
    let totalEvents: Int
    let upcomingEvents: Int
    let todayEvents: Int
    @Binding var filterTodayOnly: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            EventStatBadge(
                icon: "calendar.badge.clock",
                count: totalEvents,
                label: "Total",
                gradient: LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                onTap: nil
            )
            
            EventStatBadge(
                icon: "clock.fill",
                count: upcomingEvents,
                label: "Upcoming",
                gradient: LinearGradient(
                    colors: [Color.purple, Color.purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                onTap: nil
            )
            
            EventStatBadge(
                icon: "star.fill",
                count: todayEvents,
                label: "Today",
                gradient: LinearGradient(
                    colors: [Color.orange, Color.orange.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                isActive: filterTodayOnly,
                onTap: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        filterTodayOnly.toggle()
                    }
                }
            )
        }
    }
}

struct EventStatBadge: View {
    let icon: String
    let count: Int
    let label: String
    let gradient: LinearGradient
    var isActive: Bool = false
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        let content = VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(isActive ? gradient.opacity(0.3) : gradient.opacity(0.2))
                    .frame(width: 38, height: 38)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(gradient)
            }
            
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isActive ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: isActive ? Color.orange.opacity(0.15) : Color.black.opacity(0.06), radius: isActive ? 10 : 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? gradient : LinearGradient(
                    colors: [Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isActive ? 2 : 0)
        )
        
        Group {
            if let onTap = onTap {
                Button(action: onTap) {
                    content
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                content
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(gradient.opacity(0.2), lineWidth: 1.5)
        )
    }
}

/// Futuristic Empty State
struct FuturisticEmptyState: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                // Animated rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.3 - Double(index) * 0.1),
                                    Color.purple.opacity(0.3 - Double(index) * 0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(
                            width: 120 + CGFloat(index * 30),
                            height: 120 + CGFloat(index * 30)
                        )
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .opacity(isAnimating ? 0.3 : 0.6)
                        .animation(
                            Animation.easeInOut(duration: 2.0 + Double(index) * 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
                
                // Central icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: isAnimating
                )
            }
            
            VStack(spacing: 12) {
                Text("No Events Yet")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("Create your first community event\nand bring neighbors together!")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

/// Modern Event Card
struct ModernEventCard: View {
    @Binding var event: LocalEvent
    @Binding var isExpanded: Bool
    let canEdit: Bool
    let isEventExpired: ((LocalEvent) -> Bool)?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onFullScreen: () -> Void
    let onUpdate: (LocalEvent) -> Void
    
    @State private var showDeleteAlert = false
    @State private var scale: CGFloat = 1.0
    @State private var showMapOptions = false
    @State private var showReminderSheet = false
    @State private var reminderDate: Date = Date()
    @AppStorage("scheduledRemindersData") private var scheduledRemindersData: String = ""
    @State private var existingReminder: EventFullScreenView.ReminderInfo? = nil
    
    private var timeUntilEvent: String {
        let now = Date()
        if event.date < now {
            return "Past event"
        }
        
        let interval = event.date.timeIntervalSince(now)
        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if days > 0 {
            return "in \(days)d \(hours)h"
        } else if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes)m"
        }
    }
    
    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.08),
                Color.purple.opacity(0.05),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        let iconGradient = LinearGradient(
            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        let symbolGradient = LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        let timeBadgeGradient = LinearGradient(
            colors: [Color.orange, Color.orange.opacity(0.8)],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 14) {
                    // Event Icon with gradient
                    ZStack {
                        Circle()
                            .fill(iconGradient)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(symbolGradient)
                    }
                    
                    // Event Info
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            // Time badge
                            if event.date > Date() {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 10))
                                    Text(timeUntilEvent)
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(timeBadgeGradient)
                                )
                            }
                            
                            Spacer()
                        }
                        
                        Text(event.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .strikethrough(isEventExpired?(event) ?? false, color: .red)
                        
                        // Date and location
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 12))
                                        .foregroundColor(.blue)
                                    Text(event.date, style: .date)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                
                                Button(action: {
                                    // Set reminder action using the EventFullScreenView system
                                    reminderDate = event.date > Date() ? event.date.addingTimeInterval(-3600) : Date().addingTimeInterval(3600)
                                    showReminderSheet = true
                                }) {
                                    Text("Set Reminder")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            if let location = event.location, !location.isEmpty {
                                HStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.red)
                                        Text(location)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Button(action: {
                                        // Get directions using the EventFullScreenView system
                                        showMapOptions = true
                                    }) {
                                        Text("Get Directions")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(14)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Image
                    if let imageData = event.imageData, let uiImage = UIImage(data: imageData) {
                        Button(action: {
                            onFullScreen()
                        }) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: 180)
                                .clipped()
                                .cornerRadius(14)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 16)
                    }
                    
                    // Description
                    if let description = event.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Details", systemImage: "text.alignleft")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.blue)
                            
                            Text(description)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Contact Info
                    if let contactName = event.contactName, !contactName.isEmpty,
                       let contactCell = event.contactCell, !contactCell.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Contact", systemImage: "person.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.blue)
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(contactName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(contactCell)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(spacing: 8) {
                                    // Call Button
                                    Button(action: {
                                        if let url = URL(string: "tel:\(contactCell)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "phone.fill")
                                                .font(.system(size: 14))
                                            Text("Call")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.blue, Color.blue.opacity(0.8)],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                        )
                                    }
                                    
                                    // WhatsApp Button
                                    Button(action: {
                                        var waNumber = contactCell.filter { $0.isNumber }
                                        if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                            waNumber = "27" + waNumber.dropFirst()
                                        }
                                        if let url = URL(string: "https://wa.me/\(waNumber)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "message.fill")
                                                .font(.system(size: 14))
                                            Text("WhatsApp")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.green, Color.green.opacity(0.8)],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                        )
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.06))
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    // Action buttons
                    if canEdit {
                        HStack(spacing: 12) {
                            Button(action: onEdit) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Edit")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue.opacity(0.1))
                                )
                            }
                            
                            Button(action: { showDeleteAlert = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Delete")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.1))
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.blue.opacity(0.15), radius: 12, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .scaleEffect(scale)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                scale = 0.98
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    scale = 1.0
                }
            }
        }
        .alert("Delete Event", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete this event? This action cannot be undone.")
        }
        .actionSheet(isPresented: $showMapOptions) {
            if let location = event.location {
                return ActionSheet(
                    title: Text("Open Location"),
                    message: Text("Choose a maps app to open this location."),
                    buttons: [
                        .default(Text("Apple Maps")) {
                            openInAppleMaps(address: location)
                        },
                        .default(Text("Google Maps")) {
                            openInGoogleMaps(address: location)
                        },
                        .cancel()
                    ]
                )
            } else {
                return ActionSheet(title: Text("No location available"), buttons: [.cancel()])
            }
        }
        .sheet(isPresented: $showReminderSheet) {
            ReminderSheet(
                reminderDate: $reminderDate,
                eventTitle: event.title,
                onSchedule: {
                    scheduleReminder(for: event, at: reminderDate)
                    showReminderSheet = false
                    existingReminder = EventFullScreenView.ReminderInfo(
                        id: "event_reminder_\(event.id.uuidString)",
                        title: "Event Reminder: \(event.title)",
                        body: event.description ?? "Don't forget your event!",
                        date: reminderDate
                    )
                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                },
                onCancel: {
                    showReminderSheet = false
                }
            )
        }
        .onAppear {
            updateExistingReminder()
        }
    }
    
    // MARK: - Helper Functions
    
    private func scheduleReminder(for event: LocalEvent, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Event Reminder: \(event.title)"
        content.body = event.description ?? "Don't forget your event!"
        content.sound = .default
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let identifier = "event_reminder_\(event.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule reminder: \(error.localizedDescription)")
            }
        }
        // Save reminder info
        saveScheduledReminder(
            EventFullScreenView.ReminderInfo(
                id: identifier,
                title: content.title,
                body: content.body,
                date: date
            )
        )
    }
    
    private func saveScheduledReminder(_ reminder: EventFullScreenView.ReminderInfo) {
        var reminders = loadScheduledReminders()
        reminders.removeAll { $0.id == reminder.id }
        reminders.append(reminder)
        if let data = try? JSONEncoder().encode(reminders) {
            scheduledRemindersData = String(data: data, encoding: .utf8) ?? ""
        }
    }
    
    private func loadScheduledReminders() -> [EventFullScreenView.ReminderInfo] {
        guard let data = scheduledRemindersData.data(using: .utf8), !scheduledRemindersData.isEmpty else { return [] }
        let reminders = (try? JSONDecoder().decode([EventFullScreenView.ReminderInfo].self, from: data)) ?? []
        
        // Clean up expired reminders (older than 2 hours)
        let now = Date()
        let twoHoursInSeconds: TimeInterval = 2 * 60 * 60
        let cleanedReminders = reminders.filter { reminder in
            let timeSinceReminder = now.timeIntervalSince(reminder.date)
            return timeSinceReminder <= twoHoursInSeconds
        }
        
        // Save cleaned reminders back if any were removed
        if cleanedReminders.count != reminders.count {
            if let cleanedData = try? JSONEncoder().encode(cleanedReminders) {
                scheduledRemindersData = String(data: cleanedData, encoding: .utf8) ?? ""
            }
        }
        
        return cleanedReminders
    }
    
    private func findExistingReminder() -> EventFullScreenView.ReminderInfo? {
        let reminders = loadScheduledReminders()
        let id = "event_reminder_\(event.id.uuidString)"
        return reminders.first(where: { $0.id == id })
    }
    
    private func updateExistingReminder() {
        existingReminder = findExistingReminder()
    }
    
    private func openInAppleMaps(address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openInGoogleMaps(address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let googleMapsURL = URL(string: "comgooglemaps://?q=\(encoded)")
        if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let webUrl = URL(string: "https://maps.google.com/?q=\(encoded)") {
            UIApplication.shared.open(webUrl)
        }
    }
}

// MARK: - Reminder Sheet
struct ReminderSheet: View {
    @Binding var reminderDate: Date
    var eventTitle: String
    var onSchedule: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Set Reminder for \(eventTitle)")
                    .font(.headline)
                DatePicker("Reminder Time", selection: $reminderDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                Spacer()
                HStack {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(.red)
                    Spacer()
                    Button("Schedule") { onSchedule() }
                        .fontWeight(.bold)
                }
            }
            .padding()
            .navigationTitle("Set Reminder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

