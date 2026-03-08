import SwiftUI

// MARK: - Full Screen Event View
struct EventFullScreenView: View {
    // MARK: - Static helper to remove scheduled reminder for a deleted event
    static func removeScheduledReminder(for eventID: UUID) {
        let key = "scheduledRemindersData"
        let id = "event_reminder_\(eventID.uuidString)"
        let defaults = UserDefaults.standard
        guard let data = defaults.string(forKey: key)?.data(using: .utf8), !data.isEmpty else { return }
        if var reminders = try? JSONDecoder().decode([ReminderInfo].self, from: data) {
            reminders.removeAll { $0.id == id }
            if let newData = try? JSONEncoder().encode(reminders) {
                let newString = String(data: newData, encoding: .utf8) ?? ""
                defaults.set(newString, forKey: key)
            }
        }
        // Also remove pending notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
    // For saving reminders
    @AppStorage("scheduledRemindersData") private var scheduledRemindersData: String = ""
    @State private var showMapOptions = false
    @State private var showReminderSheet = false
    @State private var reminderDate: Date = Date()
    @State private var reminderScheduled = false
    @State private var existingReminder: ReminderInfo? = nil
    @State private var showFullScreenImage = false
    let event: LocalEvent
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Blurred/material background
            if #available(iOS 15.0, *) {
                VisualEffectBlur(blurStyle: .systemMaterial)
                    .ignoresSafeArea()
            } else {
                Color(.systemBackground)
                    .ignoresSafeArea()
            }
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let imageData = event.imageData, let uiImage = UIImage(data: imageData) {
                            Button(action: {
                                showFullScreenImage = true
                            }) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 320)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.bottom, 8)
                        }
                        Text(event.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.bottom, 2)
                        Text(event.eventType.rawValue)
                            .font(.headline)
                            .foregroundColor(.accentColor)
                        if let location = event.location, !location.isEmpty {
                            Button(action: { showMapOptions = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.red)
                                    Text(location)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                        .underline()
                                }
                            }
                            .buttonStyle(.plain)
                            .actionSheet(isPresented: $showMapOptions) {
                                ActionSheet(
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
                            }
                        }
                        // Show scheduled reminder if it exists
                        if let reminder = existingReminder {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reminder scheduled!")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    HStack(spacing: 2) {
                                        Text(reminder.date, style: .date)
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                        Text(",")
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                        Text(reminder.date, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        Button(action: {
                            reminderDate = existingReminder?.date ?? (event.date > Date() ? event.date : Date().addingTimeInterval(3600))
                            showReminderSheet = true
                        }) {
                            (Text(event.date, style: .date) + Text(" , ") + Text(event.date, style: .time))
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showReminderSheet) {
                            ReminderSheet(reminderDate: $reminderDate, eventTitle: event.title, onSchedule: {
                                scheduleReminder(for: event, at: reminderDate)
                                reminderScheduled = true
                                showReminderSheet = false
                                // Update local state
                                existingReminder = ReminderInfo(id: "event_reminder_\(event.id.uuidString)", title: "Event Reminder: \(event.title)", body: event.description ?? "Don't forget your event!", date: reminderDate)
                            }, onCancel: {
                                showReminderSheet = false
                            })
                        }
                        if let description = event.description, !description.isEmpty {
                            Divider().padding(.vertical, 6)
                            Text(description)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Event Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { onDismiss() }
                    }
                }
            }
            .background(Color.clear)
            .ignoresSafeArea(edges: .bottom)
        }
        .fullScreenCover(isPresented: $showFullScreenImage) {
            if let imageData = event.imageData, let uiImage = UIImage(data: imageData) {
                ImageFullScreenView(image: uiImage) {
                    showFullScreenImage = false
                }
            }
        }
        .onAppear {
            updateExistingReminder()
        }
    }
    // MARK: - Load scheduled reminder for this event
    private func findExistingReminder() -> ReminderInfo? {
        let reminders = loadScheduledReminders()
        let id = "event_reminder_\(event.id.uuidString)"
        return reminders.first(where: { $0.id == id })
    }

    // MARK: - On appear, update existingReminder
    init(event: LocalEvent, onDismiss: @escaping () -> Void) {
        self.event = event
        self.onDismiss = onDismiss
        // _existingReminder is a State wrapper, so we can't set it directly here
        // Instead, use .onAppear in the body
    }

    // MARK: - Reminder Scheduling
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
        // Save reminder info for HomeView
        saveScheduledReminder(
            ReminderInfo(
                id: identifier,
                title: content.title,
                body: content.body,
                date: date
            )
        )
    }

    // MARK: - Save Reminder to AppStorage
    private func saveScheduledReminder(_ reminder: ReminderInfo) {
        var reminders = loadScheduledReminders()
        // Remove any existing with same id (replace)
        reminders.removeAll { $0.id == reminder.id }
        reminders.append(reminder)
        if let data = try? JSONEncoder().encode(reminders) {
            scheduledRemindersData = String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func loadScheduledReminders() -> [ReminderInfo] {
        guard let data = scheduledRemindersData.data(using: .utf8), !scheduledRemindersData.isEmpty else { return [] }
        let reminders = (try? JSONDecoder().decode([ReminderInfo].self, from: data)) ?? []
        
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

    // MARK: - ReminderInfo Model
    struct ReminderInfo: Codable, Identifiable {
        let id: String
        let title: String
        let body: String
        let date: Date
    }

    // MARK: - Update existingReminder on appear
    private func updateExistingReminder() {
        existingReminder = findExistingReminder()
    }

    // MARK: - Open in Maps Helpers
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

// MARK: - Image Full Screen View
struct ImageFullScreenView: View {
    let image: UIImage
    var onDismiss: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1 {
                                withAnimation {
                                    scale = 1
                                    lastScale = 1
                                }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1 {
                            scale = 1
                            lastScale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// VisualEffectBlur for iOS 15+
@available(iOS 15.0, *)
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
