import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct PatrolWorkspaceView: View {
    fileprivate struct PatrolMapPin: Identifiable, Equatable {
        let id: String
        let userId: String?
        let latitude: Double
        let longitude: Double
        let name: String
        let initials: String
        let freshnessLabel: String?
        let freshnessColor: Color?
        let isCurrentUser: Bool
    }

    private enum WorkspaceSection: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case comms = "Comms"
        case map = "Map"

        var id: String { rawValue }
    }

    let schedule: FirebaseManager.PatrolSchedule
    let currentUserId: String?
    let isAdmin: Bool
    let isUsingCellularData: Bool
    let lastPublishAt: Date
    @Binding var cellularPublishIntervalMinutes: Int
    let liveLocations: [FirebaseManager.PatrolLocationUpdate]
    let messages: [FirebaseManager.PatrolMessage]
    @Binding var draftText: String
    // PTT removed: UI flags for push-to-talk removed
    let onClose: () -> Void
    let onJoinRequested: (FirebaseManager.PatrolSchedule.PatrolScheduleType?) -> Void
    let onActivate: () -> Void
    let onComplete: () -> Void
    let onCancelPatrol: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    // PTT removed: callbacks deprecated
    let onSendText: () -> Void
    let onSendQuickAction: (String) -> Void

    @State private var selectedSection: WorkspaceSection = .overview
    @State private var showFullMap = false
    @State private var showMapSectionFullScreen = false
    @State private var showCommsSectionFullScreen = false
    @State private var pinAddresses: [String: String] = [:]
    @Environment(\.colorScheme) private var colorScheme
    @State private var showReminderAlert = false
    @State private var lastReminderMinute = 0
    @State private var reminderTimer: Timer?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -33.9249, longitude: 18.4241),
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    )
    @State private var hasInitializedMapRegion = false
    
    @State private var showJoinPatrolTypeDialog = false
    @StateObject private var localLocationPublisher = PatrolLocationPublisher()

    private var sortedLocations: [FirebaseManager.PatrolLocationUpdate] {
        liveLocations.sorted {
            ($0.updatedAt ?? $0.timestamp ?? .distantPast) > ($1.updatedAt ?? $1.timestamp ?? .distantPast)
        }
    }

    private var sortedMessages: [FirebaseManager.PatrolMessage] {
        messages.sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    private var mapPins: [PatrolMapPin] {
        guard schedule.status == .active else {
            return []
        }

        // Show all live locations published to this patrol's path, regardless of volunteer array matching.
        // This prevents cross-platform schema mismatches from hiding active Android users.
        let volunteerLocations = sortedLocations.filter { loc in
            return !loc.userId.isEmpty
        }

        var pins = volunteerLocations.map { item -> PatrolMapPin in
            let status = freshness(for: item)
            let memberName = item.displayName?.isEmpty == false ? item.displayName ?? "Patrol" : "Patrol"
            let initials = initialsForName(memberName)
            return PatrolMapPin(
                id: item.id,
                userId: item.userId,
                latitude: item.latitude,
                longitude: item.longitude,
                name: memberName,
                initials: initials,
                freshnessLabel: status.label,
                freshnessColor: status.color,
                isCurrentUser: false
            )
        }

        if let currentUserId = currentUserId {
            pins.removeAll { $0.userId == currentUserId }
        }

        // Only show the current user's live pin if they have joined the patrol.
        if hasJoined, let localLocation = localLocationPublisher.latestLocation {
            pins.append(
                PatrolMapPin(
                    id: "current-user-live-pin",
                    userId: currentUserId,
                    latitude: localLocation.coordinate.latitude,
                    longitude: localLocation.coordinate.longitude,
                    name: "You (Live)",
                    initials: initialsForName(displayName),
                    freshnessLabel: "Live",
                    freshnessColor: .blue,
                    isCurrentUser: true
                )
            )
        }

        return pins
    }

    private var hasJoined: Bool {
        guard let currentUserId else { return false }
        return schedule.volunteerUserIDs.contains(currentUserId)
    }

    // PTT removed: UI card omitted
    // (kept single placeholder)

    private var displayName: String {
        let creator = [schedule.creatorName, schedule.creatorSurname]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")
        return creator.isEmpty ? schedule.title : creator
    }

    private func patrolTypeLabel(for userId: String) -> String? {
        let rawType = schedule.volunteerPatrolTypes[userId]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawType.isEmpty else { return nil }
        if let resolved = FirebaseManager.PatrolSchedule.PatrolScheduleType(rawValue: rawType) {
            return resolved.displayName
        }
        return rawType.capitalized
    }

    private var activeStartDate: Date? {
        if let explicitStart = schedule.patrolStartedAt {
            return explicitStart
        }
        if schedule.status == .active {
            return schedule.startTime
        }
        return nil
    }

    private var clampedCellularMinutes: Int {
        max(0, min(10, cellularPublishIntervalMinutes))
    }

    private var cellularIntervalLabel: String {
        if clampedCellularMinutes == 0 { return "Real-time" }
        return "Every \(clampedCellularMinutes) min"
    }

    private var typeIcon: String {
        switch schedule.scheduleType {
        case .walking: return "figure.walk"
        case .driving: return "car.fill"
        case .camera: return "camera.fill"
        }
    }

    private var statusTint: Color {
        switch schedule.status {
        case .draft: return Color.gray
        case .scheduled: return Color.blue
        case .active: return Color.green
        case .completed: return Color.secondary
        case .cancelled: return Color.red
        }
    }

    private var isCreator: Bool {
        guard let currentUserId else { return false }
        return schedule.userId == currentUserId
    }

    private var canEdit: Bool {
        guard let currentUserId else { return false }
        return isAdmin || schedule.userId == currentUserId
    }

    private var canJoin: Bool {
        !schedule.isFull || hasJoined
    }

    private var canToggleJoinByStatus: Bool {
        switch schedule.status {
        case .draft, .scheduled, .active:
            return true
        case .completed, .cancelled:
            return false
        }
    }

    private func elapsedTimeText(at now: Date) -> String {
        guard let start = activeStartDate else { return "00:00:00" }
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private var panelBackground: Color {
        if colorScheme == .dark {
            return Color(red: 0.11, green: 0.15, blue: 0.22).opacity(0.94)
        }
        return Color.white.opacity(0.94)
    }

    private var panelBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.10)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.88) : Color(.secondaryLabel)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(.label)
    }

    private func freshness(for item: FirebaseManager.PatrolLocationUpdate) -> (label: String, color: Color) {
        guard let timestamp = item.updatedAt ?? item.timestamp else {
            return ("Unknown", .gray)
        }
        let age = Date().timeIntervalSince(timestamp)
        if age <= 45 { return ("Fresh", .green) }
        if age <= 120 { return ("Aging", .orange) }
        return ("Stale", .red)
    }

    private func initialsForName(_ fullName: String) -> String {
        let components = fullName
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let letters = components
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0).uppercased() }
        if letters.isEmpty {
            return String(fullName.prefix(1)).uppercased()
        }
        return letters.joined()
    }

    private func recenterIfNeeded() {
        guard !mapPins.isEmpty else { return }
        let latitudes = mapPins.map { $0.latitude }
        let longitudes = mapPins.map { $0.longitude }
        guard
            let minLat = latitudes.min(),
            let maxLat = latitudes.max(),
            let minLon = longitudes.min(),
            let maxLon = longitudes.max()
        else { return }

        mapRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.7, 0.01),
                longitudeDelta: max((maxLon - minLon) * 1.7, 0.01)
            )
        )
    }

    private func centerOnCurrentUser() {
        if let localLocation = localLocationPublisher.latestLocation {
            mapRegion = MKCoordinateRegion(
                center: localLocation.coordinate,
                span: regionSpan(for: 3000)
            )
        } else {
            recenterIfNeeded()
        }
        hasInitializedMapRegion = true
    }

    private func prepareMapRegionForDisplay() {
        guard !mapPins.isEmpty else {
            centerOnCurrentUser()
            return
        }

        let latitudes = mapPins.map { $0.latitude }
        let longitudes = mapPins.map { $0.longitude }
        guard
            let minLat = latitudes.min(),
            let maxLat = latitudes.max(),
            let minLon = longitudes.min(),
            let maxLon = longitudes.max()
        else {
            centerOnCurrentUser()
            return
        }

        mapRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
            )
        )
        hasInitializedMapRegion = true
    }

    private func fitMapToAllPins() {
        prepareMapRegionForDisplay()
    }

    private func openFullScreenMap() {
        centerOnCurrentUser()
        showFullMap = true
    }

    private func refreshPinAddresses() {
        for pin in mapPins {
            if pinAddresses[pin.id] != nil { continue }

            let location = CLLocation(latitude: pin.latitude, longitude: pin.longitude)
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                let resolved = placemarks?.first.flatMap { placemark in
                    let streetNumber = placemark.subThoroughfare ?? ""
                    let streetName = placemark.thoroughfare ?? ""
                    let suburb = placemark.subLocality ?? placemark.locality ?? ""
                    let city = placemark.locality ?? ""

                    let street = [streetNumber, streetName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    let area = [suburb, city]
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")

                    let full = [street, area]
                        .filter { !$0.isEmpty }
                        .joined(separator: " - ")
                    return full.isEmpty ? nil : full
                } ?? "Address unavailable"

                DispatchQueue.main.async {
                    pinAddresses[pin.id] = resolved
                }
            }
        }
    }

    private func displayAddress(for pin: PatrolMapPin) -> String {
        pinAddresses[pin.id] ?? "Resolving address..."
    }

    private func regionSpan(for radiusMeters: CLLocationDistance) -> MKCoordinateSpan {
        let delta = max(radiusMeters / 111_000.0, 0.02)
        return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
    }

    private func handleJoinOrLeaveTapped() {
        if hasJoined {
            onJoinRequested(nil)
            return
        }
        showJoinPatrolTypeDialog = true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                let bgColors = colorScheme == .dark
                    ? [
                        Color(red: 0.03, green: 0.05, blue: 0.09),
                        Color(red: 0.08, green: 0.13, blue: 0.20),
                        Color(red: 0.02, green: 0.04, blue: 0.08),
                    ]
                    : [
                        Color(.systemBackground),
                        Color(.secondarySystemBackground),
                        Color(.systemBackground)
                    ]

                LinearGradient(
                    colors: bgColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerCard

                        Picker("Patrol section", selection: $selectedSection) {
                            ForEach(WorkspaceSection.allCases) { section in
                                Text(section.rawValue).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(.white)

                        switch selectedSection {
                        case .overview:
                            actionCard
                        case .comms:
                            commsCard(compact: true)
                        // PTT removed
                        case .map:
                            actionCard
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
            .alert("Patrol reminder", isPresented: $showReminderAlert) {
                Button("Stay on Patrol", role: .cancel) {
                    showReminderAlert = false
                }
                Button("Leave Patrol") {
                    showReminderAlert = false
                    onJoinRequested(nil)
                }
            } message: {
                Text("This patrol has been active for 45 minutes or more. Keep going or leave the patrol now.")
            }
            .confirmationDialog(
                "Select Your Patrol Type",
                isPresented: $showJoinPatrolTypeDialog,
                titleVisibility: .visible
            ) {
                ForEach(FirebaseManager.PatrolSchedule.PatrolScheduleType.allCases, id: \.self) { type in
                    Button(type.displayName) {
                        onJoinRequested(type)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how you will join this patrol.")
            }
            .onAppear {
                if hasJoined {
                    localLocationPublisher.startPublishing()
                }
                centerOnCurrentUser()
                refreshPinAddresses()
                startReminderTimer()
            }
            .onChange(of: hasJoined) { joined in
                if joined {
                    localLocationPublisher.startPublishing()
                    centerOnCurrentUser()
                } else {
                    localLocationPublisher.stopPublishing()
                }
            }
            .onChange(of: localLocationPublisher.latestLocation) { newLocation in
                guard !hasInitializedMapRegion, newLocation != nil else { return }
                centerOnCurrentUser()
            }
            .onChange(of: mapPins) { _ in
                refreshPinAddresses()
            }
            .onChange(of: selectedSection) { newSection in
                switch newSection {
                case .map:
                    centerOnCurrentUser()
                    selectedSection = .overview
                    showMapSectionFullScreen = true
                case .comms:
                    break
                case .overview:
                    break
                }
            }
            .onDisappear {
                stopReminderTimer()
                localLocationPublisher.stopPublishing()
                onClose()
            }
            .fullScreenCover(isPresented: $showFullMap) {
                FullScreenPatrolMapView(
                    mapRegion: $mapRegion,
                    pins: mapPins,
                    isUsingCellularData: isUsingCellularData,
                    cellularIntervalMinutes: clampedCellularMinutes,
                    lastPublishAt: lastPublishAt,
                    onClose: { showFullMap = false }
                )
            }
            .fullScreenCover(isPresented: $showMapSectionFullScreen) {
                FullScreenPatrolMapView(
                    mapRegion: $mapRegion,
                    pins: mapPins,
                    isUsingCellularData: isUsingCellularData,
                    cellularIntervalMinutes: clampedCellularMinutes,
                    lastPublishAt: lastPublishAt
                ) {
                    showMapSectionFullScreen = false
                    selectedSection = .overview
                }
            }
            .fullScreenCover(isPresented: $showCommsSectionFullScreen) {
                PatrolSectionFullScreenPage(title: "Comms") {
                    showCommsSectionFullScreen = false
                    selectedSection = .overview
                } content: {
                    commsCard()
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Patrol Overview")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(colorScheme == .dark ? .cyan : .blue)
                    Text(schedule.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(primaryText)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(primaryText)
                        .frame(width: 40, height: 40)
                        .background(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                        .clipShape(Circle())
                }
            }

            HStack(spacing: 8) {
                statChip(title: "Type", value: schedule.scheduleType.displayName)
                statChip(title: "Status", value: schedule.status.displayName)
                statChip(title: "Volunteers", value: "\(schedule.volunteerCount)/\(schedule.maxVolunteers)")
            }

            // Show organizer and volunteers
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Patrol Window")
                        .font(.caption2)
                        .foregroundColor(secondaryText)
                    Text("\(schedule.startTime, style: .time) - \(schedule.endTime, style: .time)")
                        .font(.subheadline)
                        .foregroundColor(primaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Patrol Type")
                        .font(.caption2)
                        .foregroundColor(secondaryText)
                    HStack(spacing: 6) {
                        Image(systemName: typeIcon)
                            .foregroundColor(primaryText)
                        Text(schedule.scheduleType.displayName)
                            .font(.subheadline)
                            .foregroundColor(primaryText)
                    }
                }
            }

            if !schedule.volunteerNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(schedule.volunteerNames.indices, id: \.self) { idx in
                            let name = schedule.volunteerNames[idx]
                            let volunteerType = idx < schedule.volunteerUserIDs.count
                                ? patrolTypeLabel(for: schedule.volunteerUserIDs[idx])
                                : nil
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Text(initialsForName(name))
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    )
                                Text(name)
                                    .font(.caption)
                                    .foregroundColor(secondaryText)

                                if let volunteerType {
                                    Text("(\(volunteerType))")
                                        .font(.caption2)
                                        .foregroundColor(secondaryText)
                                }
                            }
                            .padding(8)
                            .background(panelBackground.opacity(0.85))
                            .cornerRadius(12)
                        }
                    }
                }
            }

            if let meetingPoint = schedule.meetingPoint, !meetingPoint.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.cyan)
                    Text(meetingPoint)
                        .font(.subheadline)
                        .foregroundColor(primaryText)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.cyan)
                Text("\(schedule.startTime, style: .time) - \(schedule.endTime, style: .time)")
                    .font(.subheadline)
                    .foregroundColor(primaryText)
            }

            if let startedAt = schedule.patrolStartedAt {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.green)
                    Text("Started: \(startedAt, style: .time)")
                        .font(.subheadline)
                        .foregroundColor(primaryText)
                    Spacer()
                    if !schedule.userId.isEmpty {
                        Text("Active patrol")
                            .font(.caption)
                            .foregroundColor(secondaryText)
                    }
                }
            }

            if schedule.status == .active, activeStartDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .foregroundColor(.green)
                        Text("Patrol Timer")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(secondaryText)
                        Spacer()
                        Text(elapsedTimeText(at: context.date))
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.14))
                    .cornerRadius(12)
                }
            }

            HStack(spacing: 8) {
                Text(schedule.status.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.22))
                    .foregroundColor(colorScheme == .dark ? .white : Color(.label))
                    .cornerRadius(10)

                Text(hasJoined ? "You are on this patrol" : "Tap join to enter the patrol")
                    .font(.caption)
                    .foregroundColor(secondaryText)
                Spacer()

                if !hasJoined && canJoin && canToggleJoinByStatus {
                    Button("Choose Patrol Type") {
                        showJoinPatrolTypeDialog = true
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.16))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(panelBorder, lineWidth: 1)
        )
        .cornerRadius(24)
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Patrol Controls")
                .font(.headline)
                .foregroundColor(primaryText)
            Text("Use the quick actions below to keep the patrol moving and stay in touch with your team.")
                .font(.caption)
                .foregroundColor(secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mobile Data Update Rate")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(secondaryText)
                    Spacer()
                    Text(cellularIntervalLabel)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(primaryText)
                }

                Slider(
                    value: Binding(
                        get: { Double(clampedCellularMinutes) },
                        set: { cellularPublishIntervalMinutes = Int($0.rounded()) }
                    ),
                    in: 0...10,
                    step: 1
                )
                .tint(.accentColor)

                Text(isUsingCellularData
                    ? "Mobile data is active now. Set 0 for real-time updates, or up to 10 minutes between sends."
                    : "Choose the mobile data cadence before you leave Wi-Fi. This setting applies automatically once cellular is active.")
                    .font(.caption2)
                    .foregroundColor(secondaryText)
            }
            .padding(10)
            .background(panelBackground.opacity(0.72))
            .cornerRadius(12)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if isCreator && schedule.status == .scheduled {
                    Button("Start Patrol") { onActivate() }
                        .patrolActionStyle(fill: Color.green)
                }

                Button(hasJoined ? "Leave Patrol" : "Join Patrol") { handleJoinOrLeaveTapped() }
                    .disabled(!canJoin || !canToggleJoinByStatus)
                    .patrolActionStyle(fill: hasJoined ? Color.orange : Color.green)

                // Push-to-Talk removed
                    .patrolActionStyle(fill: Color.indigo)

                if canEdit {
                    Button("Edit") { onEdit() }
                        .patrolActionStyle(fill: Color.blue)
                    if schedule.status != .active {
                        Button("Delete") { onDelete() }
                            .patrolActionStyle(fill: Color.red)
                    }
                }
            }

            if let notes = schedule.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(panelBorder, lineWidth: 1)
        )
        .cornerRadius(22)
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live GPS")
                .font(.headline)
                .foregroundColor(primaryText)

            VStack(alignment: .leading, spacing: 12) {
                Button(action: openFullScreenMap) {
                    Label("Full Screen", systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.06))
                        .cornerRadius(12)
                }

                Map(coordinateRegion: $mapRegion, annotationItems: mapPins) { item in
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)) {
                    VStack(spacing: 6) {
                        if item.isCurrentUser {
                            Image(systemName: "location.north.fill")
                                .font(.title2)
                                .foregroundColor(item.freshnessColor ?? .blue)
                                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
                        } else {
                            ZStack {
                                Circle()
                                    .fill(item.freshnessColor ?? .gray)
                                    .frame(width: 38, height: 38)
                                    .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
                                Text(item.initials)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        }

                        VStack(spacing: 2) {
                            Text(item.name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(6)

                            if item.isCurrentUser {
                                if isUsingCellularData && clampedCellularMinutes > 0 {
                                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                        let interval = TimeInterval(clampedCellularMinutes * 60)
                                        let elapsed = Date().timeIntervalSince(lastPublishAt)
                                        let remaining = max(0, Int(interval - elapsed))
                                        Text("Next: \(remaining)s")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                } else {
                                    Text("Live")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 320)
            .cornerRadius(18)

            if mapPins.isEmpty {
                Text("No live patrol locations yet. Join and enable location sharing to populate the map.")
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panelBackground.opacity(0.85))
                    .cornerRadius(14)
            } else {
                VStack(spacing: 8) {
                    ForEach(mapPins) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(primaryText)
                                Text(displayAddress(for: item))
                                    .font(.caption)
                                    .foregroundColor(secondaryText)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(item.freshnessLabel ?? "Unknown")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(item.freshnessColor ?? .gray)
                        }
                        .padding(10)
                        .background(panelBackground.opacity(0.85))
                        .cornerRadius(12)
                    }
                }
            }

            // Show volunteer roster and live status
            if !schedule.volunteerUserIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Volunteers")
                        .font(.subheadline)
                        .foregroundColor(primaryText)

                    ForEach(Array(zip(schedule.volunteerUserIDs, schedule.volunteerNames)), id: \.0) { uid, name in
                        HStack {
                            HStack(spacing: 4) {
                                Text(name)
                                    .font(.caption)
                                    .foregroundColor(secondaryText)
                                if let volunteerType = patrolTypeLabel(for: uid) {
                                    Text("(\(volunteerType))")
                                        .font(.caption2)
                                        .foregroundColor(secondaryText)
                                }
                            }
                            Spacer()
                            if mapPins.contains(where: { $0.userId == uid }) {
                                Text("Live")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            } else {
                                Text("No location")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(panelBackground.opacity(0.85))
                        .cornerRadius(10)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(panelBorder, lineWidth: 1)
        )
        .cornerRadius(22)
    }
    }

    private func commsCard(compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comms")
                    .font(.headline)
                    .foregroundColor(primaryText)
                Spacer()
                if compact {
                    Button("Open Full Screen") {
                        showCommsSectionFullScreen = true
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack(spacing: 8) {
                Button("Check-in") { onSendQuickAction("✅ Check-in: Patrol member is safe and active.") }
                    .patrolMiniActionStyle()
                Button("Backup") { onSendQuickAction("⚠️ Need backup at my current patrol position.") }
                    .patrolMiniActionStyle()
                Button("Clear") { onSendQuickAction("🟢 All clear in current zone.") }
                    .patrolMiniActionStyle()
            }

            if sortedMessages.isEmpty {
                Text("No patrol messages yet.")
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(panelBackground.opacity(0.85))
                    .cornerRadius(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedMessages) { msg in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(msg.senderName?.isEmpty == false ? msg.senderName ?? "Patrol" : "Patrol")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(primaryText)
                                    Spacer()
                                    if let createdAt = msg.createdAt {
                                        Text(createdAt, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(secondaryText)
                                    }
                                }
                                Text(msg.text)
                                    .font(msg.messageType == "system" ? .caption : .subheadline)
                                    .foregroundColor(msg.messageType == "system" ? secondaryText : primaryText)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(msg.messageType == "system" ? Color.orange.opacity(0.20) : panelBackground.opacity(0.88))
                            .cornerRadius(12)
                        }
                    }
                }
                .frame(maxHeight: compact ? 180 : 280)
            }

            HStack(spacing: 8) {
                TextField("Send patrol update", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                Button("Send") { onSendText() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(panelBorder, lineWidth: 1)
        )
        .cornerRadius(22)
    }

    // PTT removed: UI card omitted
    private var pttCard: some View { EmptyView() }

    private func startReminderTimer() {
        stopReminderTimer()
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            guard schedule.status == .active, hasJoined, let start = activeStartDate else { return }
            let elapsedMinutes = Int(floor(Date().timeIntervalSince(start) / 60.0))
            // Only fire once the patrol has genuinely been active for 45+ minutes,
            // then repeat every 15 minutes (60, 75, …). The previous max(45,…) formula
            // evaluated to 45 on the very first tick (minute 1), causing an instant alert.
            guard elapsedMinutes >= 45 else { return }
            let reminderWindow = (elapsedMinutes / 15) * 15

            DispatchQueue.main.async {
                if reminderWindow != self.lastReminderMinute {
                    self.lastReminderMinute = reminderWindow
                    self.showReminderAlert = true
                }
            }
        }
    }

    private func stopReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : Color(.secondaryLabel))
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(primaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

private struct FullScreenPatrolMapView: View {
    @Binding var mapRegion: MKCoordinateRegion
    let pins: [PatrolWorkspaceView.PatrolMapPin]
    let isUsingCellularData: Bool
    let cellularIntervalMinutes: Int
    let lastPublishAt: Date
    let onClose: () -> Void
    @State private var currentUserAddress: String = "Resolving address..."
    @State private var hasCenteredOnCurrentUser = false

    var body: some View {
        NavigationStack {
            ZStack {
                Map(coordinateRegion: $mapRegion, annotationItems: pins) { item in
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)) {
                        VStack(spacing: 6) {
                            if item.isCurrentUser {
                                Image(systemName: "location.north.fill")
                                    .font(.title)
                                    .foregroundColor(item.freshnessColor ?? .blue)
                            } else {
                                Circle()
                                    .fill(item.freshnessColor ?? .gray)
                                    .frame(width: 36, height: 36)
                                    .overlay(Text(item.initials).foregroundColor(.white).font(.caption2))
                            }

                            VStack(spacing: 2) {
                                Text(item.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)

                                if item.isCurrentUser {
                                    if isUsingCellularData && cellularIntervalMinutes > 0 {
                                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                                            let interval = TimeInterval(cellularIntervalMinutes * 60)
                                            let elapsed = Date().timeIntervalSince(lastPublishAt)
                                            let remaining = max(0, Int(interval - elapsed))
                                            Text("Timed: \(remaining)s")
                                                .font(.caption2)
                                                .foregroundColor(.white.opacity(0.85))
                                        }
                                    } else {
                                        Text("Live")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                } else {
                                    Text(item.freshnessLabel ?? "Unknown")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                        }
                    }
                }
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .padding(12)
                                .background(.thinMaterial)
                                .cornerRadius(10)
                        }
                    }
                    .padding()

                    Spacer()

                    HStack {
                        Image(systemName: "house.fill")
                            .foregroundColor(.white)
                        Text(currentUserAddress)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.72))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .onAppear {
                centerMapOnCurrentUserPin()
                resolveCurrentUserAddress()
            }
            .onChange(of: pins) { _ in
                resolveCurrentUserAddress()
            }
        }
    }

    private func centerMapOnCurrentUserPin() {
        guard !hasCenteredOnCurrentUser else { return }
        guard let currentPin = pins.first(where: { $0.isCurrentUser }) else { return }

        mapRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: currentPin.latitude, longitude: currentPin.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        hasCenteredOnCurrentUser = true
    }

    private func resolveCurrentUserAddress() {
        guard let currentPin = pins.first(where: { $0.isCurrentUser }) else {
            currentUserAddress = "Current address unavailable"
            return
        }

        let location = CLLocation(latitude: currentPin.latitude, longitude: currentPin.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let resolved = placemarks?.first.flatMap { placemark in
                let streetNumber = placemark.subThoroughfare ?? ""
                let streetName = placemark.thoroughfare ?? ""
                let suburb = placemark.subLocality ?? placemark.locality ?? ""
                let city = placemark.locality ?? ""

                let street = [streetNumber, streetName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let area = [suburb, city]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                let full = [street, area]
                    .filter { !$0.isEmpty }
                    .joined(separator: " - ")
                return full.isEmpty ? nil : full
            } ?? "Address unavailable"

            DispatchQueue.main.async {
                currentUserAddress = resolved
            }
        }
    }
}

private struct PatrolActionButtonStyle: ViewModifier {
    let fill: Color
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(colorScheme == .dark ? .white : Color(.label))
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(fill.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(fill.opacity(0.45), lineWidth: 1)
            )
            .cornerRadius(14)
    }
}

private struct PatrolSectionFullScreenPage<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                let bgColors = colorScheme == .dark
                    ? [
                        Color(red: 0.03, green: 0.05, blue: 0.09),
                        Color(red: 0.08, green: 0.13, blue: 0.20),
                        Color(red: 0.02, green: 0.04, blue: 0.08),
                    ]
                    : [
                        Color(.systemBackground),
                        Color(.secondarySystemBackground),
                        Color(.systemBackground)
                    ]

                LinearGradient(colors: bgColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        content
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onClose() }
                }
            }
        }
    }
}

private struct PatrolMiniActionButtonStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(colorScheme == .dark ? .white : Color(.label))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(10)
    }
}

private extension View {
    func patrolActionStyle(fill: Color) -> some View {
        modifier(PatrolActionButtonStyle(fill: fill))
    }

    func patrolMiniActionStyle() -> some View {
        modifier(PatrolMiniActionButtonStyle())
    }
}
