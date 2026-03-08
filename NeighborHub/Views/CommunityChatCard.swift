import AVFoundation
import AVKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

// Helper to get an SF Symbol for a file type
private func fileIcon(for fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.lowercased()
    switch ext {
    case "pdf": return "doc.richtext"
    case "jpg", "jpeg", "png", "gif", "heic": return "photo"
    case "doc", "docx": return "doc.text"
    case "xls", "xlsx": return "tablecells"
    case "ppt", "pptx": return "chart.bar"
    case "zip", "rar": return "archivebox"
    case "mp3", "wav", "m4a": return "music.note"
    case "mp4", "mov", "avi": return "film"
    case "txt": return "doc.plaintext"
    default: return "doc"
    }
}

// MARK: - Preview helpers
extension Notification.Name {
    static let attachmentCopyErrorNotification = Notification.Name(
        "attachmentCopyErrorNotification")
}

// Full screen image viewer with pinch-to-zoom
struct FullScreenImageView: View {
    let uiImage: UIImage
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width * scale)
                        .gesture(
                            MagnificationGesture().onChanged { v in
                                scale = v
                            })
                }
            }
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
}

// AVPlayerViewController wrapper for full screen videos
struct AVPlayerVC: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = true
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = false
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Ensure player is set and ready
        if uiViewController.player != player {
            uiViewController.player = player
        }
    }
}

// Helper to detect video file types from a URL
private func isVideoURL(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
}

// Firebase conditional import for Firestore usage
#if canImport(FirebaseFirestore)
    import FirebaseFirestore
#endif
// CommunityChatFeatures types are available in the same target

// Animation phases for different message states
enum AnimationPhase {
    case appearing, stable, editing, deleting, deleted
}

// MARK: - CommunityChatCard (Modern Chat Interface)
struct CommunityChatCard: View {
    // For jump-to-message from search
    @State private var scrollToMessageId: UUID?
    // State to track the height of the message input bar
    @State private var messageBarHeight: CGFloat = 0
    @StateObject private var keyboardManager = KeyboardManager.shared
    // State for showing enlarged image viewer
    @State private var showImageViewer = false
    // ...existing code...
    // Helper to trigger AI search input
    private func triggerAISearchInput() {
        isTextFieldFocused = true
        if !inputBinding.wrappedValue.hasPrefix("#") {
            inputBinding.wrappedValue = "#" + inputBinding.wrappedValue
        }
    }
    @State private var showSearchSubActions: Bool = false
    // State for pinned messages sheet
    @State private var showPinnedMessages: Bool = false
    @State private var showActionSheet: Bool = false
    @State private var showCustomActionsRow: Bool = false
    // User & Admin logic
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("committeeMembers") private var committeeMembers: String = ""
    @AppStorage("communityMessagesData") private var communityMessagesData: String = ""
    
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

    private var currentUserFullName: String {
        "\(userName) \(userSurname)".trimmingCharacters(in: .whitespaces)
    }

    // Chat state
    @State private var messageText: String = ""
    @State private var messages: [CommunityMessage] = []
    @State private var showingMessageOptions = false
    @State private var selectedMessage: CommunityMessage?
    @State private var isTyping = false
    @State private var showingChatSettings = false
    @State private var replyingToMessage: CommunityMessage?
    @State private var editingMessage: CommunityMessage?
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var highlightedMessageId: UUID?
    @State private var justAddedMessageId: UUID?
    @State private var deletingMessageId: UUID?
    @State private var editingAnimationId: UUID?
    @State private var shakingMessageId: UUID?
    @StateObject private var pinnedMessagesManager = PinnedMessagesManager()
    @StateObject private var aiSearchManager = AISearchManager()
    @StateObject private var chatManager = ChatMessagesManager()
    @State private var showBusinessSearchOverlay: Bool = false
    @State private var showMessageSearchOverlay: Bool = false
    @StateObject private var locationManager = LocationManager()

    // Business sharing
    @State private var sharedBusinessCards: [SharedBusinessCard] = []

    // Business Detail View Management
    @State private var selectedBusiness: LocalBusiness?
    @State private var showingBusinessDetail = false

    // Chat Settings
    @AppStorage("chatNotificationsEnabled") private var chatNotificationsEnabled: Bool = true
    @AppStorage("chatSoundEnabled") private var chatSoundEnabled: Bool = true
    @AppStorage("chatShowTimestamps") private var chatShowTimestamps: Bool = true
    @AppStorage("chatFontSize") private var chatFontSize: Double = 16.0
    @AppStorage("chatTheme") private var chatTheme: String = "auto"
    @AppStorage("chatBackgroundStyle") private var chatBackgroundStyle: String = "default"
    @AppStorage("chatAutoScroll") private var chatAutoScroll: Bool = true
    @AppStorage("chatShowTypingIndicators") private var chatShowTypingIndicators: Bool = true
    @AppStorage("showUserCredentials") private var showUserCredentials: Bool = true
    @AppStorage("communityGuidelines") private var communityGuidelines: String = ""
    @AppStorage("contentModerationEnabled") private var contentModerationEnabled: Bool = true
    @AppStorage("showModerationWarnings") private var showModerationWarnings: Bool = true

    // Computed property for appearance
    private var currentColorScheme: ColorScheme? {
        switch chatTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // Computed property for background
    private var chatBackgroundView: some View {
        Group {
            switch chatBackgroundStyle {
            case "blue":
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.25),
                        Color.blue.opacity(0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "green":
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.25),
                        Color.green.opacity(0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "purple":
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.25),
                        Color.purple.opacity(0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "orange":
                LinearGradient(
                    colors: [
                        Color.orange.opacity(0.25),
                        Color.orange.opacity(0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "sunset":
                LinearGradient(
                    colors: [
                        Color.orange.opacity(0.3),
                        Color.pink.opacity(0.2),
                        Color.purple.opacity(0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "ocean":
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.3),
                        Color.cyan.opacity(0.2),
                        Color.teal.opacity(0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "forest":
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.3),
                        Color.mint.opacity(0.2),
                        Color.teal.opacity(0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "warm":
                LinearGradient(
                    colors: [
                        Color.red.opacity(0.2),
                        Color.orange.opacity(0.15),
                        Color.yellow.opacity(0.1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "cool":
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.2),
                        Color.indigo.opacity(0.15),
                        Color.purple.opacity(0.1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "minimal":
                Color(.systemGray5).opacity(0.6)
            default:  // "default"
                Color(.systemBackground)
            }
        }
    }

    // Helper property for background style display name
    private var backgroundStyleDisplayName: String {
        switch chatBackgroundStyle {
        case "blue": return "Ocean Blue"
        case "green": return "Nature Green"
        case "purple": return "Royal Purple"
        case "orange": return "Warm Orange"
        case "sunset": return "Sunset Gradient"
        case "ocean": return "Ocean Waves"
        case "forest": return "Forest Breeze"
        case "warm": return "Warm Tones"
        case "cool": return "Cool Tones"
        case "minimal": return "Minimal Gray"
        default: return "Default"
        }
    }

    // Helper property for user initials (same as HomeView)
    private var initials: String {
        let first =
            userName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) } ?? ""
        let last =
            userSurname.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) }
            ?? ""
        return (first + last).uppercased()
    }

    // MARK: - Image Picker State
    @State private var showingImagePicker: Bool = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    @State private var capturedImage: UIImage? = nil
    @State private var showingPasteMenu: Bool = false
    @State private var showingFilePicker: Bool = false
    @State private var attachedFileURL: URL? = nil
    @State private var attachedFileName: String? = nil
    @State private var attachmentCopyErrorAlert: Bool = false
    @State private var messageBlockedAlert: Bool = false
    @State private var videoUploadErrorAlert: Bool = false
    @State private var videoUploadErrorMessage: String = ""
    @State private var attachmentCopyErrorMessage: String? = nil
    // Full screen attachment preview state
    private struct IdentifiableImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }
    @State private var fullScreenImageItem: IdentifiableImage? = nil
    // Video preview states
    @State private var fullScreenPlayer: AVPlayer? = nil
    @State private var popupVideoURL: URL? = nil
    @State private var popupGifURL: URL? = nil  // GIF preview state
    @State private var fullScreenURL: URL? = nil
    @State private var showingPopupVideo: Bool = false
    @State private var showingPopupGif: Bool = false  // GIF preview flag
    @State private var showingDocumentPreview: Bool = false
    // showClearStorageAlert removed (Clear App Storage UI removed)
    @State private var currentSearchQuery: String = ""
    @State private var highlightTimer: Timer?
    // Voice recording state
    @State private var isRecording: Bool = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingStartWorkItem: DispatchWorkItem? = nil
    @State private var recordingTimer: Timer? = nil
    @State private var voiceRecorder = VoiceRecorder()

    // Animation state variables
    @State private var animatingMessageIds = Set<UUID>()
    @State private var newMessageIds = Set<UUID>()
    @State private var editedMessageIds = Set<UUID>()
    @State private var deletedMessageIds = Set<UUID>()
    @State private var messageAnimationPhase: [UUID: AnimationPhase] = [:]

    // Typing indicator state
    @State private var typingUsers: Set<String> = []
    @State private var displayNamesCache: [String: String] = [:] // UID -> Display Name
    @State private var typingTimer: Timer?
    @State private var isShowingTypingIndicator: Bool = false

    var body: some View {
        ZStack {
            // Background that matches HomeView pattern
            chatBackgroundView.ignoresSafeArea()

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    ScrollViewReader { proxy in
                        // compute bottom padding in a simple expression to reduce compiler type-check complexity
                        let bottomPadding =
                            messageBarHeight + keyboardManager.keyboardHeight
                            + geometry.safeAreaInsets.bottom + 8
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                // Messages List
                                messagesView

                                // Invisible anchor for last message (for precise scroll)
                                if !messages.isEmpty {
                                    Color.clear
                                        .frame(height: 1)
                                        .id("lastMessageAnchor")
                                }
                            }
                            .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 16)
                            .padding(.top, 8)
                            .padding(.bottom, bottomPadding)  // Add keyboard height to bottom padding
                        }
                        .onAppear {
                            // Always scroll to last message anchor on appear
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation {
                                    proxy.scrollTo("lastMessageAnchor", anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: messages.count) { _, _ in
                            // Scroll to last message when a new message is sent/received
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo("lastMessageAnchor", anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: scrollToMessageId) { _, newId in
                            if let id = newId {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                                // Clear after scroll
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scrollToMessageId = nil
                                }
                            }
                        }
                    }
                    // Overlay action buttons at the bottom right, just above the message bar
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            if showCustomActionsRow {
                                VStack(spacing: 8) {
                                    ActionCircleButton(
                                        icon: "pin.circle", color: .purple, label: ""
                                    ) {
                                        showPinnedMessages = true
                                        showCustomActionsRow = false
                                    }
                                    ZStack {
                                        VStack(spacing: 12) {
                                            if showSearchSubActions {
                                                ActionCircleButton(
                                                    icon: "text.magnifyingglass", color: .blue,
                                                    label: ""
                                                ) {
                                                    triggerAISearchInput()
                                                    showSearchSubActions = false
                                                    showCustomActionsRow = false
                                                }
                                                ActionCircleButton(
                                                    icon: "building.2.crop.circle", color: .teal,
                                                    label: ""
                                                ) {
                                                    // Always show the business search overlay, even if input is empty
                                                    let query = messageText.trimmingCharacters(
                                                        in: .whitespacesAndNewlines)
                                                    aiSearchManager.searchBusinesses(
                                                        query: query.isEmpty ? " " : query,
                                                        in: messages)
                                                    showBusinessSearchOverlay = true
                                                    isTextFieldFocused = false
                                                    showSearchSubActions = false
                                                    showCustomActionsRow = false
                                                }
                                            }
                                            ActionCircleButton(
                                                icon: "magnifyingglass.circle", color: .blue,
                                                label: ""
                                            ) {
                                                withAnimation {
                                                    showSearchSubActions.toggle()
                                                }
                                            }
                                        }
                                    }
                                    // Removed: mark-as-read, mute, and export actions per request
                                    // Camera button moved to the bottom
                                    ActionCircleButton(icon: "camera.fill", color: .blue, label: "")
                                    {
                                        showImagePicker(sourceType: .camera)
                                        showCustomActionsRow = false
                                    }
                                    // Attachment button (photo or file)
                                    AttachmentActionButton {
                                        // Present attachment options (photo/camera/file/paste)
                                        showActionSheet = true
                                        showCustomActionsRow = false
                                    }
                                    // Voice note button (start/stop recording)
                                    ActionCircleButton(
                                        icon: "mic.fill", color: .red,
                                        label: isRecording ? "Stop" : "",
                                        action: {
                                            // Toggle recording: start if not recording, stop+send if recording
                                            if isRecording {
                                                // stop recording and send, then hide the actions row
                                                isRecording = false
                                                recordingTimer?.invalidate()
                                                recordingTimer = nil
                                                voiceRecorder.stopRecording()
                                                if let audioURL = voiceRecorder.audioURL,
                                                    let data = try? Data(contentsOf: audioURL)
                                                {
                                                    sendAudioMessage(
                                                        audioData: data,
                                                        fileName: audioURL.lastPathComponent)
                                                }
                                                // After stopping, collapse the custom actions for a cleaner UI
                                                showCustomActionsRow = false
                                            } else {
                                                // start recording immediately and keep the actions row open so the mic remains tappable to stop
                                                isRecording = true
                                                recordingDuration = 0
                                                let filename = "voice-\(UUID().uuidString).m4a"
                                                let url = FileManager.default.temporaryDirectory
                                                    .appendingPathComponent(filename)
                                                voiceRecorder = VoiceRecorder()
                                                do {
                                                    try voiceRecorder.startRecording(to: url)
                                                    recordingTimer?.invalidate()
                                                    recordingTimer = Timer.scheduledTimer(
                                                        withTimeInterval: 0.5, repeats: true
                                                    ) { _ in
                                                        recordingDuration += 0.5
                                                    }
                                                } catch {
                                                    // on failure, stop recording state and hide the actions row
                                                    isRecording = false
                                                    recordingTimer?.invalidate()
                                                    recordingTimer = nil
                                                    showCustomActionsRow = false
                                                }
                                            }
                                        }, isActive: isRecording, activeColor: .red)
                                }
                                .padding(
                                    .bottom, messageBarHeight + geometry.safeAreaInsets.bottom + 20
                                )
                                .padding(.trailing, 18)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                }
            }

            // Floating # Search Results popup overlayed above the message bar
            // Show business search overlay if active
            if showBusinessSearchOverlay {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack(alignment: .topTrailing) {
                            AISearchResultsView(
                                searchManager: aiSearchManager,
                                onMessageTap: { message in
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        highlightedMessageId = message.id
                                    }
                                    aiSearchManager.clearSearch()
                                    isTextFieldFocused = false
                                    messageText = ""
                                    showBusinessSearchOverlay = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            highlightedMessageId = nil
                                        }
                                    }
                                },
                                onBusinessTap: { business in
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    selectedBusiness = business
                                    showingBusinessDetail = true
                                },
                                onBusinessShare: { business in
                                    shareBusinessToChat(business)
                                },
                                onSendMessageToChat: { text in
                                    sendSharedResultsToChat(text)
                                },
                                onSendBusinessListToChat: { businesses in
                                    sendBusinessListToChat(businesses)
                                },
                                onJumpToMessage: { messageId in
                                    scrollToMessageId = messageId
                                    aiSearchManager.clearSearch()
                                    isTextFieldFocused = false
                                    showBusinessSearchOverlay = false
                                }
                            )
                            Button(action: {
                                withAnimation {
                                    showBusinessSearchOverlay = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary)
                                    .padding(12)
                            }
                            .accessibilityLabel("Close Business Search")
                        }
                        .frame(maxWidth: 420)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.red, lineWidth: 2)
                                )
                        )
                        .padding(.bottom, 80)
                        .padding(.horizontal, 12)
                        Spacer()
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }

            // Show message search overlay if active
            if showMessageSearchOverlay {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack(alignment: .topTrailing) {
                            AISearchResultsView(
                                searchManager: aiSearchManager,
                                onMessageTap: { message in
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        highlightedMessageId = message.id
                                    }
                                    aiSearchManager.clearSearch()
                                    isTextFieldFocused = false
                                    messageText = ""
                                    showMessageSearchOverlay = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            highlightedMessageId = nil
                                        }
                                    }
                                },
                                onBusinessTap: nil,
                                onBusinessShare: nil,
                                onSendMessageToChat: nil,
                                onSendBusinessListToChat: nil,
                                onJumpToMessage: { messageId in
                                    scrollToMessageId = messageId
                                    aiSearchManager.clearSearch()
                                    isTextFieldFocused = false
                                    showMessageSearchOverlay = false
                                }
                            )
                            Button(action: {
                                withAnimation {
                                    showMessageSearchOverlay = false
                                    aiSearchManager.clearSearch()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary)
                                    .padding(12)
                            }
                            .accessibilityLabel("Close Message Search")
                        }
                        .frame(maxWidth: 420)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.blue, lineWidth: 2)
                                )
                        )
                        .padding(.bottom, 80)
                        .padding(.horizontal, 12)
                        Spacer()
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(11)
            }

            // Message Input fixed at bottom, with typing indicator above it
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    if chatShowTypingIndicators {
                        typingIndicator
                    }
                    // Measure the height of the message input view
                    ZStack(alignment: .bottom) {
                        messageInputView
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .onAppear {
                                            messageBarHeight = proxy.size.height
                                        }
                                        .onChange(of: proxy.size.height) { _, newHeight in
                                            messageBarHeight = newHeight
                                        }
                                }
                            )
                    }
                }
            }
        }
        .navigationTitle("NeighbourHUB Chat")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Settings avatar button (trailing)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingChatSettings = true }) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.accentColor.opacity(0.25), radius: 8, x: 0, y: 4)
                        Text(initials)
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                }
                .accessibilityLabel("Chat Settings")
            }
        }
        .preferredColorScheme(currentColorScheme)
        .onTapGesture {
            isTextFieldFocused = false
            // Dismiss message options if tapping elsewhere
            if highlightedMessageId != nil {
                withAnimation(.easeInOut(duration: 0.3)) {
                    highlightedMessageId = nil
                    showingMessageOptions = false
                    selectedMessage = nil
                }
            }
        }
        .onAppear {
            // Track screen view
            AnalyticsService.shared.trackScreenView("CommunityChat")
            // Initialize local UI state
            loadMessages()
            addWelcomeMessagesIfNeeded()
            initializeCommunityGuidelines()

            // Set up location manager for business search
            aiSearchManager.setLocationManager(locationManager)

            // Start listening for typing status from other users
            startTypingStatusListener()

            // Observe attachment copy errors posted from nested views
            NotificationCenter.default.addObserver(
                forName: .attachmentCopyErrorNotification, object: nil, queue: .main
            ) { note in
                if let msg = note.object as? String {
                    attachmentCopyErrorMessage = msg
                    attachmentCopyErrorAlert = true
                }
            }
            
            // Observe video upload errors
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("VideoUploadError"), object: nil, queue: .main
            ) { note in
                if let msg = note.object as? String {
                    videoUploadErrorMessage = msg
                    videoUploadErrorAlert = true
                }
            }
        }

        // Update local messages whenever the manager publishes changes
        .onReceive(chatManager.$messages) { newMessages in
            // Track animation for new, edited, and deleted messages
            let oldMessageIds = Set(self.messages.map { $0.id })
            let newMessageIds = Set(newMessages.map { $0.id })

            // Detect new messages
            let addedIds = newMessageIds.subtracting(oldMessageIds)
            for id in addedIds {
                messageAnimationPhase[id] = .appearing

                // Start appearing animation
                _ = withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.3))
                {
                    animatingMessageIds.insert(id)
                }

                // Set to stable after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        messageAnimationPhase[id] = .stable
                        animatingMessageIds.remove(id)
                    }
                }
            }

            // Detect edited messages (compare timestamps)
            let oldMessages = Dictionary(uniqueKeysWithValues: self.messages.map { ($0.id, $0) })
            for newMessage in newMessages {
                if let oldMessage = oldMessages[newMessage.id],
                    newMessage.isEdited && !oldMessage.isEdited
                {
                    // Message was edited
                    messageAnimationPhase[newMessage.id] = .editing

                    _ = withAnimation(.easeInOut(duration: 0.4)) {
                        editedMessageIds.insert(newMessage.id)
                    }

                    // Return to stable after edit animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            messageAnimationPhase[newMessage.id] = .stable
                            editedMessageIds.remove(newMessage.id)
                        }
                    }
                }
            }

            // Update local messages from manager
            self.messages = newMessages
        }
        .onDisappear {
            // Stop broadcasting typing status when leaving chat
            stopTypingStatusListener()
        }
        .sheet(isPresented: $showingChatSettings) {
            chatSettingsSheet
        }
        .sheet(isPresented: $showingBusinessDetail) {
            if let business = selectedBusiness {
                BusinessDetailView(business: business) { business in
                    shareBusinessToChat(business)
                }
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
            }
        }
        // Clear App Storage alert removed
        .overlay(
            // Message options overlay
            messageOptionsOverlay
        )
        // Camera image picker sheet (supports photos and video capture)
        .sheet(isPresented: $showingImagePicker) {
            ChatImagePicker(sourceType: imagePickerSourceType) { media in
                defer { showingImagePicker = false }
                guard let media = media else { return }

                switch media {
                case .image(let image):
                    capturedImage = image

                case .video(let url):
                    // Copy captured video into Documents/Attachments to match document picker behavior
                    let fm = FileManager.default
                    let docs =
                        fm.urls(for: .documentDirectory, in: .userDomainMask).first
                        ?? fm.temporaryDirectory
                    let attachmentsDir = docs.appendingPathComponent(
                        "Attachments", isDirectory: true)
                    do {
                        try fm.createDirectory(
                            at: attachmentsDir, withIntermediateDirectories: true)
                    } catch {
                        attachmentCopyErrorMessage =
                            "Failed to create attachments directory: \(error.localizedDescription)"
                        attachmentCopyErrorAlert = true
                        return
                    }

                    // Reject very large videos to avoid excessive storage and uploads
                    do {
                        let attrs = try fm.attributesOfItem(atPath: url.path)
                        if let size = attrs[.size] as? NSNumber {
                            let bytes = size.int64Value
                            let maxBytes: Int64 = 50 * 1024 * 1024  // 50 MB
                            if bytes > maxBytes {
                                attachmentCopyErrorMessage =
                                    "Selected video is too large (over 50 MB). Please choose a smaller file."
                                attachmentCopyErrorAlert = true
                                return
                            }
                        }
                    } catch {
                        // If we can't read attributes, continue and try copy; fail will be reported
                    }

                    let dest = attachmentsDir.appendingPathComponent(
                        "\(UUID().uuidString)-\(url.lastPathComponent)")
                    do {
                        if fm.fileExists(atPath: dest.path) {
                            try fm.removeItem(at: dest)
                        }
                        try fm.copyItem(at: url, to: dest)
                        attachedFileURL = dest
                        attachedFileName = dest.lastPathComponent
                        
                        // Automatically send the video when captured from camera
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            sendMessage()
                        }
                    } catch {
                        // Fallback: try Data copy
                        do {
                            let data = try Data(contentsOf: url)
                            try data.write(to: dest, options: .atomic)
                            attachedFileURL = dest
                            attachedFileName = dest.lastPathComponent
                            
                            // Automatically send the video when captured from camera
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                sendMessage()
                            }
                        } catch {
                            attachmentCopyErrorMessage =
                                "Failed to copy captured video: \(error.localizedDescription)"
                            attachmentCopyErrorAlert = true
                        }
                    }
                }
            }
        }
        // File/document picker sheet — copy the picked file into app Documents/Attachments
        .sheet(isPresented: $showingFilePicker) {
            ChatDocumentPicker { url in
                defer { showingFilePicker = false }
                guard let picked = url else { return }

                // Attempt to access security-scoped resource and copy into app Documents/Attachments
                let fm = FileManager.default
                let docs =
                    fm.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? fm.temporaryDirectory
                let attachmentsDir = docs.appendingPathComponent("Attachments", isDirectory: true)
                do {
                    try fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
                } catch {
                    attachmentCopyErrorMessage =
                        "Failed to create attachments directory: \(error.localizedDescription)"
                    attachmentCopyErrorAlert = true
                    return
                }

                var didStart = false
                if picked.startAccessingSecurityScopedResource() {
                    didStart = true
                }

                // Check size first for picked documents; reject >50MB
                do {
                    let attrs = try fm.attributesOfItem(atPath: picked.path)
                    if let size = attrs[.size] as? NSNumber {
                        let bytes = size.int64Value
                        let maxBytes: Int64 = 50 * 1024 * 1024  // 50 MB
                        if bytes > maxBytes {
                            attachmentCopyErrorMessage =
                                "Selected file is too large (over 50 MB). Please choose a smaller file."
                            attachmentCopyErrorAlert = true
                            if didStart { picked.stopAccessingSecurityScopedResource() }
                            return
                        }
                    }
                } catch {
                    // If attributes fail, continue and rely on copy exceptions
                }

                let dest = attachmentsDir.appendingPathComponent(
                    "\(UUID().uuidString)-\(picked.lastPathComponent)")
                do {
                    // Prefer copyItem to preserve file; if it fails, fall back to Data copy
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.copyItem(at: picked, to: dest)
                    attachedFileURL = dest
                    attachedFileName = dest.lastPathComponent
                } catch {
                    // Fallback: try reading data and writing
                    do {
                        let data = try Data(contentsOf: picked)
                        try data.write(to: dest, options: .atomic)
                        attachedFileURL = dest
                        attachedFileName = dest.lastPathComponent
                    } catch {
                        attachmentCopyErrorMessage =
                            "Failed to copy attachment: \(error.localizedDescription)"
                        attachmentCopyErrorAlert = true
                    }
                }

                if didStart {
                    picked.stopAccessingSecurityScopedResource()
                }
            }
        }

        // Modern confirmationDialog for attach options
        .confirmationDialog("Attach", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("Photo Library") {
                imagePickerSourceType = .photoLibrary
                showingImagePicker = true
            }
            Button("Paste from Clipboard") {
                handlePastedContent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how you'd like to attach a photo or file.")
        }

        // Show copy error alerts
        .alert("Attachment Error", isPresented: $attachmentCopyErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                attachmentCopyErrorMessage ?? "An unknown error occurred while attaching the file.")
        }
        // Show video upload error alerts
        .alert("Video Upload Error", isPresented: $videoUploadErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(videoUploadErrorMessage)
        }
        // Show content moderation alerts
        .alert("Message Blocked", isPresented: $messageBlockedAlert) {
            Button("Edit Message", role: .cancel) {}
            Button("Send Anyway") {
                // Send the original message without moderation
                let originalModeration = contentModerationEnabled
                contentModerationEnabled = false
                sendMessage()
                contentModerationEnabled = originalModeration
            }
        } message: {
            Text(
                "This message contains inappropriate content that violates community guidelines. You can edit your message or choose to send it anyway (it will still be filtered for other users)."
            )
        }
        // Full screen presenters
        .fullScreenCover(item: $fullScreenImageItem) { item in
            FullScreenImageView(uiImage: item.image)
        }
        .sheet(isPresented: $showingPopupVideo) {
            if let videoURL = popupVideoURL {
                PopupVideoPlayerView(url: videoURL)
                    .onAppear {
                        print("Popup video player appeared for URL: \(videoURL)")
                    }
                    .onDisappear {
                        print("Popup video player disappeared")
                        popupVideoURL = nil
                    }
            }
        }
        .sheet(isPresented: $showingPopupGif) {
            if let gifURL = popupGifURL {
                PopupGifView(url: gifURL)
                    .onAppear {
                        print("Popup GIF viewer appeared for URL: \(gifURL)")
                    }
                    .onDisappear {
                        print("Popup GIF viewer disappeared")
                        popupGifURL = nil
                    }
            }
        }
        .fullScreenCover(isPresented: $showingDocumentPreview) {
            if let url = fullScreenURL {
                QuickLookPreview(url: url)
            }
        }
        .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 800 : .infinity)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Messages View
    private var messagesView: some View {
        LazyVStack(spacing: 12) {
            // Pinned messages banner
            if !pinnedMessagesManager.pinnedMessages.isEmpty {
                pinnedMessagesBanner
            }

            ForEach(groupedMessages, id: \.date) { group in
                // Date separator
                DateSeparatorView(date: group.date)

                // Messages for this date
                ForEach(group.messages) { message in
                    MessageBubbleView(
                        message: message,
                        isCurrentUser: message.user == currentUserFullName,
                        isHighlighted: highlightedMessageId == message.id,
                        isJustAdded: justAddedMessageId == message.id,
                        isDeleting: deletingMessageId == message.id,
                        isEditingAnimation: editingAnimationId == message.id,
                        isShaking: shakingMessageId == message.id,
                        animationPhase: messageAnimationPhase[message.id] ?? .stable,
                        allMessages: messages,  // NEW: Pass all messages for reply lookup
                        onLongPress: {
                            selectedMessage = message
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                highlightedMessageId = message.id
                                showingMessageOptions = true
                            }
                        },
                        onBusinessTap: { business in
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            selectedBusiness = business
                            showingBusinessDetail = true
                        },
                        onPreviewImage: { img in
                            fullScreenImageItem = IdentifiableImage(image: img)
                        },
                        onPreviewVideo: { url in
                            print("Creating video player for URL: \(url)")
                            print("URL is file URL: \(url.isFileURL)")
                            print("URL exists: \(FileManager.default.fileExists(atPath: url.path))")

                            // Check if this is a GIF file
                            let isGif = url.pathExtension.lowercased() == "gif"
                            
                            if isGif {
                                print("Detected GIF file, showing GIF viewer")
                                popupGifURL = url
                                showingPopupGif = true
                            } else {
                                print("Detected video file, showing video player")
                                popupVideoURL = url
                                showingPopupVideo = true
                            }
                        },
                        onPreviewDocument: { url in
                            fullScreenURL = url
                            showingDocumentPreview = true
                        }
                    )
                    .id(message.id)
                }
            }

            // Typing indicator at the end of messages
            if !typingUsers.isEmpty {
                typingIndicator
                    .transition(
                        .asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
            }
        }
    }

    // MARK: - Typing Indicator
    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .opacity(!typingUsers.isEmpty ? 1.0 : 0.2)
                        .scaleEffect(!typingUsers.isEmpty ? 1.2 : 0.6)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: !typingUsers.isEmpty
                        )
                }

                Text(typingText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(!typingUsers.isEmpty ? 1.0 : 0.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
            .opacity(!typingUsers.isEmpty ? 1.0 : 0.0)
            .scaleEffect(!typingUsers.isEmpty ? 1.0 : 0.8)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
        .frame(height: 36)  // Fixed height to prevent layout jumps
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: !typingUsers.isEmpty)
    }

    // MARK: - Typing Text Helper
    private func extractFirstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: " ")
        return components.first?.capitalized ?? trimmed
    }

    private var typingText: String {
        let users = Array(typingUsers)
        if users.isEmpty {
            return ""
        } else if users.count == 1 {
            let firstName = extractFirstName(from: users[0])
            return "\(firstName) is typing..."
        } else if users.count == 2 {
            let firstName1 = extractFirstName(from: users[0])
            let firstName2 = extractFirstName(from: users[1])
            return "\(firstName1) and \(firstName2) are typing..."
        } else {
            let firstName = extractFirstName(from: users[0])
            return "\(firstName) and \(users.count - 1) others are typing..."
        }
    }

    // MARK: - Pinned Messages Banner
    private var pinnedMessagesBanner: some View {
        VStack(spacing: 0) {
            Button(action: { showPinnedMessages = true }) {
                HStack {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))

                    Text(
                        "\(pinnedMessagesManager.pinnedMessages.count) pinned message\(pinnedMessagesManager.pinnedMessages.count == 1 ? "" : "s")"
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Message Input View
    private var messageInputView: some View {
        VStack(spacing: 0) {
            // Reply or Edit context bar
            if let replyMessage = replyingToMessage {
                replyContextBar(for: replyMessage)
            } else if let editMessage = editingMessage {
                editContextBar(for: editMessage)
            }

            // Attachment/captured image preview
            if let image = capturedImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 80)
                        .cornerRadius(10)
                        .padding(.vertical, 4)
                        .onTapGesture {
                            showImageViewer = true
                        }
                        .accessibilityLabel("Tap to enlarge image preview")
                    Button(action: { capturedImage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 12)
                // Fullscreen image viewer sheet
                .sheet(isPresented: $showImageViewer) {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack {
                            Spacer()
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black)
                                .onTapGesture {
                                    showImageViewer = false
                                }
                            Spacer()
                        }
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: { showImageViewer = false }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding()
                                }
                            }
                            Spacer()
                        }
                    }
                }
            } else if let fileName = attachedFileName {
                HStack {
                    Image(systemName: fileIcon(for: fileName))
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text(isVideoFile(fileName) ? "Video" : fileName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(action: {
                        attachedFileURL = nil
                        attachedFileName = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            // Recording indicator
            if isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .scaleEffect(isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.4), value: isRecording)

                    Text("Recording... \(Int(recordingDuration))s")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        // Cancel recording
                        if isRecording {
                            isRecording = false
                            recordingTimer?.invalidate()
                            recordingTimer = nil
                            voiceRecorder.cancelRecording()
                        }
                    }) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            HStack(spacing: 12) {
                // Text input with enhanced keyboard optimizations
                HStack {
                    TextField(inputPlaceholder, text: inputBinding, axis: .vertical)
                        .focused($isTextFieldFocused)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .keyboardType(.default)
                        .submitLabel(.send)
                        .onSubmit {
                            if editingMessage != nil {
                                saveEditedMessage()
                            } else {
                                sendMessage()
                            }
                        }
                        .onChange(of: editingText) { _, newValue in
                            simulateTyping()
                            handleAISearchQuery(newValue)
                            showTypingIndicator(for: newValue)
                        }
                        .onChange(of: messageText) { _, newValue in
                            simulateTyping()
                            handleAISearchQuery(newValue)
                            showTypingIndicator(for: newValue)
                        }
                        .onChange(of: isTextFieldFocused) { _, focused in
                            if focused {
                                simulateTyping()
                            }
                        }
                }
                if !inputBinding.wrappedValue.isEmpty {
                    Button(action: clearInput) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                // Send/Save button
                Button(action: {
                    if editingMessage != nil {
                        saveEditedMessage()
                    } else {
                        sendMessage()
                    }
                }) {
                    Image(systemName: sendButtonIcon)
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(
                                    (inputBinding.wrappedValue.trimmingCharacters(in: .whitespaces)
                                        .isEmpty && capturedImage == nil && attachedFileURL == nil)
                                        ? Color.gray : Color.blue)
                        )
                        .scaleEffect(
                            (inputBinding.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
                                && capturedImage == nil && attachedFileURL == nil) ? 0.8 : 1.0
                        )
                        .animation(.spring(response: 0.3), value: inputBinding.wrappedValue.isEmpty)
                        .animation(.spring(response: 0.3), value: capturedImage != nil)
                        .animation(.spring(response: 0.3), value: attachedFileURL != nil)
                }
                .disabled(
                    inputBinding.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
                        && capturedImage == nil && attachedFileURL == nil)

                // (hold-to-record removed; use mic button in custom actions)

                // Custom button on the right
                VStack(spacing: 4) {
                    Button(action: {
                        withAnimation { showCustomActionsRow.toggle() }
                    }) {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(.purple)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.purple.opacity(0.12))
                            )
                    }
                    .accessibilityLabel("More options")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                // 3D, semi-transparent, rounded, blurred background using native SwiftUI
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.18), radius: 15, x: 0, y: 4)
            )

            // Real-time content warning indicator
            if currentInputContainsInappropriateContent {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12, weight: .semibold))

                        Text("Your message contains filtered content")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)

                        Spacer()
                    }

                    Text("Preview: \(currentInputPreview)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(
                    .easeInOut(duration: 0.2), value: currentInputContainsInappropriateContent)
            }
        }
        .sheet(isPresented: $showPinnedMessages) {
            VStack(spacing: 0) {
                Capsule()
                    .frame(width: 40, height: 6)
                    .foregroundColor(Color(.systemGray4))
                    .padding(.top, 8)
                Text("Pinned Messages")
                    .font(.headline)
                    .padding(.top, 8)
                Divider()
                ScrollView {
                    PinnedMessagesView(manager: pinnedMessagesManager, isAdmin: isAdmin)
                        .padding(.bottom, 24)
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Context Bars
    private func replyContextBar(for message: CommunityMessage) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Replying to \(extractFirstName(from: message.user))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }

                // Show appropriate content based on message type
                Group {
                    if message.text.isEmpty && (message.imageData != nil || message.fileData != nil)
                    {
                        HStack(spacing: 4) {
                            Image(systemName: message.imageData != nil ? "photo" : "paperclip")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(
                                message.imageData != nil
                                    ? "Photo"
                                    : (isVideoFile(message.fileName ?? "")
                                        ? "Video" : (message.fileName ?? "Attachment"))
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                        }
                    } else {
                        Text(message.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer()
            Button(action: cancelReply) {
                Image(systemName: "xmark")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
    }

    // MARK: - ActionCircleButton
    struct ActionCircleButton: View {
        let icon: String
        let color: Color
        let label: String
        let action: () -> Void
        // Optional active state for things like recording
        var isActive: Bool = false
        var activeColor: Color? = nil

        @State private var pulse: Bool = false

        var body: some View {
            VStack(spacing: 8) {
                Button(action: action) {
                    ZStack {
                        // Pulsing outer ring when active
                        if isActive {
                            Circle()
                                .stroke(activeColor ?? color, lineWidth: 4)
                                .frame(width: 72, height: 72)
                                .scaleEffect(pulse ? 1.12 : 0.92)
                                .opacity(pulse ? 0.22 : 0.08)
                                .animation(
                                    Animation.easeInOut(duration: 0.9).repeatForever(
                                        autoreverses: true), value: pulse
                                )
                                .onAppear { pulse = true }
                                .onDisappear { pulse = false }
                        }

                        Circle()
                            .fill(Color.white)
                            .frame(width: 56, height: 56)
                            .shadow(color: color.opacity(0.22), radius: 10, x: 0, y: 4)

                        Circle()
                            .fill(color.opacity(0.22))
                            .frame(width: 48, height: 48)

                        Image(systemName: icon)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(color)
                    }
                }
                if !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
    }
    private func editContextBar(for message: CommunityMessage) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Editing your message")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
                Text(message.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: cancelEdit) {
                Image(systemName: "xmark")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Helper Properties for Input
    private var inputBinding: Binding<String> {
        if editingMessage != nil {
            return $editingText
        } else {
            return $messageText
        }
    }

    private var inputPlaceholder: String {
        if replyingToMessage != nil {
            return "Reply to message..."
        } else if editingMessage != nil {
            return "Edit your message..."
        } else {
            return "Message... (Type # for search or local businesses)"
        }
    }

    private var sendButtonIcon: String {
        let hasText = !inputBinding.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        let hasImage = capturedImage != nil
        let hasFile = attachedFileURL != nil
        let hasContent = hasText || hasImage || hasFile

        if editingMessage != nil {
            return hasContent ? "checkmark.circle.fill" : "checkmark.circle"
        } else {
            return hasContent ? "arrow.up.circle.fill" : "arrow.up.circle"
        }
    }

    // MARK: - Chat Settings Sheet
    private var chatSettingsSheet: some View {
        NavigationView {
            Form {
                // Notification Settings
                Section(header: Text("Notifications")) {
                    Toggle("Chat Notifications", isOn: $chatNotificationsEnabled)
                        .accessibilityLabel("Enable chat notifications")

                    Toggle("Sound Effects", isOn: $chatSoundEnabled)
                        .accessibilityLabel("Enable sound effects")
                        .disabled(!chatNotificationsEnabled)
                }

                // Display Settings
                Section(header: Text("Display")) {
                    Toggle("Show Timestamps", isOn: $chatShowTimestamps)
                        .accessibilityLabel("Show message timestamps")

                    Toggle("Show Typing Indicators", isOn: $chatShowTypingIndicators)
                        .accessibilityLabel("Show typing indicators")

                    Toggle("Auto-scroll to New Messages", isOn: $chatAutoScroll)
                        .accessibilityLabel("Auto-scroll to new messages")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(chatFontSize))pt")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $chatFontSize, in: 12...24, step: 1)
                            .accessibilityLabel("Adjust font size")
                    }

                    // Background Style Picker
                    NavigationLink(destination: backgroundPickerView) {
                        HStack {
                            Label("Background Style", systemImage: "paintbrush.fill")
                            Spacer()
                            Text(backgroundStyleDisplayName)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }

                // Features
                Section(header: Text("Features")) {
                    NavigationLink(destination: searchFeatureGuideView) {
                        Label("Message Search Guide", systemImage: "magnifyingglass.circle")
                    }

                    NavigationLink(destination: businessDiscoveryGuideView) {
                        Label("Local Business Discovery", systemImage: "storefront.circle")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text("Quick Tip")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text(
                            "Type # followed by your search term to find messages or discover local businesses instantly."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }

                // Privacy & Safety
                Section(header: Text("Privacy & Safety")) {
                    Toggle("Show My Name", isOn: $showUserCredentials)
                        .accessibilityLabel("Show or hide your name in messages")

                    NavigationLink(destination: moderationSettingsView) {
                        Label("Moderation Settings", systemImage: "shield.lefthalf.filled")
                    }
                }

                // Data Management
                Section(
                    header: Text("Data"),
                    footer: Text(
                        "Clear Chat Messages: Removes only your messages from the chat. Clear All Messages: Admin-only option to remove all community messages."
                    )
                ) {
                    HStack {
                        Text("Messages Stored")
                        Spacer()
                        Text("\(messages.count)")
                            .foregroundColor(.secondary)
                    }

                    Button(action: clearPersonalData) {
                        Label("Clear Chat Messages", systemImage: "trash")
                            .foregroundColor(.red)
                    }

                    // "Clear App Storage" removed per request

                    if isAdmin {
                        Button(action: clearAllData) {
                            Label("Clear All Messages", systemImage: "trash.fill")
                                .foregroundColor(.red)
                        }
                    }
                }

                // Community Features
                Section(header: Text("Community")) {
                    if isAdmin {
                        NavigationLink(destination: editCommunityGuidelinesView) {
                            Label("Edit Community Guidelines", systemImage: "doc.text.fill")
                        }
                    } else {
                        NavigationLink(destination: communityGuidelinesView) {
                            Label("Community Guidelines", systemImage: "doc.text")
                        }
                    }

                    NavigationLink(destination: neighborDirectoryView) {
                        Label("Neighbor Directory", systemImage: "person.3")
                    }
                }

                // About Section
                Section(header: Text("About")) {
                    if isAdmin {
                        NavigationLink(destination: adminHelpView) {
                            Label("Admin Help", systemImage: "person.badge.key.fill")
                        }
                    }
                }
            }
            .navigationTitle("Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingChatSettings = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        // ...existing code...
    }

    // MARK: - Message Options Overlay
    private var messageOptionsOverlay: some View {
        Group {
            if showingMessageOptions, let message = selectedMessage {
                ZStack {
                    // Semi-transparent background
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                highlightedMessageId = nil
                                showingMessageOptions = false
                                selectedMessage = nil
                            }
                        }

                    // Floating action menu positioned near the highlighted message
                    VStack(spacing: 0) {
                        Spacer()

                        HStack {
                            Spacer()

                            // Compact floating menu
                            VStack(spacing: 1) {
                                // Reply button
                                Button(action: replyToMessage) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrowshape.turn.up.left.fill")
                                            .foregroundColor(.blue)
                                            .frame(width: 16)
                                        Text("Reply")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemBackground))
                                }

                                // Copy button
                                Button(action: copyMessage) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                            .frame(width: 16)
                                        Text("Copy")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemBackground))
                                }

                                // Edit button (only for own messages)
                                if message.user == currentUserFullName
                                    && message.messageType == .text
                                {
                                    Button(action: editMessage) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "pencil")
                                                .foregroundColor(.blue)
                                                .frame(width: 16)
                                            Text("Edit")
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemBackground))
                                    }
                                }

                                // Delete button (own messages or admin)
                                if message.user == currentUserFullName || isAdmin {
                                    Button(action: deleteMessage) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                                .frame(width: 16)
                                            Text("Delete")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.red)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemBackground))
                                    }
                                }

                                // Pin/Unpin (admin only)
                                if isAdmin && message.messageType != .system {
                                    if pinnedMessagesManager.isPinned(messageId: message.id) {
                                        Button(action: {
                                            pinnedMessagesManager.unpin(
                                                messageId: message.id, isAdmin: isAdmin)
                                        }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "pin.slash")
                                                    .foregroundColor(.orange)
                                                    .frame(width: 16)
                                                Text("Unpin")
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.orange)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(.systemBackground))
                                        }
                                    } else {
                                        Button(action: {
                                            pinnedMessagesManager.pin(
                                                message: message, isAdmin: isAdmin,
                                                pinnedBy: currentUserFullName)
                                        }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "pin")
                                                    .foregroundColor(.orange)
                                                    .frame(width: 16)
                                                Text("Pin")
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.orange)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(.systemBackground))
                                        }
                                    }
                                }
                                // Admin moderate option
                                if isAdmin && message.user != currentUserFullName
                                    && message.messageType != .system
                                {
                                    Button(action: moderateMessage) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "exclamationmark.shield")
                                                .foregroundColor(.orange)
                                                .frame(width: 16)
                                            Text("Moderate")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.orange)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemBackground))
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            .scaleEffect(showingMessageOptions ? 1.0 : 0.8)
                            .opacity(showingMessageOptions ? 1.0 : 0.0)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.8),
                                value: showingMessageOptions)

                            Spacer()
                        }

                        Spacer()
                            .frame(height: 100)  // Space above input field
                    }
                }
            }
        }
    }

    // MARK: - Settings Sub-Views
    private var moderationSettingsView: some View {
        Form {
            Section(
                header: Text("Content Moderation"),
                footer: Text(
                    "Enable or disable content filtering for inappropriate language. This setting only affects what you see."
                )
            ) {

                Toggle("Enable Content Filtering", isOn: $contentModerationEnabled)
                    .tint(.blue)

                if contentModerationEnabled {
                    Toggle("Show Content Warnings", isOn: $showModerationWarnings)
                        .tint(.orange)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How Content Filtering Works")
                        .font(.headline)

                    Text(
                        "When enabled, the app will filter out inappropriate language and profanity from messages."
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Your settings only affect what YOU see")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Other users can set their own preferences")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Original messages are never modified")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Content Moderation")
    }

    private var backgroundPickerView: some View {
        Form {
            Section(header: Text("Background Styles")) {
                // Default option
                Button(action: { chatBackgroundStyle = "default" }) {
                    HStack {
                        Rectangle()
                            .fill(Color(.systemBackground))
                            .frame(width: 40, height: 30)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )

                        VStack(alignment: .leading) {
                            Text("Default")
                                .foregroundColor(.primary)
                            Text("Clean system background")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if chatBackgroundStyle == "default" {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())

                // Solid color options
                ForEach(
                    [
                        ("blue", "Ocean Blue", "Enhanced blue tones for better visibility"),
                        ("green", "Nature Green", "Vibrant natural vibes"),
                        ("purple", "Royal Purple", "Rich elegant sophistication"),
                        ("orange", "Warm Orange", "Bold energetic warmth"),
                    ], id: \.0
                ) { style, name, description in
                    Button(action: { chatBackgroundStyle = style }) {
                        HStack {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            colorForStyle(style).opacity(0.15),
                                            colorForStyle(style).opacity(0.05),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 30)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )

                            VStack(alignment: .leading) {
                                Text(name)
                                    .foregroundColor(.primary)
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if chatBackgroundStyle == style {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Section(header: Text("Gradient Backgrounds")) {
                ForEach(
                    [
                        ("sunset", "Sunset Gradient", "Enhanced warm sunset colors"),
                        ("ocean", "Ocean Waves", "Deeper ocean blues and teals"),
                        ("forest", "Forest Breeze", "Richer natural green tones"),
                        ("warm", "Warm Tones", "Vibrant cozy red and orange"),
                        ("cool", "Cool Tones", "Enhanced blue and purple"),
                    ], id: \.0
                ) { style, name, description in
                    Button(action: { chatBackgroundStyle = style }) {
                        HStack {
                            Rectangle()
                                .fill(gradientForStyle(style))
                                .frame(width: 40, height: 30)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )

                            VStack(alignment: .leading) {
                                Text(name)
                                    .foregroundColor(.primary)
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if chatBackgroundStyle == style {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Section(header: Text("Minimal Options")) {
                Button(action: { chatBackgroundStyle = "minimal" }) {
                    HStack {
                        Rectangle()
                            .fill(Color(.systemGray6).opacity(0.3))
                            .frame(width: 40, height: 30)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )

                        VStack(alignment: .leading) {
                            Text("Minimal Gray")
                                .foregroundColor(.primary)
                            Text("Subtle gray background")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if chatBackgroundStyle == "minimal" {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }

            Section(
                footer: Text(
                    "Background changes apply immediately to the chat. Enhanced opacity levels provide better visibility in both light and dark modes. Choose a style that enhances readability and matches your mood."
                )
            ) {
                EmptyView()
            }
        }
        .navigationTitle("Chat Background")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Helper functions for background picker
    private func colorForStyle(_ style: String) -> Color {
        switch style {
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        default: return .blue
        }
    }

    private func gradientForStyle(_ style: String) -> LinearGradient {
        switch style {
        case "sunset":
            return LinearGradient(
                colors: [
                    Color.orange.opacity(0.3), Color.pink.opacity(0.2), Color.purple.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "ocean":
            return LinearGradient(
                colors: [
                    Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.teal.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "forest":
            return LinearGradient(
                colors: [
                    Color.green.opacity(0.3), Color.mint.opacity(0.2), Color.teal.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "warm":
            return LinearGradient(
                colors: [
                    Color.red.opacity(0.2), Color.orange.opacity(0.15), Color.yellow.opacity(0.1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "cool":
            return LinearGradient(
                colors: [
                    Color.blue.opacity(0.2), Color.indigo.opacity(0.15), Color.purple.opacity(0.1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var communityGuidelinesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Community Guidelines")
                    .font(.title2)
                    .fontWeight(.bold)

                if communityGuidelines.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Be respectful and kind to all neighbors")
                        Text("2. Keep discussions relevant to the community")
                        Text("3. No spam or excessive promotional content")
                        Text("4. Respect privacy and confidentiality")
                        Text("5. Report inappropriate behavior to moderators")
                    }
                } else {
                    Text(communityGuidelines)
                        .lineSpacing(4)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Guidelines")
    }

    private var editCommunityGuidelinesView: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Community Guidelines")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)

                TextEditor(text: $communityGuidelines)
                    .frame(minHeight: 200)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                Text("These guidelines will be visible to all community members.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Edit Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Guidelines are automatically saved via @AppStorage
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var neighborDirectoryView: some View {
        List {
            Text("Feature coming soon - Connect with verified neighbors")
                .foregroundColor(.secondary)
                .italic()
        }
    }

    private var adminHelpView: some View {
        List {
            Section("Admin Features") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("As an admin, you can:")
                    Text("• Delete any message")
                    Text("• Moderate inappropriate content")
                    Text("• Edit community guidelines")
                    Text("• Clear all chat history")
                    Text("• Pin important messages")
                }
                .font(.subheadline)
            }

            Section("Quick Actions") {
                Text("Long press any message to see moderation and other options")
            }
        }
        .navigationTitle("Admin Help")
    }

    // MARK: - Feature Guides
    private var searchFeatureGuideView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Message Search Guide")
                    .font(.title2)
                    .fontWeight(.bold)

                // Quick Start
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.blue)
                        Text("Quick Start")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }

                    Text(
                        "Type # followed by your search term to activate message search. The system automatically detects whether you're looking for chat messages or local businesses."
                    )
                    .lineSpacing(4)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                // Message Search
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "message.fill")
                            .foregroundColor(.green)
                        Text("Message Search")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search through neighborhood chat history:")
                        Group {
                            Text("• #hello - Find messages containing 'hello'")
                            Text("• #meeting - Find messages about meetings")
                            Text("• #maintenance - Find property discussions")
                            Text("• #John - Find messages from John")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Advanced Features
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundColor(.purple)
                        Text("Smart Search Features")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Fuzzy Matching: Finds similar words even with typos")
                        Text("• Relevance Scoring: Most relevant results shown first")
                        Text("• Recent Boost: Recent messages ranked higher")
                        Text("• User Search: Find messages from specific neighbors")
                        Text("• Content Filtering: Respects moderation settings")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Message Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var businessDiscoveryGuideView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Local Business Discovery")
                    .font(.title2)
                    .fontWeight(.bold)

                // How it Works
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.orange)
                        Text("Location-Based Search")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }

                    Text(
                        "Our system automatically detects business-related searches and shows you nearby local businesses based on your location. Results are sorted by distance, relevance, and ratings."
                    )
                    .lineSpacing(4)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)

                // Search Examples
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                        Text("Search Examples")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            Text("🍕 #pizza - Find nearby restaurants")
                            Text("☕ #coffee - Find cafés and coffee shops")
                            Text("🛒 #grocery - Find local markets")
                            Text("⚕️ #doctor - Find healthcare providers")
                            Text("🔧 #repair - Find repair services")
                            Text("🐕 #vet - Find veterinary clinics")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Business Cards
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundColor(.green)
                        Text("Interactive Business Cards")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Each business result shows:")
                        Group {
                            Text("• ⭐ Star ratings and reviews")
                            Text("• 📍 Distance from your location")
                            Text("• 🕒 Current hours and open status")
                            Text("• 📞 Direct calling capability")
                            Text("• 🗺️ Instant directions in Maps")
                            Text("• 🌐 Quick website access")
                            Text("• ℹ️ Detailed business information")
                            Text("• 📤 Share individual or entire lists")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        Text("🎯 New Interactive Features:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)

                        Group {
                            Text("• 📱 Quick action buttons always visible")
                            Text("• 🔽 Tap to expand all available actions")
                            Text("• 📳 Haptic feedback for button presses")
                            Text("• 💬 Toast notifications for confirmations")
                            Text("• ⚡ Actions work directly from chat bubbles")
                            Text("• 🎨 Auto-collapse after action completion")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)

                // Sharing Feature
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "square.and.arrow.up.fill")
                            .foregroundColor(.purple)
                        Text("Share with Neighbors")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share individual businesses:")
                        Group {
                            Text("• Tap the 'Share' button on any business card")
                            Text("• Creates interactive chat bubble")
                            Text("• Neighbors can call/get directions directly")
                            Text("• Includes ratings and contact info")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        Text("🆕 Share All Results (New!):")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)

                        Group {
                            Text("• Use 'Share All' button for entire business list")
                            Text("• Creates expandable business list chat bubble")
                            Text("• Shows business count and search query")
                            Text("• Each business has interactive buttons")
                            Text("• Perfect for community recommendations")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)

                // Interactive Chat Features
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "hand.tap.fill")
                            .foregroundColor(.cyan)
                        Text("Interactive Chat Features")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("🎯 Direct interaction from chat bubbles:")
                        Group {
                            Text("• 📞 Always-visible call button (if phone available)")
                            Text("• 🗺️ Always-visible directions button")
                            Text("• 🔽 Tap any business to expand all actions")
                            Text("• 🌐 Website access button (if available)")
                            Text("• ℹ️ Full business details modal")
                            Text("• 📳 Haptic feedback on all interactions")
                            Text("• 💬 Toast confirmations for actions taken")
                            Text("• ⚡ Auto-collapse after completing actions")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        Text("✨ User Experience Benefits:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)

                        Group {
                            Text("• No need to leave the chat to interact")
                            Text("• Quick access to most common actions")
                            Text("• Smooth animations and transitions")
                            Text("• Consistent design across all business types")
                            Text("• Perfect for mobile-first usage")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(12)

                // Sort Options
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.red)
                        Text("Sort Options")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sort business results by:")
                        Group {
                            Text("• Distance (closest first)")
                            Text("• Rating (highest rated first)")
                            Text("• Name (alphabetical)")
                            Text("• Open Now (open businesses first)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Business Discovery")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helper Properties
    private var onlineUsersCount: Int {
        // Simulate online users based on recent activity
        let recentMessages = messages.filter { $0.timestamp > Date().addingTimeInterval(-3600) }
        let uniqueUsers = Set(recentMessages.map { $0.user })
        return max(1, uniqueUsers.count)
    }

    private var groupedMessages: [MessageGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }

        return grouped.map { date, messages in
            MessageGroup(date: date, messages: messages.sorted { $0.timestamp < $1.timestamp })
        }.sorted { $0.date < $1.date }
    }

    // Computed property to check if current input contains inappropriate content
    private var currentInputContainsInappropriateContent: Bool {
        guard contentModerationEnabled else { return false }
        let currentText = editingMessage != nil ? editingText : messageText
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && SimpleContentModerator.shouldCensorMessage(trimmed, moderationEnabled: true)
    }

    private var currentInputPreview: String {
        let currentText = editingMessage != nil ? editingText : messageText
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SimpleContentModerator.censorMessage(trimmed, moderationEnabled: true)
    }

    // MARK: - Actions
    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || capturedImage != nil || attachedFileURL != nil else { return }

        // Validate video file size before proceeding
        if let fileURL = attachedFileURL, isVideoFile(fileURL.lastPathComponent) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let fileSize = attributes[.size] as? Int64 {
                    let maxSize: Int64 = 100 * 1024 * 1024  // 100MB limit
                    if fileSize > maxSize {
                        // Show error alert
                        let sizeMB = Double(fileSize) / (1024 * 1024)
                        let maxMB = Double(maxSize) / (1024 * 1024)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("VideoUploadError"),
                            object: "Video file is too large (\(String(format: "%.1f", sizeMB))MB). Maximum size is \(Int(maxMB))MB."
                        )
                        return
                    }
                }
            } catch {
                print("CommunityChatCard: Could not read file size: \(error)")
            }
        }

        // Check if this is a search query (starts with "#") - don't send as message
        if trimmed.hasPrefix("#") && capturedImage == nil && attachedFileURL == nil {
            // This is a search query, not a message to send
            // Clear the search and input
            aiSearchManager.clearSearch()
            messageText = ""
            isTextFieldFocused = false
            return
        }

        // Content Moderation: Check if message should be blocked entirely
        if contentModerationEnabled
            && SimpleContentModerator.shouldCensorMessage(
                trimmed, moderationEnabled: contentModerationEnabled)
        {
            let censoredText = SimpleContentModerator.censorMessage(
                trimmed, moderationEnabled: contentModerationEnabled)

            // If the entire message becomes just asterisks, prevent sending
            let asteriskCount = censoredText.filter { $0 == "*" }.count
            let totalCharacters = censoredText.trimmingCharacters(in: .whitespacesAndNewlines).count

            if Double(asteriskCount) > Double(totalCharacters) * 0.7 {  // If more than 70% is censored
                // Show alert and don't send message
                messageBlockedAlert = true
                return
            }
        }

        // Content Moderation: Apply user's preferred filtering
        let censoredText: String
        if contentModerationEnabled {
            censoredText = SimpleContentModerator.censorMessage(
                trimmed, moderationEnabled: contentModerationEnabled)
        } else {
            censoredText = trimmed
        }

        let displayName =
            showUserCredentials
            ? (currentUserFullName.isEmpty ? "Anonymous" : currentUserFullName)
            : "Anonymous Neighbor"

        // Convert captured image to data for storage and persist to disk for offline fallback
        var imageData: Data? = nil
        var imageLocalPath: String? = nil
        if let img = capturedImage {
            // Compress image for Firestore storage (instant loading)
            imageData = img.compressedForFirestore()
            // Persist image using ImageCacheManager (Application Support) so files are excluded from backups
            if let data = img.compressedForFirestore() {
                do {
                    let path = try ImageCacheManager.shared.saveData(data, forMessage: UUID())
                    imageLocalPath = path
                } catch {
                    print("Failed to write chat image to cache: \(error)")
                }
            }
        }

        // Handle file attachment
        var fileData: Data? = nil
        var fileName: String? = nil
        var fileLocalURL: String? = nil
        if let fileURL = attachedFileURL {
            fileName = fileURL.lastPathComponent
            print("CommunityChatCard: Processing file attachment: \(fileName ?? "unknown")")
            print("   - File URL: \(fileURL.absoluteString)")
            print("   - File path: \(fileURL.path)")
            
            // Check if this is a video/GIF file - don't load large videos into RAM
            let isVideo = isVideoFile(fileName ?? "")
            let isGif = (fileName ?? "").lowercased().hasSuffix(".gif")
            print("CommunityChatCard: File type: \(isVideo ? (isGif ? "GIF" : "VIDEO") : "OTHER")")
            
            // Check if file is already in app's sandbox (Documents/Attachments)
            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
            let tempPath = fileManager.temporaryDirectory.path
            let isInAppSandbox = fileURL.path.hasPrefix(documentsPath)
            let isInTempDir = fileURL.path.hasPrefix(tempPath)
            
            print("CommunityChatCard: File in app sandbox: \(isInAppSandbox)")
            print("CommunityChatCard: File in temp directory: \(isInTempDir)")
            
            // Verify file exists before trying to read
            if !fileManager.fileExists(atPath: fileURL.path) {
                print("CommunityChatCard: ❌ ERROR: File does not exist at path!")
                print("   - This will cause upload to fail!")
            } else {
                print("CommunityChatCard: ✅ File exists at path")
                if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? UInt64 {
                    print("   - File size: \(size) bytes (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))")
                }
            }
            
            if isInAppSandbox || isInTempDir {
                // File is already in our Documents directory or temp - read directly without security scoping
                do {
                    fileData = try Data(contentsOf: fileURL)
                    print("CommunityChatCard: ✅ File loaded successfully (\(fileData?.count ?? 0) bytes)")
                } catch {
                    print("CommunityChatCard: ❌ FAILED to load file: \(error.localizedDescription)")
                    print("   - Error details: \(error)")
                }
            } else {
                // File is outside sandbox - need security-scoped access
                let canAccessResource = fileURL.startAccessingSecurityScopedResource()
                print("CommunityChatCard: Security-scoped resource access: \(canAccessResource)")
                
                if canAccessResource {
                    do {
                        fileData = try Data(contentsOf: fileURL)
                        print("CommunityChatCard: ✅ File loaded successfully with security scoping (\(fileData?.count ?? 0) bytes)")
                    } catch {
                        print("CommunityChatCard: ❌ FAILED to load file data: \(error.localizedDescription)")
                    }
                    fileURL.stopAccessingSecurityScopedResource()
                } else {
                    print("CommunityChatCard: ❌ Failed to access security-scoped resource")
                }
            }
            
            // Store local path for immediate playback on sender's device
            fileLocalURL = fileURL.path
            print("CommunityChatCard: File local path: \(fileLocalURL ?? "nil")")
            print("CommunityChatCard: Final fileData status: \(fileData != nil ? "✅ DATA LOADED (\(fileData!.count) bytes)" : "❌ NO DATA")")
        } else {
            print("CommunityChatCard: No file attachment")
        }

        // Determine message type based on content
        let messageType: MessageType
        let hasText = !censoredText.isEmpty
        let hasImage = capturedImage != nil
        let hasFile = attachedFileURL != nil

        if hasFile && hasText {
            messageType = .mixed  // File + text
        } else if hasImage && hasText {
            messageType = .mixed  // Image + text
        } else if hasFile {
            messageType = .file
        } else if hasImage {
            messageType = .image
        } else {
            messageType = .text
        }

        let newMessage = CommunityMessage(
            id: UUID(),
            user: displayName,
            text: hasFile
                ? (hasText
                    ? censoredText : (isVideoFile(fileName ?? "") ? "Video" : (fileName ?? "File")))
                : censoredText,
            timestamp: Date(),
            messageType: messageType,
            isEdited: false,
            editedAt: nil,
            replyTo: replyingToMessage?.id,
            imageData: imageData,
            imageLocalURL: imageLocalPath,
            imageURL: nil,
            fileURL: nil,
            audioURL: nil,
            fileData: fileData,
            fileName: fileName,
            fileLocalURL: fileLocalURL,
            isRead: false
        )

        // Optimistically append locally so UI is responsive
        messages.append(newMessage)
        // Immediately show upload progress for this optimistic message
        NotificationCenter.default.post(
            name: .communityUploadProgress, object: nil,
            userInfo: ["id": newMessage.id.uuidString, "type": "start", "progress": 0.0])

        // Set up sending animation
        messageAnimationPhase[newMessage.id] = .appearing
        newMessageIds.insert(newMessage.id)

        // Clear any previous animation state first
        justAddedMessageId = nil

        // Animate new message with dramatic entrance effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.3)) {
                justAddedMessageId = newMessage.id
            }

            // Transition to stable state after appearing animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    messageAnimationPhase[newMessage.id] = .stable
                    newMessageIds.remove(newMessage.id)
                }
            }

            // Automatically fade out the green glow after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOutQuart(duration: 1.5)) {
                    if justAddedMessageId == newMessage.id {
                        justAddedMessageId = nil
                    }
                }
            }

            // Play enhanced sound effect for new message
            if chatSoundEnabled && chatNotificationsEnabled {
                playSendSound()
                // Add a subtle second sound for emphasis
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    AudioServicesPlaySystemSound(1016)  // Keyboard click for emphasis
                }
            }
        }

        messageText = ""
        replyingToMessage = nil
        isTextFieldFocused = false
        capturedImage = nil  // Clear image after sending
        attachedFileURL = nil  // Clear file after sending
        attachedFileName = nil

        // Stop broadcasting typing status since message was sent
        broadcastTypingStatus(false)

        saveMessages()

        // Delegate persistence and any attachment uploads to the centralized ChatMessagesManager.
        // The manager uses FirebaseManager which will upload attachments (image/file/audio) when needed
        // and write the Firestore document; it also merges remote updates back into the UI.
        #if canImport(FirebaseFirestore)
            chatManager.addMessage(newMessage)
        #endif

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Note: Notifications for incoming messages are now handled by ChatMessagesManager
        // Only the sender gets haptic feedback, other users get push notifications
    }

    private func playSendSound() {
        // Play system sound for message sent
        AudioServicesPlaySystemSound(1004)  // Message sent sound
    }

    private func playReceiveSound() {
        // Play system sound for message received
        AudioServicesPlaySystemSound(1003)  // Message received sound
    }

    private func sendAudioMessage(audioData: Data, fileName: String) {
        let displayName =
            showUserCredentials
            ? (currentUserFullName.isEmpty ? "Anonymous" : currentUserFullName)
            : "Anonymous Neighbor"

        // Persist audio file to Documents/NeighborHub/Audio for persistence
        let fm = FileManager.default
        let documents =
            fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let audioDir = documents.appendingPathComponent("NeighborHub/Audio", isDirectory: true)
        try? fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let safeName = fileName
        let destination = audioDir.appendingPathComponent(safeName)
        do {
            try audioData.write(to: destination, options: .atomic)
        } catch {
            print("Failed to write audio file: \(error)")
        }

        // Use new initializer that accepts audioData/audioFileName (initializer will set file name/url appropriately)
        let newMessage = CommunityMessage(
            id: UUID(),
            user: displayName,
            text: "Voice Message",
            timestamp: Date(),
            messageType: .audio,
            isEdited: false,
            editedAt: nil,
            replyTo: replyingToMessage?.id,
            imageData: nil,
            imageURL: nil,
            fileURL: nil,
            audioURL: nil,
            fileData: nil,
            fileName: nil,
            fileLocalURL: nil,
            audioFileName: safeName,
            audioFileURL: destination.path,
            isRead: false
        )

        messages.append(newMessage)

        // Play effects and save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.3)) {
                justAddedMessageId = newMessage.id
            }
            if chatSoundEnabled && chatNotificationsEnabled {
                playSendSound()
            }
        }

        saveMessages()
        // Haptic
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Persist audio message via ChatMessagesManager which will handle uploads and Firestore writes.
        #if canImport(FirebaseFirestore)
            chatManager.addMessage(newMessage)
        #endif
    }

    private func simulateTyping() {
        // Get the current input text
        let currentText = editingMessage != nil ? editingText : messageText

        // Only show typing indicator if there's actual text being typed
        guard !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isTyping = false
            return
        }

        // Show typing indicator immediately
        isTyping = true

        // Hide typing indicator after a delay if no more typing occurs
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Only hide if the message text is still the same (no new typing)
            let currentInputText = self.editingMessage != nil ? self.editingText : self.messageText
            if currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.isTyping = false
            }
        }
    }

    private func handleAISearchQuery(_ text: String) {
        // Cancel previous highlight timer
        highlightTimer?.invalidate()

        // Check if the text starts with "#" for AI search
        if text.hasPrefix("#") && text.count > 1 {
            let searchQuery = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !searchQuery.isEmpty {
                currentSearchQuery = searchQuery

                // Trigger AI search (for the search results overlay)
                aiSearchManager.search(query: searchQuery, in: messages)

                // Show the correct overlay based on search type
                if aiSearchManager.searchType == .messages {
                    showMessageSearchOverlay = true
                    showBusinessSearchOverlay = false
                } else if aiSearchManager.searchType == .businesses {
                    showBusinessSearchOverlay = true
                    showMessageSearchOverlay = false
                }

                // Also perform real-time highlighting of messages in chat
                highlightMatchingMessagesInChat(query: searchQuery)

                // Set a timer to clear highlighting after user stops typing
                highlightTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    // Only clear if user hasn't changed the search query
                    if currentSearchQuery == searchQuery {
                        clearMessageHighlighting()
                    }
                }
            } else {
                // Clear search if only "#" is typed
                currentSearchQuery = ""
                aiSearchManager.clearSearch()
                clearMessageHighlighting()
                showMessageSearchOverlay = false
                showBusinessSearchOverlay = false
            }
        } else {
            // Clear search if not a search query
            currentSearchQuery = ""
            aiSearchManager.clearSearch()
            clearMessageHighlighting()
            showMessageSearchOverlay = false
            showBusinessSearchOverlay = false
        }
    }

    private func highlightMatchingMessagesInChat(query: String) {
        // Find the first matching message and highlight it
        let queryLower = query.lowercased()

        // First try to find exact phrase matches, then word matches
        var foundMatch = false

        // Look for exact phrase matches first (higher priority)
        for message in messages.reversed() {  // Start from most recent
            let messageTextLower = message.text.lowercased()
            let userNameLower = message.user.lowercased()

            // Check if query matches as a phrase in message text or username
            if messageTextLower.contains(queryLower) || userNameLower.contains(queryLower) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    highlightedMessageId = message.id
                }
                foundMatch = true
                break
            }
        }

        // If no exact phrase match, look for individual word matches
        if !foundMatch && query.contains(" ") {
            let queryWords = query.lowercased().split(separator: " ")

            for message in messages.reversed() {
                let messageTextLower = message.text.lowercased()
                let userNameLower = message.user.lowercased()

                // Check if all query words are found in the message
                let allWordsFound = queryWords.allSatisfy { word in
                    messageTextLower.contains(word) || userNameLower.contains(word)
                }

                if allWordsFound {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        highlightedMessageId = message.id
                    }
                    foundMatch = true
                    break
                }
            }
        }

        // If still no match found, clear highlighting
        if !foundMatch {
            clearMessageHighlighting()
        }
    }

    private func clearMessageHighlighting() {
        highlightTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.3)) {
            highlightedMessageId = nil
        }
    }

    private func replyToMessage() {
        if let message = selectedMessage {
            replyingToMessage = message
            isTextFieldFocused = true
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            highlightedMessageId = nil
            showingMessageOptions = false
            selectedMessage = nil
        }
    }

    private func editMessage() {
        if let message = selectedMessage {
            editingMessage = message
            editingText = message.text
            isTextFieldFocused = true

            // Show editing animation
            withAnimation(.easeInOut(duration: 0.3)) {
                editingAnimationId = message.id
            }

            // Remove editing animation after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    editingAnimationId = nil
                }
            }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            highlightedMessageId = nil
            showingMessageOptions = false
            selectedMessage = nil
        }
    }

    // MARK: - Typing Indicator Management
    private func showTypingIndicator(for text: String) {
        if !text.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) {
                isShowingTypingIndicator = true
            }

            // Broadcast typing status to other users
            broadcastTypingStatus(true)

            // Auto-hide after 3 seconds of no activity
            typingTimer?.invalidate()
            typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    isShowingTypingIndicator = false
                }
                // Stop broadcasting typing status
                broadcastTypingStatus(false)
            }
        } else {
            typingTimer?.invalidate()
            withAnimation(.easeInOut(duration: 0.3)) {
                isShowingTypingIndicator = false
            }
            // Stop broadcasting typing status
            broadcastTypingStatus(false)
        }
    }

    // MARK: - Real-time Typing Indicators
    private var neighborhoodId: String {
        // Use a default neighborhood ID or get from user settings
        return "default_neighborhood"
    }

    // Helper to fetch display name from Firestore
    private func fetchDisplayName(forUID uid: String, completion: @escaping (String) -> Void) {
        // Check cache first
        if let cached = displayNamesCache[uid] {
            print("✅ Typing indicator: Using cached name for \(uid): \(cached)")
            completion(cached)
            return
        }
        
        #if canImport(FirebaseFirestore)
            let db = Firestore.firestore()
            print("🔍 Typing indicator: Fetching display name for UID: \(uid)")
            db.collection("users").document(uid).getDocument { snapshot, error in
                if let error = error {
                    print("❌ Typing indicator: Error fetching user document for \(uid): \(error.localizedDescription)")
                    completion("Someone")
                    return
                }
                
                guard let data = snapshot?.data() else {
                    print("❌ Typing indicator: No data found for user \(uid)")
                    completion("Someone")
                    return
                }
                
                print("📄 Typing indicator: User document data for \(uid):")
                print("   Keys: \(data.keys.joined(separator: ", "))")
                
                if let firstName = data["firstName"] as? String,
                   let lastName = data["lastName"] as? String {
                    let displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                    print("✅ Typing indicator: Found name for \(uid): \(displayName)")
                    
                    // Cache the result
                    DispatchQueue.main.async {
                        displayNamesCache[uid] = displayName
                        completion(displayName)
                    }
                } else {
                    // Log what fields are missing
                    let hasFirstName = data["firstName"] != nil
                    let hasLastName = data["lastName"] != nil
                    print("⚠️ Typing indicator: Missing name fields for \(uid)")
                    print("   firstName present: \(hasFirstName)")
                    print("   lastName present: \(hasLastName)")
                    
                    // Try fallback to "name" field
                    if let name = data["name"] as? String, !name.isEmpty {
                        print("✅ Typing indicator: Using 'name' field: \(name)")
                        DispatchQueue.main.async {
                            displayNamesCache[uid] = name
                            completion(name)
                        }
                    } else {
                        print("❌ Typing indicator: No name data available, using fallback")
                        completion("Someone")
                    }
                }
            }
        #else
            completion("Someone")
        #endif
    }

    private func broadcastTypingStatus(_ isTyping: Bool) {
        #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
            guard let uid = FirebaseManager.shared.getCurrentUserUID() else {
                print("⚠️ Typing indicator: Cannot broadcast - no UID available")
                return
            }
            
            let db = Firestore.firestore()
            let typingRef = db.collection("neighborhoods")
                .document("default")  // Using default for now, should be passed as parameter
                .collection("typing_status")
                .document(uid)

            if isTyping {
                // Set typing status with timestamp
                print("📡 Typing indicator: Broadcasting typing status for UID: \(uid)")
                typingRef.setData([
                    "user": uid,
                    "timestamp": FieldValue.serverTimestamp(),
                    "isTyping": true,
                ]) { error in
                    if let error = error {
                        print("❌ Typing indicator: Error setting typing status: \(error.localizedDescription)")
                    } else {
                        print("✅ Typing indicator: Successfully broadcast typing status")
                    }
                }
            } else {
                // Remove typing status
                print("📡 Typing indicator: Removing typing status for UID: \(uid)")
                typingRef.delete { error in
                    if let error = error {
                        print("❌ Typing indicator: Error removing typing status: \(error.localizedDescription)")
                    } else {
                        print("✅ Typing indicator: Successfully removed typing status")
                    }
                }
            }
        #endif
    }

    private func startTypingStatusListener() {
        #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
            guard let currentUID = FirebaseManager.shared.getCurrentUserUID() else {
                print("⚠️ Typing indicator: Cannot start listener - no UID available")
                return
            }
            
            print("👂 Typing indicator: Starting listener for current user UID: \(currentUID)")
            
            let db = Firestore.firestore()
            let typingRef = db.collection("neighborhoods")
                .document("default")  // Using default for now, should be passed as parameter
                .collection("typing_status")

            // Store the listener to cancel it later if needed
            typingRef.addSnapshotListener { [self] snapshot, error in
                if let error = error {
                    print("❌ Typing indicator: Error listening to typing status: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else {
                    print("⚠️ Typing indicator: No documents in snapshot")
                    return
                }

                print("📥 Typing indicator: Received \(documents.count) typing status documents")
                
                var currentlyTypingUIDs = Set<String>()
                let now = Date()

                for document in documents {
                    let data = document.data()
                    print("   📄 Document \(document.documentID): \(data)")
                    
                    if let uid = data["user"] as? String,
                        let timestamp = data["timestamp"] as? Timestamp,
                        let isTyping = data["isTyping"] as? Bool,
                        uid != currentUID,  // Don't show our own typing
                        isTyping
                    {
                        // Check if timestamp is recent (within 5 seconds)
                        let timeDiff = now.timeIntervalSince(timestamp.dateValue())
                        print("   ⏱️ User \(uid): isTyping=\(isTyping), age=\(String(format: "%.1f", timeDiff))s")
                        
                        if timeDiff < 5.0 {
                            currentlyTypingUIDs.insert(uid)
                            print("   ✅ Added \(uid) to typing users")
                        } else {
                            print("   ⚠️ Typing status too old (\(String(format: "%.1f", timeDiff))s), cleaning up")
                            // Clean up old typing status
                            document.reference.delete()
                        }
                    } else {
                        if let uid = data["user"] as? String {
                            if uid == currentUID {
                                print("   ⏭️ Skipping own typing status (\(uid))")
                            } else {
                                print("   ⚠️ Invalid typing status for \(uid)")
                            }
                        }
                    }
                }

                print("🔍 Typing indicator: Found \(currentlyTypingUIDs.count) users currently typing")
                
                // Fetch display names for all typing users
                let dispatchGroup = DispatchGroup()
                var displayNames = Set<String>()
                
                for uid in currentlyTypingUIDs {
                    dispatchGroup.enter()
                    fetchDisplayName(forUID: uid) { displayName in
                        displayNames.insert(displayName)
                        dispatchGroup.leave()
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    print("✅ Typing indicator: Updating UI with \(displayNames.count) names: \(displayNames)")
                    typingUsers = displayNames
                }
            }
        #endif
    }

    private func stopTypingStatusListener() {
        // Broadcast that we're no longer typing
        broadcastTypingStatus(false)
    }

    private func deleteMessage() {
        if let message = selectedMessage {
            // Start deletion animation sequence
            messageAnimationPhase[message.id] = .deleting

            withAnimation(.easeInOut(duration: 0.6)) {
                deletingMessageId = message.id
                deletedMessageIds.insert(message.id)
            }

            // Complete deletion after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.3)) {
                    messageAnimationPhase[message.id] = .deleted
                }

                // Remove from UI after fade out
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    messages.removeAll { $0.id == message.id }
                    deletingMessageId = nil
                    deletedMessageIds.remove(message.id)
                    messageAnimationPhase.removeValue(forKey: message.id)
                    saveMessages()

                    // Play sound effect for deleted message
                    AudioServicesPlaySystemSound(1155)  // Delete sound

                    // Delete in Firestore as well if available
                    #if canImport(FirebaseFirestore)
                        FirebaseManager.shared.deleteCommunityMessage(id: message.id.uuidString) {
                            err in
                            if let err = err { print("Failed to delete community message: \(err)") }
                        }
                    #endif
                }
            }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            highlightedMessageId = nil
            showingMessageOptions = false
            selectedMessage = nil
        }
    }

    private func moderateMessage() {
        // Admin moderation: scan and censor inappropriate words if auto-moderation is enabled
        if let message = selectedMessage {
            // Show shake animation before moderation
            withAnimation(.easeInOut(duration: 0.08).repeatCount(6, autoreverses: true)) {
                shakingMessageId = message.id
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let censoredText: String
                if contentModerationEnabled {
                    censoredText = SimpleContentModerator.censorMessage(
                        message.text, moderationEnabled: contentModerationEnabled)
                } else {
                    censoredText = message.text
                }
                let moderatedMessage = CommunityMessage(
                    id: message.id,
                    user: message.user,
                    text: censoredText,
                    timestamp: message.timestamp,
                    messageType: message.messageType,
                    isEdited: true,
                    editedAt: Date(),
                    replyTo: message.replyTo,
                    imageData: message.imageData,
                    imageURL: message.imageURL,
                    fileURL: message.fileURL,
                    audioURL: message.audioURL,
                    fileData: message.fileData,
                    fileName: message.fileName,
                    fileLocalURL: message.fileLocalURL,
                    audioFileName: message.audioFileName,
                    audioFileURL: message.audioFileURL,
                    isRead: message.isRead
                )

                if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                    self.messages[index] = moderatedMessage
                    self.saveMessages()
                    // Persist moderation edit to Firestore
                    // Delegate persistence to ChatMessagesManager so uploads and Firestore writes
                    // go through the centralized manager and listener/sanitization pipeline.
                    #if canImport(FirebaseFirestore)
                        chatManager.addMessage(moderatedMessage)
                    #endif
                }

                self.shakingMessageId = nil
            }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            highlightedMessageId = nil
            showingMessageOptions = false
            selectedMessage = nil
        }
    }

    private func copyMessage() {
        if let message = selectedMessage {
            UIPasteboard.general.string = message.text
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            highlightedMessageId = nil
            showingMessageOptions = false
            selectedMessage = nil
        }
    }

    private func warnUser() {
        // Send a warning message to the user
        if let message = selectedMessage {
            let warningMessage = CommunityMessage(
                id: UUID(),
                user: "System",
                text:
                    "⚠️ \(message.user) has received a warning from the admin for their recent message. Please follow community guidelines.",
                timestamp: Date(),
                messageType: .announcement,
                isEdited: false,
                editedAt: nil,
                imageData: nil,
                imageURL: nil,
                fileURL: nil,
                audioURL: nil,
                fileData: nil,
                fileName: nil,
                fileLocalURL: nil,
                audioFileName: nil,
                audioFileURL: nil,
                isRead: false
            )

            messages.append(warningMessage)
            saveMessages()
            // Persist warning via ChatMessagesManager so it appears for all users
            #if canImport(FirebaseFirestore)
                chatManager.addMessage(warningMessage)
            #endif
        }
        showingMessageOptions = false
        selectedMessage = nil
    }

    private func cancelReply() {
        replyingToMessage = nil
        isTextFieldFocused = false
    }

    private func cancelEdit() {
        editingMessage = nil
        editingText = ""
        isTextFieldFocused = false
    }

    private func clearInput() {
        if editingMessage != nil {
            editingText = ""
        } else {
            messageText = ""
        }
        isTextFieldFocused = false
    }

    private func saveEditedMessage() {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let editMessage = editingMessage else { return }

        let updatedMessage = CommunityMessage(
            id: editMessage.id,
            user: editMessage.user,
            text: trimmed,
            timestamp: editMessage.timestamp,
            messageType: editMessage.messageType,
            isEdited: true,
            editedAt: Date(),  // Set the current time as edit timestamp
            replyTo: editMessage.replyTo,
            imageData: editMessage.imageData,
            imageURL: editMessage.imageURL,
            fileURL: editMessage.fileURL,
            audioURL: editMessage.audioURL,
            fileData: editMessage.fileData,
            fileName: editMessage.fileName,
            fileLocalURL: editMessage.fileLocalURL,
            audioFileName: editMessage.audioFileName,
            audioFileURL: editMessage.audioFileURL,
            isRead: editMessage.isRead
        )

        if let index = messages.firstIndex(where: { $0.id == editMessage.id }) {
            // Show edit completion animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                editingAnimationId = editMessage.id
                messages[index] = updatedMessage
            }

            // Remove edit animation after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    editingAnimationId = nil
                }
            }

            saveMessages()
        }

        // Clear edit state
        editingMessage = nil
        editingText = ""
        isTextFieldFocused = false
        // Play sound effect for edited message
        AudioServicesPlaySystemSound(1057)  // Tink sound for edit
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Persist edit via ChatMessagesManager for consistent behavior
        chatManager.addMessage(updatedMessage)
    }

    private func clearAllMessages() {
        guard isAdmin else { return }
        messages.removeAll()
        saveMessages()
    }

    private func exportChat() {
        // Implement chat export functionality
    }

    private func shareInviteLink() {
        // Implement invite link sharing
        let inviteText =
            "Join our NeighborHub community chat! Download the app and connect with neighbors in your area."
        if let url = URL(string: "https://neighborhub.app/invite") {
            let activityVC = UIActivityViewController(
                activityItems: [inviteText, url], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first,
                let rootVC = window.rootViewController
            {
                rootVC.present(activityVC, animated: true)
            }
        }
    }

    private func clearPersonalData() {
        // Clear user's own messages locally and in Firestore
        let toDelete = messages.filter { $0.user == currentUserFullName }
        messages.removeAll { $0.user == currentUserFullName }
        saveMessages()
        #if canImport(FirebaseFirestore)
            for m in toDelete {
                FirebaseManager.shared.deleteCommunityMessage(id: m.id.uuidString) { err in
                    if let err = err { print("Failed to delete personal message: \(err)") }
                }
            }
        #endif
    }

    private func clearAppStorage() {
        // Removed: Clear App Storage UI no longer available. Function retained as no-op for safety.
    }

    private func performClearAppStorage() {
        // Clear only the current user's personal app data and settings
        // Keep shared community data intact

        // Clear personal chat settings
        chatNotificationsEnabled = true
        chatSoundEnabled = true
        chatShowTimestamps = true
        chatFontSize = 16.0
        chatTheme = "auto"
        chatBackgroundStyle = "default"
        chatAutoScroll = true
        chatShowTypingIndicators = true
        showUserCredentials = true
        contentModerationEnabled = true

        // Clear AI search history and cache
        aiSearchManager.clearSearch()

        // Clear pinned messages (only for this user session)
        pinnedMessagesManager.pinnedMessages.removeAll()

        // Clear user's own messages from the chat
        messages.removeAll { $0.user == currentUserFullName }
        saveMessages()

        // Clear business discovery cache
        aiSearchManager.clearSearch()

        // Clear any temporary UI state
        messageText = ""
        editingText = ""
        replyingToMessage = nil
        editingMessage = nil
        selectedMessage = nil
        capturedImage = nil
        attachedFileURL = nil
        attachedFileName = nil
        highlightedMessageId = nil
        justAddedMessageId = nil

        // Clear shared business cards created by this user
        sharedBusinessCards.removeAll { $0.sharedBy == currentUserFullName }

        // Note: We deliberately do NOT clear:
        // - userName/userSurname (user identity)
        // - committeeMembers (admin settings)
        // - communityMessagesData (shared community messages from other users)
        // - communityGuidelines (shared community rules)
        // - Other users' messages or data

        // Provide user feedback
        // You could add a success message here if desired
    }

    private func clearAllData() {
        // Clear all messages (admin only)
        messages.removeAll()
        saveMessages()
        #if canImport(FirebaseFirestore)
            // Admin: delete all documents in communityMessages
            let db = Firestore.firestore()
            db.collection("communityMessages").getDocuments { snap, err in
                guard let docs = snap?.documents else { return }
                for doc in docs {
                    // Delete document (no completion handler needed)
                    doc.reference.delete()
                }
            }
        #endif
    }

    private func sendFeedback() {
        // ...removed sendFeedback function...
    }

    // MARK: - Business Sharing
    private func shareBusinessToChat(_ business: LocalBusiness) {
        let sharedCard = SharedBusinessCard(
            business: business,
            sharedBy: currentUserFullName,
            messageText: "Check out this local business!"
        )

        // Create a specialized business card message with business data embedded
        let businessDataString = try? JSONEncoder().encode(business)
        let businessDataBase64 = businessDataString?.base64EncodedString()

        let newMessage = CommunityMessage(
            id: UUID(),
            user: currentUserFullName,
            text: businessDataBase64 ?? "📍 Shared a local business",  // Store business data in text field
            timestamp: Date(),
            messageType: .businessCard,
            isEdited: false,
            editedAt: nil,
            replyTo: nil,
            imageData: nil,
            imageURL: nil,
            fileURL: nil,
            audioURL: nil,
            fileData: nil,
            fileName: business.name,  // Store business name in filename for easy access
            fileLocalURL: nil,
            audioFileName: nil,
            audioFileURL: nil,
            isRead: false
        )

        // Add to messages with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            messages.append(newMessage)
            justAddedMessageId = newMessage.id
        }

        // Store the shared business card separately (for backward compatibility)
        sharedBusinessCards.append(sharedCard)

        // Auto-clear animation after brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.3)) {
                justAddedMessageId = nil
            }
        }

        saveMessages()

        // Clear the AI search
        aiSearchManager.clearSearch()

        // Success feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Persist shared business card via ChatMessagesManager for consistent behavior
        #if canImport(FirebaseFirestore)
            chatManager.addMessage(newMessage)
        #endif
    }

    // MARK: - Shared Results to Chat
    private func sendSharedResultsToChat(_ text: String) {
        let displayName =
            showUserCredentials
            ? (currentUserFullName.isEmpty ? "Anonymous" : currentUserFullName)
            : "Anonymous Neighbor"

        let newMessage = CommunityMessage(
            id: UUID(),
            user: displayName,
            text: text,
            timestamp: Date(),
            messageType: .text,
            isEdited: false,
            editedAt: nil,
            replyTo: nil,
            imageData: nil,
            imageURL: nil,
            fileURL: nil,
            audioURL: nil,
            fileData: nil,
            fileName: nil,
            fileLocalURL: nil,
            audioFileName: nil,
            audioFileURL: nil,
            isRead: false
        )

        // Add to messages with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            messages.append(newMessage)
            justAddedMessageId = newMessage.id
        }

        // Auto-clear animation after brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.3)) {
                justAddedMessageId = nil
            }
        }

        saveMessages()

        // Clear the AI search
        aiSearchManager.clearSearch()

        // Success feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Persist shared results via ChatMessagesManager for consistent behavior
        #if canImport(FirebaseFirestore)
            chatManager.addMessage(newMessage)
        #endif
    }

    private func sendBusinessListToChat(_ businesses: [LocalBusiness]) {
        let displayName =
            showUserCredentials
            ? (currentUserFullName.isEmpty ? "Anonymous" : currentUserFullName)
            : "Anonymous Neighbor"

        // Create business list data
        let businessListData = BusinessListData(
            businesses: businesses,
            searchQuery: "Business Discovery"
        )

        // Encode the business list data
        let encodedData: String
        do {
            let jsonData = try JSONEncoder().encode(businessListData)
            encodedData = jsonData.base64EncodedString()
        } catch {
            print("Failed to encode business list: \(error)")
            // Fallback to text
            let fallbackText = "🤖 Found \(businesses.count) businesses in your area"
            sendSharedResultsToChat(fallbackText)
            return
        }

        let newMessage = CommunityMessage(
            id: UUID(),
            user: displayName,
            text: encodedData,
            timestamp: Date(),
            messageType: .businessList,
            isEdited: false,
            editedAt: nil,
            replyTo: nil,
            imageData: nil,
            imageURL: nil,
            fileURL: nil,
            audioURL: nil,
            fileData: nil,
            fileName: nil,
            fileLocalURL: nil,
            audioFileName: nil,
            audioFileURL: nil,
            isRead: false
        )

        // Add to messages with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            messages.append(newMessage)
            justAddedMessageId = newMessage.id
        }

        // Auto-clear animation after brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.3)) {
                justAddedMessageId = nil
            }
        }

        saveMessages()

        // Clear the AI search
        aiSearchManager.clearSearch()

        // Success feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Persist business list via ChatMessagesManager for consistent behavior
        #if canImport(FirebaseFirestore)
            chatManager.addMessage(newMessage)
        #endif
    }

    // MARK: - Paste and File Handling
    private func handlePastedContent() {
        // Check for various types of content in pasteboard
        let pasteboard = UIPasteboard.general

        // Check for GIF data first (before hasImages, as GIFs need special handling)
        if let gifData = pasteboard.data(forPasteboardType: "com.compuserve.gif") {
            print("📎 GIF detected in pasteboard (\(gifData.count) bytes)")
            handlePastedGIF(data: gifData)
            return
        }
        
        // Also check for public.gif type
        if let gifData = pasteboard.data(forPasteboardType: "public.gif") {
            print("📎 GIF (public.gif) detected in pasteboard (\(gifData.count) bytes)")
            handlePastedGIF(data: gifData)
            return
        }

        // Prioritize images (non-GIF)
        if pasteboard.hasImages, let image = pasteboard.image {
            capturedImage = image
            return
        }

        // Then check for URLs/files
        if pasteboard.hasURLs, let url = pasteboard.url {
            messageText += url.absoluteString
            return
        }

        // Finally text
        if pasteboard.hasStrings, let text = pasteboard.string {
            messageText += text
        }
    }
    
    private func handlePastedGIF(data: Data) {
        // Save GIF to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let gifFileName = "\(UUID().uuidString).gif"
        let gifURL = tempDir.appendingPathComponent(gifFileName)
        
        do {
            try data.write(to: gifURL)
            print("✅ GIF saved to temporary location: \(gifURL.path)")
            print("   - GIF file size: \(data.count) bytes (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))")
            print("   - GIF filename: \(gifFileName)")
            
            // Verify file was actually written
            if FileManager.default.fileExists(atPath: gifURL.path) {
                print("   - ✅ Verified: File exists on disk")
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? UInt64 {
                    print("   - File size on disk: \(fileSize) bytes")
                }
            } else {
                print("   - ❌ WARNING: File does NOT exist on disk!")
            }
            
            // Treat GIF as an attached file (like video)
            attachedFileURL = gifURL
            attachedFileName = gifFileName
            
            print("📎 GIF attached as file - ready to send")
            print("   - attachedFileURL: \(gifURL.absoluteString)")
            print("   - attachedFileName: \(gifFileName)")
        } catch {
            print("❌ Failed to save pasted GIF: \(error.localizedDescription)")
            NotificationCenter.default.post(
                name: .attachmentCopyErrorNotification,
                object: "Failed to save pasted GIF: \(error.localizedDescription)"
            )
        }
    }

    private func canPasteContent() -> Bool {
        let pasteboard = UIPasteboard.general
        return pasteboard.hasImages || pasteboard.hasStrings || pasteboard.hasURLs
    }

    // MARK: - File Handling Helpers
    private func fileIcon(for fileName: String) -> String {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        switch fileExtension {
        case "pdf":
            return "doc.richtext"
        case "doc", "docx":
            return "doc.text"
        case "xls", "xlsx":
            return "tablecells"
        case "ppt", "pptx":
            return "rectangle.stack"
        case "zip", "rar", "7z":
            return "archivebox"
        case "mp3", "wav", "m4a":
            return "music.note"
        case "mp4", "mov", "avi":
            return "video"
        case "jpg", "jpeg", "png", "gif":
            return "photo"
        case "txt":
            return "doc.plaintext"
        default:
            return "doc"
        }
    }

    private func fileSizeString(for url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            // If we can't get file size, return empty string
        }
        return ""
    }

    private func saveMessages() {
        // Sanitize messages: remove large binary blobs (images, files, local file paths) before saving to AppStorage/UserDefaults
        let sanitized = messages.map { msg -> CommunityMessage in
            return CommunityMessage(
                id: msg.id,
                user: msg.user,
                text: msg.text,
                timestamp: msg.timestamp,
                messageType: msg.messageType,
                isEdited: msg.isEdited,
                editedAt: msg.editedAt,
                replyTo: msg.replyTo,
                imageData: nil,  // remove embedded image bytes
                imageURL: msg.imageURL,  // keep remote URL if available
                fileURL: msg.fileURL,  // keep remote file URL
                audioURL: msg.audioURL,  // keep remote audio URL
                fileData: nil,  // remove embedded file bytes
                fileName: msg.fileName,
                fileLocalURL: nil,  // remove local file path to avoid storing large paths/data
                audioFileName: msg.audioFileName,
                audioFileURL: nil,  // remove local audio file path
                isRead: msg.isRead
            )
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            communityMessagesData = String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func loadMessages() {
        // Let ChatMessagesManager handle all message loading - don't interfere with Firestore listeners
        return
    }

    private func initializeCommunityGuidelines() {
        if communityGuidelines.isEmpty {
            communityGuidelines = """
                1. Be respectful and kind to all neighbors
                2. Keep discussions relevant to the community
                3. No spam or excessive promotional content
                4. Respect privacy and confidentiality
                5. Report inappropriate behavior to moderators
                6. Use appropriate language suitable for all ages
                7. No sharing of personal contact information publicly
                8. Respect different opinions and viewpoints
                """
        }
    }

    private func addWelcomeMessagesIfNeeded() {
        guard messages.isEmpty else { return }

        let welcomeMessages = [
            CommunityMessage(
                id: UUID(), user: "System", text: "Welcome to the NeighborHub community chat! 🏘️",
                timestamp: Date().addingTimeInterval(-3600), messageType: .system, isEdited: false,
                editedAt: nil, replyTo: nil, imageData: nil, imageURL: nil, fileURL: nil,
                audioURL: nil, fileData: nil, fileName: nil, fileLocalURL: nil, audioFileName: nil,
                audioFileURL: nil, isRead: true),
            CommunityMessage(
                id: UUID(), user: showUserCredentials ? "Alice Johnson" : "Anonymous Neighbor",
                text: "Hi everyone! Excited to connect with neighbors here.",
                timestamp: Date().addingTimeInterval(-1800), messageType: .text, isEdited: false,
                editedAt: nil, replyTo: nil, imageData: nil, imageURL: nil, fileURL: nil,
                audioURL: nil, fileData: nil, fileName: nil, fileLocalURL: nil, audioFileName: nil,
                audioFileURL: nil, isRead: false),
            CommunityMessage(
                id: UUID(), user: showUserCredentials ? "Bob Smith" : "Anonymous Neighbor",
                text: "Great to see this community coming together! 👋",
                timestamp: Date().addingTimeInterval(-900), messageType: .text, isEdited: false,
                editedAt: nil, replyTo: nil, imageData: nil, imageURL: nil, fileURL: nil,
                audioURL: nil, fileData: nil, fileName: nil, fileLocalURL: nil, audioFileName: nil,
                audioFileURL: nil, isRead: false),
        ]

        messages = welcomeMessages
        saveMessages()
    }
}

// MARK: - Supporting Data Models
// MARK: - Enhanced Content Moderation System
struct SimpleContentModerator {
    // Comprehensive list of words to filter when moderation is enabled
    static let inappropriateWords: [String] = [
        // Profanity
        "fuck", "fucking", "fucked", "fucker", "fuckers", "fucks", "fck", "f*ck",
        "shit", "shits", "shitting", "shitty", "sht", "sh*t",
        "bitch", "bitches", "bitching", "b*tch",
        "asshole", "assholes", "ass", "asses", "a**", "a*s",
        "bastard", "bastards", "b*stard",
        "damn", "damned", "dammit", "d*mn",
        // "hell" removed to prevent false positives with "hello", "shell", etc.
        "dick", "dicks", "d*ck",
        "piss", "pissed", "pissing", "p*ss",
        "cock", "cocks", "c*ck",
        "slut", "sluts", "sl*t",
        "whore", "whores", "wh*re",
        "crap", "crappy", "cr*p",
        "prick", "pr*ck",
        "douche", "douchebag",
        "fag", "faggot", "f*g",
        "retard", "retarded", "r*tard",

        // Hate speech and slurs
        "nigger", "nigga", "n*gger", "n*gga",
        "chink", "ch*nk",
        "spic", "sp*c",
        "kike", "k*ke",
        "wetback", "w*tback",
        "gook", "g**k",
        "raghead", "r*ghead",

        // Sexual content
        "penis", "vagina", "pussy", "p*ssy",
        "tits", "boobs", "t*ts",
        "nude", "naked", "n*de",
        "sex", "sexy", "horny",
        "porn", "porno", "p*rn",

        // Violence
        "kill", "murder", "die", "death", "dead",
        "suicide", "kys", "hang yourself",
        "shoot", "stab", "knife", "gun",

        // Drugs
        "weed", "marijuana", "cocaine", "heroin", "meth",
        "drug", "drugs", "high", "stoned",
    ]

    static func shouldCensorMessage(_ text: String, moderationEnabled: Bool) -> Bool {
        guard moderationEnabled else { return false }

        let lowercaseText = text.lowercased()

        // Check for inappropriate words using simple string matching with word boundaries
        return inappropriateWords.contains { word in
            let wordLower = word.lowercased()

            // Create a pattern that matches the word with word boundaries
            // Use simple string search with word boundary checking
            let words = lowercaseText.components(separatedBy: CharacterSet.alphanumerics.inverted)
            return words.contains { textWord in
                // Exact match or close variants (handling asterisks in filter words)
                let cleanWord = textWord.trimmingCharacters(in: .whitespacesAndNewlines)
                let filterWord = wordLower.replacingOccurrences(of: "*", with: "")

                return cleanWord == filterWord || cleanWord == wordLower
                    || (filterWord.count > 3 && cleanWord.contains(filterWord))
            }
        }
    }

    static func censorMessage(_ text: String, moderationEnabled: Bool) -> String {
        guard moderationEnabled else { return text }

        var censored = text
        let words = inappropriateWords

        for word in words {
            let cleanWord = word.replacingOccurrences(of: "*", with: "")

            // Replace using case-insensitive search
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: cleanWord) + "\\b"

            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(location: 0, length: censored.utf16.count)
                let replacement = String(repeating: "*", count: cleanWord.count)
                censored = regex.stringByReplacingMatches(
                    in: censored, options: [], range: range, withTemplate: replacement)
            } catch {
                // Fallback to simple string replacement if regex fails
                let replacement = String(repeating: "*", count: cleanWord.count)
                censored = censored.replacingOccurrences(
                    of: cleanWord, with: replacement, options: [.caseInsensitive])
            }
        }

        return censored
    }

    static func getWarningMessage(moderationEnabled: Bool) -> String {
        return moderationEnabled
            ? "This message contains content that may be inappropriate for the community." : ""
    }
}
struct CommunityMessage: Identifiable, Codable {
    let id: UUID
    let user: String
    let text: String
    let timestamp: Date
    let messageType: MessageType
    let isEdited: Bool
    let editedAt: Date?
    let replyTo: UUID?
    var imageData: Data?  // Store image as Data for persistence
    var imageLocalURL: String?  // Local file system path for saved images
    // Remote URLs from Firestore storage (if available)
    var imageURL: URL?
    var fileURL: URL?
    var audioURL: URL?
    var fileData: Data?  // Store file as Data for persistence
    let fileName: String?  // Store original filename
    var fileLocalURL: String?  // Local file system path for attachments (videos/files)
    let audioFileName: String?  // Store audio filename (e.g., voice-uuid.m4a)
    var audioFileURL: String?  // Local file system path to audio file
    var isRead: Bool  // Track if message has been read by current user
    
    // Pinned message fields
    var pinned: Bool  // Whether this message is pinned
    var pinnedBy: String?  // User who pinned the message
    var pinnedAt: Date?  // When it was pinned

    init(
        id: UUID,
        user: String,
        text: String,
        timestamp: Date,
        messageType: MessageType,
        isEdited: Bool,
        editedAt: Date? = nil,
        replyTo: UUID? = nil,
        imageData: Data? = nil,
        imageLocalURL: String? = nil,
        imageURL: URL? = nil,
        fileURL: URL? = nil,
        audioURL: URL? = nil,
        fileData: Data? = nil,
        fileName: String? = nil,
        fileLocalURL: String? = nil,
        audioFileName: String? = nil,
        audioFileURL: String? = nil,
        isRead: Bool = false,
        pinned: Bool = false,
        pinnedBy: String? = nil,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.user = user
        self.text = text
        self.timestamp = timestamp
        self.messageType = messageType
        self.isEdited = isEdited
        self.editedAt = editedAt
        self.imageURL = imageURL
        self.fileURL = fileURL
        self.audioURL = audioURL
        self.replyTo = replyTo
        self.imageData = imageData
        self.fileData = fileData
        self.fileName = fileName
        self.fileLocalURL = fileLocalURL
        self.audioFileName = audioFileName
        self.audioFileURL = audioFileURL
        self.isRead = isRead
        self.pinned = pinned
        self.pinnedBy = pinnedBy
        self.pinnedAt = pinnedAt
    }

    // Helper to get UIImage from stored data
    var image: UIImage? {
        // Prefer a local saved image file if present
        if let local = imageLocalURL {
            let url = URL(fileURLWithPath: local)
            if FileManager.default.fileExists(atPath: url.path), let d = try? Data(contentsOf: url),
                let ui = UIImage(data: d)
            {
                return ui
            }
        }
        guard let imageData = imageData else { return nil }
        return UIImage(data: imageData)
    }

    var initials: String {
        let comps = user.split(separator: " ")
        let first = comps.first?.first.map { String($0) } ?? ""
        let last = comps.dropFirst().first?.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }

    var userColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let hash = abs(user.hashValue)
        return colors[hash % colors.count]
    }
}

enum MessageType: String, Codable {
    case text, system, image, announcement, mixed, file, businessCard, businessList, audio
}

// MARK: - Voice Recorder Helper
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private(set) var audioURL: URL?

    func startRecording(to url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        audioURL = url
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        audioRecorder?.record()
    }

    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func cancelRecording() {
        audioRecorder?.stop()
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioRecorder = nil
        audioURL = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// MARK: - Business List Data Structure
struct BusinessListData: Codable {
    let businesses: [LocalBusiness]
    let searchQuery: String
    let sharedAt: Date

    init(businesses: [LocalBusiness], searchQuery: String) {
        self.businesses = businesses
        self.searchQuery = searchQuery
        self.sharedAt = Date()
    }
}

struct MessageGroup {
    let date: Date
    let messages: [CommunityMessage]
}

// MARK: - Supporting Views
struct MessageBubbleView: View {
    let message: CommunityMessage
    let isCurrentUser: Bool
    let isHighlighted: Bool
    let isJustAdded: Bool
    let isDeleting: Bool
    let isEditingAnimation: Bool
    let isShaking: Bool
    let animationPhase: AnimationPhase
    let allMessages: [CommunityMessage]  // NEW: Access to all messages for reply lookup
    let onLongPress: () -> Void
    // Optional callback when a business card inside this bubble is tapped
    let onBusinessTap: ((LocalBusiness) -> Void)?
    // Preview callbacks
    let onPreviewImage: ((UIImage) -> Void)?
    let onPreviewVideo: ((URL) -> Void)?
    let onPreviewDocument: ((URL) -> Void)?
    @AppStorage("chatFontSize") private var chatFontSize: Double = 16.0
    @AppStorage("chatShowTimestamps") private var chatShowTimestamps: Bool = true

    // Moderation settings
    @AppStorage("contentModerationEnabled") private var contentModerationEnabled: Bool = true
    @AppStorage("showModerationWarnings") private var showModerationWarnings: Bool = true

    // Spring entrance animation state
    @State private var hasAppeared: Bool = false
    // Upload progress tracking per message
    @State private var uploadProgress: Double? = nil
    @State private var uploadType: String? = nil
    @State private var uploadError: String? = nil

    // Computed properties for content moderation
    private var shouldShowContentWarning: Bool {
        guard contentModerationEnabled else { return false }
        return SimpleContentModerator.shouldCensorMessage(
            message.text, moderationEnabled: contentModerationEnabled)
    }

    private var displayedText: String {
        if shouldShowContentWarning {
            return SimpleContentModerator.censorMessage(message.text, moderationEnabled: true)
        }
        return message.text
    }

    var body: some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 50) }

            if !isCurrentUser {
                Circle()
                    .fill(message.userColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(message.initials)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(message.userColor)
                    )
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser && message.messageType != .system {
                    // Display only first name (do not show surname)
                    Text(
                        message.user.split(separator: " ").first.map { String($0) } ?? message.user
                    )
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(message.userColor)
                }

                if let replyToId = message.replyTo {
                    replyContextView(replyToId: replyToId)
                }

                HStack {
                    if isCurrentUser && chatShowTimestamps {
                        messageStatusIndicator
                    }

                    // Main message content with dramatic effects
                    Group {
                        if message.messageType == .audio {
                            AudioMessageView(message: message)
                        } else if message.messageType == .mixed {
                            // Mixed content: Image + Text (prefer remote image URL)
                            VStack(alignment: .leading, spacing: 8) {
                                if let imageURL = message.imageURL {
                                    AsyncImage(url: imageURL) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                                .frame(maxHeight: 180)
                                        case .success(let imageView):
                                            imageView
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxHeight: 180)
                                                .cornerRadius(12)
                                                .onTapGesture {
                                                    // download image data for preview
                                                    Task {
                                                        if let data = try? await
                                                            (URLSession.shared.data(from: imageURL))
                                                            .0, let ui = UIImage(data: data)
                                                        {
                                                            onPreviewImage?(ui)
                                                        }
                                                    }
                                                }
                                        case .failure(_):
                                            if let image = message.image {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(maxHeight: 180)
                                                    .cornerRadius(12)
                                                    .onTapGesture { onPreviewImage?(image) }
                                            } else {
                                                Color.gray.frame(height: 120).cornerRadius(12)
                                            }
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                } else if let image = message.image {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 180)
                                        .cornerRadius(12)
                                        .onTapGesture { onPreviewImage?(image) }
                                }

                                if !message.text.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Show content warning if applicable
                                        if shouldShowContentWarning && showModerationWarnings {
                                            contentWarningView
                                        }
                                        
                                        TappableLinksText(
                                            text: displayedText,
                                            fontSize: chatFontSize,
                                            textColor: dynamicTextColor
                                        )
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 4)
                                    .background(
                                        // 3D, semi-transparent, rounded, blurred background using native SwiftUI
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .shadow(
                                                color: Color.black.opacity(0.18), radius: 10,
                                                x: 0, y: 3)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(
                                                dynamicBorderColor, lineWidth: borderLineWidth
                                            )
                                            .animation(
                                                .easeInOut(duration: 1.0),
                                                value: dynamicBorderColor
                                            )
                                            .animation(
                                                .easeInOut(duration: 1.0),
                                                value: borderLineWidth)
                                    )
                                }
                            }
                        } else if message.messageType == .file
                            || (message.messageType == .mixed && message.fileName != nil)
                        {
                            FileMessageView(
                                message: message, chatFontSize: chatFontSize,
                                dynamicTextColor: dynamicTextColor,
                                onPreviewDocument: onPreviewDocument,
                                onPreviewVideo: onPreviewVideo, onPreviewImage: onPreviewImage,
                                onLongPress: onLongPress
                            )
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(dynamicBubbleColor)
                                    .shadow(
                                        color: .black.opacity(isCurrentUser ? 0.15 : 0.1),
                                        radius: 4, x: 0, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(dynamicBorderColor, lineWidth: borderLineWidth)
                                    .animation(.easeInOut(duration: 1.0), value: dynamicBorderColor)
                                    .animation(.easeInOut(duration: 1.0), value: borderLineWidth)
                            )
                        } else if message.messageType == .image {
                            // Image only - prefer remote URL, fallback to local image
                            if let imageURL = message.imageURL {
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(maxHeight: 180)
                                    case .success(let imageView):
                                        imageView
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 180)
                                            .cornerRadius(12)
                                            .onTapGesture {
                                                Task {
                                                    if let data = try? await
                                                        (URLSession.shared.data(from: imageURL)).0,
                                                        let ui = UIImage(data: data)
                                                    {
                                                        onPreviewImage?(ui)
                                                    }
                                                }
                                            }
                                    case .failure(_):
                                        if let image = message.image {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxHeight: 180)
                                                .cornerRadius(12)
                                                .onTapGesture { onPreviewImage?(image) }
                                        } else {
                                            Color.gray.frame(height: 120).cornerRadius(12)
                                        }
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else if let image = message.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .cornerRadius(12)
                                    .onTapGesture { onPreviewImage?(image) }
                            }
                        } else if let localPath = message.fileLocalURL, isVideoFile(localPath) {
                            ImageVideoPreviewView(
                                filePath: localPath, onPreviewVideo: onPreviewVideo,
                                onPreviewImage: onPreviewImage
                            )
                            .frame(height: 200)
                            .cornerRadius(12)
                        } else {
                            // Text only
                            messageBubble
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(highlightBackgroundColor)
                            .scaleEffect(isHighlighted ? 1.05 : 1.0)
                            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 4)
                    )
                    .overlay(
                        // Show upload progress bar if available
                        Group {
                            if let p = uploadProgress {
                                VStack {
                                    Spacer()
                                    ProgressView(value: p)
                                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                        .frame(height: 3)
                                        .cornerRadius(2)
                                        .padding([.leading, .trailing], 8)
                                }
                            }
                        }
                    )
                    .overlay(enhancedStateOverlay)
                    .modifier(
                        BubbleTransformModifier(
                            scaleEffect: combinedScaleEffect,
                            opacity: deletionOpacity,
                            offsetX: shakingOffset,
                            offsetY: editBounceOffset,
                            rotationDegrees: deletionRotation,
                            blurRadius: deletionBlur
                        )
                    )
                    .modifier(
                        BubbleAnimationModifier(
                            isJustAdded: isJustAdded,
                            isDeleting: isDeleting,
                            isEditingAnimation: isEditingAnimation,
                            isShaking: isShaking,
                            isHighlighted: isHighlighted
                        )
                    )
                    .onAppear {
                        // Listen for upload progress notifications for this message
                        NotificationCenter.default.addObserver(
                            forName: .communityUploadProgress, object: nil, queue: .main
                        ) { note in
                            guard let info = note.userInfo as? [String: Any],
                                let id = info["id"] as? String, id == message.id.uuidString
                            else { return }
                            let prog = info["progress"] as? Double ?? 0
                            self.uploadProgress = prog
                            self.uploadType = info["type"] as? String
                            // Clear any previous upload error when progress restarts
                            if prog > 0 { self.uploadError = nil }
                        }
                        NotificationCenter.default.addObserver(
                            forName: .communityUploadCompleted, object: nil, queue: .main
                        ) { note in
                            guard let info = note.userInfo as? [String: Any],
                                let id = info["id"] as? String, id == message.id.uuidString
                            else { return }
                            // If uploader reported an error, surface it
                            if let errObj = info["error"] {
                                if let e = errObj as? Error {
                                    self.uploadError = e.localizedDescription
                                } else if let s = errObj as? String {
                                    self.uploadError = s
                                } else if let n = errObj as? NSError {
                                    self.uploadError = n.localizedDescription
                                } else {
                                    self.uploadError = "Upload failed"
                                }
                            } else {
                                self.uploadError = nil
                            }
                            self.uploadProgress = nil
                            self.uploadType = nil
                        }
                    }
                    .onDisappear {
                        NotificationCenter.default.removeObserver(
                            self, name: .communityUploadProgress, object: nil)
                        NotificationCenter.default.removeObserver(
                            self, name: .communityUploadCompleted, object: nil)
                    }

                    if !isCurrentUser && chatShowTimestamps {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if message.isEdited && message.messageType != .system {
                                HStack(spacing: 2) {
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("edited")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            }
                        }
                    }
                }
            }

            if !isCurrentUser { Spacer(minLength: 50) }
        }
        .scaleEffect(springEntranceScale)
        .opacity(springEntranceOpacity)
        .offset(x: animationPhase == .appearing ? (isCurrentUser ? 50 : -50) : 0)
        .rotation3DEffect(
            .degrees(animationPhase == .editing ? 2 : 0),
            axis: (x: 0, y: 1, z: 0)
        )
        .shadow(
            color: shadowColor,
            radius: shadowRadius,
            x: 0,
            y: shadowRadius > 0 ? 2 : 0
        )
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animationPhase)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: springEntranceScale)
        .animation(.easeInOut(duration: 0.3), value: springEntranceOpacity)
        .onAppear {
            // Spring entrance animation when message first appears
            if !hasAppeared {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.3)) {
                    hasAppeared = true
                }
            }
        }
        .onLongPressGesture {
            onLongPress()
        }
    }

    private func replyContextView(replyToId: UUID) -> some View {
        // Find the original message being replied to
        let originalMessage = allMessages.first { $0.id == replyToId }

        return HStack(spacing: 8) {
            Rectangle()
                .frame(width: 3)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                if let original = originalMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(extractFirstName(from: original.user))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }

                    // Show appropriate content preview
                    Group {
                        if original.text.isEmpty
                            && (original.imageData != nil || original.fileData != nil)
                        {
                            HStack(spacing: 4) {
                                Image(systemName: original.imageData != nil ? "photo" : "paperclip")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(
                                    original.imageData != nil
                                        ? "Photo"
                                        : (isVideoFile(original.fileName ?? "")
                                            ? "Video" : (original.fileName ?? "Attachment"))
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                            }
                        } else {
                            Text(original.text)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("Message not found")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6).opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.bottom, 4)
    }

    // Helper function to extract first name (same as in main view)
    private func extractFirstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: " ")
        return components.first?.capitalized ?? trimmed
    }

    private var messageBubble: some View {
        Group {
            if message.messageType == .businessCard {
                businessCardContent
            } else if message.messageType == .businessList {
                businessListContent
            } else {
                // Unified bubble for text-only and mixed
                VStack(alignment: .leading, spacing: 8) {
                    if message.messageType == .image || message.messageType == .mixed {
                        if let imageURL = message.imageURL {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView().frame(maxHeight: 180)
                                case .success(let imageView):
                                    imageView
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 180)
                                        .cornerRadius(12)
                                        .onTapGesture {
                                            Task {
                                                if let data = try? await
                                                    (URLSession.shared.data(from: imageURL)).0,
                                                    let ui = UIImage(data: data)
                                                {
                                                    onPreviewImage?(ui)
                                                }
                                            }
                                        }
                                case .failure(_):
                                    if let image = message.image {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 180)
                                            .cornerRadius(12)
                                            .onTapGesture { onPreviewImage?(image) }
                                    } else {
                                        Color.gray.frame(height: 120).cornerRadius(12)
                                    }
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else if let image = message.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .cornerRadius(12)
                                .onTapGesture { onPreviewImage?(image) }
                        }
                    }
                    if let fileName = message.fileName,
                        message.messageType == .file || message.messageType == .mixed
                    {
                        HStack(spacing: 8) {
                            Image(systemName: fileIcon(for: message.fileName ?? ""))
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileName)
                                    .font(.system(size: chatFontSize, weight: .medium))
                                    .foregroundColor(dynamicTextColor)
                                    .lineLimit(1)
                                if let fileData = message.fileData {
                                    Text(
                                        ByteCountFormatter.string(
                                            fromByteCount: Int64(fileData.count), countStyle: .file)
                                    )
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .onTapGesture {
                            if let localPath = message.fileLocalURL {
                                let url = URL(fileURLWithPath: localPath)
                                onPreviewDocument?(url)
                            } else if let data = message.fileData, let name = message.fileName {
                                let tmp = FileManager.default.temporaryDirectory
                                    .appendingPathComponent("\(UUID().uuidString)-\(name)")
                                do {
                                    try data.write(to: tmp, options: .atomic)
                                    onPreviewDocument?(tmp)
                                } catch {
                                    NotificationCenter.default.post(
                                        name: .attachmentCopyErrorNotification,
                                        object:
                                            "Failed to prepare file for preview: \(error.localizedDescription)"
                                    )
                                }
                            }
                        }
                    }
                    if !message.text.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            // Show content warning if applicable
                            if shouldShowContentWarning && showModerationWarnings {
                                contentWarningView
                            }

                            TappableLinksText(
                                text: displayedText,
                                fontSize: chatFontSize,
                                textColor: dynamicTextColor
                            )
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .shadow(
                                        color: Color.black.opacity(0.18), radius: 10, x: 0, y: 3
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(dynamicBorderColor, lineWidth: borderLineWidth)
                                    .animation(
                                        .easeInOut(duration: 1.0), value: dynamicBorderColor
                                    )
                                    .animation(
                                        .easeInOut(duration: 1.0), value: borderLineWidth)
                            )
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(dynamicBubbleColor)
                        .shadow(
                            color: .black.opacity(isCurrentUser ? 0.15 : 0.1), radius: 4, x: 0, y: 2
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(dynamicBorderColor, lineWidth: borderLineWidth)
                        .animation(.easeInOut(duration: 1.0), value: dynamicBorderColor)
                        .animation(.easeInOut(duration: 1.0), value: borderLineWidth)
                )
            }
        }
    }

    private var businessCardContent: some View {
        Group {
            if let business = getBusinessFromMessage() {
                // Enhanced business card without bubble background
                SharedBusinessCardInChatView(
                    business: business,
                    sharedBy: message.user,
                    sharedAt: message.timestamp,
                    isCurrentUser: isCurrentUser,
                    onTap: {
                        // Pass tap up to parent view to show details
                        onBusinessTap?(business)
                    }
                )
            } else {
                // Fallback for legacy business card messages
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "storefront.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        Text("Local Business Shared")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Spacer()
                        Text("Tap to view")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !message.text.isEmpty && !message.text.contains("base64") {
                        Text(message.text)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // Helper function to decode business data from message
    private func getBusinessFromMessage() -> LocalBusiness? {
        guard message.messageType == .businessCard else { return nil }

        // Try to decode business data from the message text
        if let data = Data(base64Encoded: message.text),
            let business = try? JSONDecoder().decode(LocalBusiness.self, from: data)
        {
            return business
        }

        return nil
    }

    // Helper function to decode business list data from message
    private func getBusinessListFromMessage() -> (businesses: [LocalBusiness], searchQuery: String)?
    {
        guard message.messageType == .businessList else { return nil }

        // Try to decode business list data from the message text
        if let data = Data(base64Encoded: message.text),
            let businessListData = try? JSONDecoder().decode(BusinessListData.self, from: data)
        {
            return (businessListData.businesses, businessListData.searchQuery)
        }

        return nil
    }

    private var businessListContent: some View {
        Group {
            if let businessListData = getBusinessListFromMessage() {
                // Enhanced business list without bubble background
                SharedBusinessListInChatView(
                    businesses: businessListData.businesses,
                    searchQuery: businessListData.searchQuery,
                    sharedBy: message.user,
                    sharedAt: message.timestamp,
                    isCurrentUser: isCurrentUser,
                    onBusinessTap: { business in
                        onBusinessTap?(business)
                    }
                )
            } else {
                // Fallback for legacy business list messages
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.cyan)
                            .font(.title2)
                        Text("Business Discovery Results")
                            .font(.headline)
                            .foregroundColor(.cyan)
                        Spacer()
                        Text("View Details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !message.text.isEmpty && !message.text.contains("base64") {
                        Text(message.text)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Base Color Properties
    private var bubbleColor: Color {
        // AI/assistant messages: keep blue background
        if message.user.lowercased().contains("ai")
            || message.user.lowercased().contains("assistant")
            || message.user.lowercased().contains("bot")
        {
            return Color.blue.opacity(0.15)
        }
        if message.messageType == .system {
            return Color(.systemGray5)
        } else if message.messageType == .announcement {
            return Color.orange.opacity(0.2)
        } else if message.messageType == .businessCard {
            return Color.orange.opacity(0.1)
        } else if message.messageType == .businessList {
            return Color.cyan.opacity(0.1)
        } else {
            return Color.clear
        }
    }

    private var textColor: Color {
        // AI/assistant messages: blue text for contrast
        if message.user.lowercased().contains("ai")
            || message.user.lowercased().contains("assistant")
            || message.user.lowercased().contains("bot")
        {
            return .blue
        }
        if message.messageType == .system {
            return .secondary
        } else if message.messageType == .announcement {
            return .orange
        } else if message.messageType == .businessCard {
            return .primary
        } else if message.messageType == .businessList {
            return .primary
        } else {
            return .primary
        }
    }

    private var borderColor: Color {
        if message.messageType == .system {
            return Color(.systemGray4)
        } else if message.messageType == .announcement {
            return Color.orange.opacity(0.5)
        } else {
            return Color.clear
        }
    }

    // MARK: - Dynamic Bubble Properties for New Message Effects
    private var dynamicBubbleColor: Color {
        // Always return the original bubble color, effects are handled by background layers
        return bubbleColor
    }

    private var dynamicTextColor: Color {
        // Keep original text color, let opacity handle fading
        return textColor
    }

    private var dynamicBorderColor: Color {
        if isJustAdded {
            return Color.green.opacity(0.8)
        } else if isEditingAnimation {
            return Color.orange.opacity(0.6)
        } else if isDeleting {
            return Color.red.opacity(0.5)
        } else {
            // Fade to base border color or clear for smooth transition
            return borderColor.opacity(borderColor == .clear ? 0.0 : 1.0)
        }
    }

    private var borderLineWidth: CGFloat {
        if isJustAdded {
            return 2
        } else if isEditingAnimation || isDeleting {
            return 2
        } else if message.messageType == .system {
            return 1
        } else {
            // Fade border width to 0 for smooth disappearance
            return 0
        }
    }

    // Formatter for edit timestamps
    private var editTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private var messageStatusIndicator: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 2) {
                // Edit indicator for current user messages
                if message.isEdited && message.messageType != .system {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("edited")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }

                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Dynamic Color Effects with Enhanced Glow Animations
    private var highlightBackgroundColor: Color {
        if isJustAdded {
            return Color.green.opacity(0.4)  // Enhanced green glow for new messages
        } else if isHighlighted {
            return Color.blue.opacity(0.2)  // Blue glow for highlighted messages
        } else if isEditingAnimation {
            return Color.orange.opacity(0.45)  // Brighter orange glow for editing
        } else if isDeleting {
            return Color.red.opacity(0.5)  // Brighter red glow for dramatic deletion
        } else {
            // Explicit transparent for smooth fade transitions
            return Color.clear.opacity(0.0)
        }
    }

    private var shadowColor: Color {
        if isJustAdded {
            return .green.opacity(0.9)  // Vibrant green shadow for new messages
        } else if isHighlighted {
            return .blue.opacity(0.4)  // Blue shadow for highlighting
        } else if isEditingAnimation {
            return .orange.opacity(0.8)  // Brighter orange shadow for editing
        } else if isDeleting {
            return .red.opacity(0.9)  // Bright red shadow for dramatic deletion
        } else {
            // Explicit transparent for smooth fade transitions
            return Color.black.opacity(0.0)
        }
    }

    private var stateOverlayColor: Color {
        if isEditingAnimation {
            return Color.orange.opacity(0.2)  // Brighter orange overlay for editing
        } else if isDeleting {
            return Color.red.opacity(0.25)  // Brighter red overlay for deletion
        } else if isJustAdded {
            return Color.green.opacity(0.15)  // Subtle green overlay for new messages
        } else if isHighlighted {
            return Color.blue.opacity(0.1)  // Subtle blue overlay for highlighting
        } else {
            // Explicit transparent for smooth fade transitions
            return Color.clear.opacity(0.0)
        }
    }

    private var stateOverlayOpacity: Double {
        if isJustAdded {
            return 0.3  // Enhanced opacity for new message glow
        } else if isEditingAnimation {
            return 0.35  // Brighter orange glow opacity
        } else if isDeleting {
            return 0.4  // Bright red glow opacity for dramatic effect
        } else if isHighlighted {
            return 0.15  // Blue glow opacity
        } else {
            // Explicit zero for smooth fade transitions
            return 0.0
        }
    }

    // MARK: - Enhanced Animation Properties

    // Combined scale effect for realistic physics (multiplicative scaling)
    private var combinedScaleEffect: Double {
        var scale = 1.0

        // Apply scale effects in order of priority
        if isDeleting {
            scale *= 0.6  // More dramatic shrink for destruction effect
        }

        if isJustAdded {
            scale *= 1.15  // More dramatic pop for new messages with spring entrance
        }

        if isEditingAnimation {
            scale *= 1.04  // Slightly more noticeable scale for editing
        }

        if isHighlighted {
            scale *= 1.03  // More visible scale for highlighting
        }

        return scale
    }

    // 2. Message Deletion Animation - Dramatic destruction with multiple effects
    private var deletionOpacity: Double {
        return isDeleting ? 0.1 : 1.0  // More dramatic fade
    }

    // 4. Moderation Animation - 3 quick trembles
    private var shakingOffset: Double {
        return isShaking ? 4 : 0
    }

    // Edit Bounce Animation - Bounce up and down effect
    private var editBounceOffset: Double {
        return isEditingAnimation ? -6 : 0  // Negative for upward bounce
    }

    // Delete Destruction Animation - Dramatic rotation and scale effects
    private var deletionRotation: Double {
        return isDeleting ? 15 : 0  // Rotate as it shrinks
    }

    private var deletionBlur: Double {
        return isDeleting ? 8 : 0  // Blur effect for disintegration
    }

    // Spring Entrance Animation - Bubble springs into place from scale 0
    private var springEntranceScale: Double {
        switch animationPhase {
        case .appearing:
            return hasAppeared ? 1.0 : 0.3
        case .editing:
            return 1.05
        case .deleting:
            return 0.95
        case .deleted:
            return 0.0
        case .stable:
            return hasAppeared ? 1.0 : 0.0
        }
    }

    private var springEntranceOpacity: Double {
        switch animationPhase {
        case .appearing:
            return hasAppeared ? 1.0 : 0.0
        case .editing:
            return 1.0
        case .deleting:
            return 0.7
        case .deleted:
            return 0.0
        case .stable:
            return hasAppeared ? 1.0 : 0.0
        }
    }

    // Enhanced Visual Effects Properties
    private var shadowRadius: Double {
        switch animationPhase {
        case .appearing:
            return 20  // Enhanced glow for appearing messages
        case .editing:
            return 16  // Bright glow for editing
        case .deleting:
            return 18  // Enhanced red glow for deletion
        case .deleted:
            return 0
        case .stable:
            if isJustAdded {
                return 16  // Enhanced glow for new messages
            } else if isHighlighted {
                return 12  // Blue glow for highlighted
            } else if isEditingAnimation {
                return 14  // Brighter orange glow for editing
            } else if isDeleting {
                return 18  // Enhanced red glow for dramatic deletion
            } else {
                return 0  // Fade to no shadow for smooth transition
            }
        }
    }

    private var glowBlurRadius: Double {
        if isJustAdded {
            return 3  // Green glow blur
        } else if isHighlighted {
            return 2  // Blue glow blur
        } else if isEditingAnimation {
            return 3  // Enhanced orange glow blur
        } else if isDeleting {
            return 4  // Enhanced red glow blur for dramatic effect
        } else {
            return 0  // No glow for smooth fade
        }
    }

    // Enhanced state overlay
    private var enhancedStateOverlay: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(stateOverlayColor)
            .opacity(stateOverlayOpacity)
            .blur(radius: glowBlurRadius)
    }

    // MARK: - Helper Functions
    private func fileIconForMessage(_ message: CommunityMessage) -> String {
        guard let fileName = message.fileName else { return "doc" }
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        switch fileExtension {
        case "pdf":
            return "doc.richtext"
        case "doc", "docx":
            return "doc.text"
        case "xls", "xlsx":
            return "tablecells"
        case "ppt", "pptx":
            return "rectangle.stack"
        case "zip", "rar", "7z":
            return "archivebox"
        case "mp3", "wav", "m4a":
            return "music.note"
        case "mp4", "mov", "avi":
            return "video"
        case "jpg", "jpeg", "png", "gif":
            return "photo"
        case "txt":
            return "doc.plaintext"
        default:
            return "doc"
        }
    }

    // MARK: - Enhanced Content Warning View
    private var contentWarningView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14, weight: .semibold))

                Text("Content Warning")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)

                Spacer()

                Image(systemName: "eye.slash")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Text("This message contains language that may be inappropriate for the community.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.red.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// Small subview to render file rows and handle document preview taps
private struct FileMessageView: View {
    let message: CommunityMessage
    let chatFontSize: Double
    let dynamicTextColor: Color
    let onPreviewDocument: ((URL) -> Void)?
    let onPreviewVideo: ((URL) -> Void)?
    let onPreviewImage: ((UIImage) -> Void)?
    let onLongPress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Debug logging for video/GIF visibility
            let _ = print("🎬 FileMessageView rendering for message \(message.id)")
            let _ = print("   - fileName: \(message.fileName ?? "nil")")
            let _ = print("   - fileURL: \(message.fileURL?.absoluteString ?? "nil")")
            let _ = print("   - fileLocalURL: \(message.fileLocalURL ?? "nil")")
            let _ = print("   - fileData: \(message.fileData != nil ? "\(message.fileData!.count) bytes" : "nil")")
            
            // Check file type
            let fileName = message.fileName ?? ""
            let isVideo = isVideoFile(fileName)
            let isGif = fileName.lowercased().hasSuffix(".gif")
            
            if isGif {
                // For GIFs, show animated inline preview
                if let gifData = message.fileData {
                    // Show from local data (optimistic UI while uploading)
                    AnimatedGifView(data: gifData)
                        .frame(maxWidth: 300, maxHeight: 300)
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    onLongPress()
                                }
                        )
                        .onTapGesture {
                            handleVideoTap()
                        }
                } else if let fileURL = message.fileURL {
                    // Download and show animated GIF from remote URL
                    AsyncGifView(url: fileURL) {
                        handleVideoTap()
                    }
                    .frame(maxWidth: 300, maxHeight: 300)
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                onLongPress()
                            }
                    )
                } else if let localPath = message.fileLocalURL, FileManager.default.fileExists(atPath: localPath) {
                    // Load from local file path
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)) {
                        AnimatedGifView(data: data)
                            .frame(maxWidth: 300, maxHeight: 300)
                            .cornerRadius(12)
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        onLongPress()
                                    }
                            )
                            .onTapGesture {
                                handleVideoTap()
                            }
                    } else {
                        gifPlaceholder
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        onLongPress()
                                    }
                            )
                    }
                } else {
                    gifPlaceholder
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    onLongPress()
                                }
                        )
                }
            } else if isVideo, let videoURL = message.fileURL ?? (message.fileLocalURL.flatMap { URL(fileURLWithPath: $0) }) {
                // For videos, show thumbnail preview
                EnhancedVideoPreviewView(source: videoURL) {
                    handleVideoTap()
                }
                .frame(maxWidth: 300)
            } else {
                // For non-video/non-GIF files, show standard file icon
                HStack(spacing: 8) {
                    Image(systemName: fileIcon(for: message.fileName ?? ""))
                        .foregroundColor(.blue)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.fileName ?? "File")
                            .font(.system(size: chatFontSize, weight: .medium))
                            .foregroundColor(dynamicTextColor)
                            .lineLimit(1)

                        if let fileData = message.fileData {
                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: Int64(fileData.count), countStyle: .file)
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        } else if message.fileURL == nil && message.fileLocalURL == nil {
                            Text("Uploading...")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer()
                }
            }
        }
        .onTapGesture {
            let fileName = message.fileName ?? ""
            if !isVideoFile(fileName) && !fileName.lowercased().hasSuffix(".gif") {
                handleNonVideoTap()
            }
        }
    }
    
    // Placeholder view for GIFs that are loading or failed
    private var gifPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 300, height: 200)
            
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                Text("GIF")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Tap to view")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture {
            handleVideoTap()
        }
    }
    
    // Separate handler for video taps
    private func handleVideoTap() {
        print("🎬 FileMessageView video tapped for message \(message.id)")
        
        // Check if this is a GIF file
        let isGif = (message.fileName ?? "").lowercased().hasSuffix(".gif")
        
        if let remote = message.fileURL {
            print("FileMessageView: Remote URL detected as \(isGif ? "GIF" : "video"), downloading: \(remote)")
            // For video/GIF files, download them first for better playback compatibility
            let task = URLSession.shared.downloadTask(with: remote) {
                localURL, resp, err in
                guard let localURL = localURL else {
                    print(
                        "FileMessageView: Failed to download \(isGif ? "GIF" : "video"): \(err?.localizedDescription ?? "Unknown")"
                    )
                    NotificationCenter.default.post(
                        name: .attachmentCopyErrorNotification,
                        object:
                            "Failed to download \(isGif ? "GIF" : "video"): \(err?.localizedDescription ?? "Unknown")"
                    )
                    return
                }
                print("FileMessageView: \(isGif ? "GIF" : "Video") downloaded to: \(localURL)")
                
                // Prepare destination directory
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(isGif ? "NeighborHub/GIFs" : "NeighborHub/Videos", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(
                        at: tmpDir, withIntermediateDirectories: true)
                } catch {
                    print("FileMessageView: Failed to create \(isGif ? "GIF" : "video") directory: \(error)")
                }
                
                // Extract actual filename from Firebase Storage URL
                // URL format: .../uploads/{uid}/communityMessages/{id}/{FILENAME}?alt=media&token=...
                let fileName: String
                if let msgFileName = message.fileName, !msgFileName.isEmpty {
                    // Use the message's fileName field (most reliable)
                    fileName = msgFileName
                } else {
                    // Fallback: try to extract from URL path components
                    let pathComponents = remote.path.components(separatedBy: "/")
                    if let lastComponent = pathComponents.last, !lastComponent.isEmpty {
                        // Remove URL encoding
                        fileName = lastComponent.removingPercentEncoding ?? (isGif ? "animation.gif" : "video.mp4")
                    } else {
                        fileName = isGif ? "animation.gif" : "video.mp4"
                    }
                }
                
                // Create unique filename to avoid conflicts
                let uniqueName = "\(UUID().uuidString)-\(fileName)"
                let dest = tmpDir.appendingPathComponent(uniqueName)
                
                print("FileMessageView: Destination path: \(dest.path)")
                
                // Remove existing file if present
                try? FileManager.default.removeItem(at: dest)
                
                // Move the temporary file immediately (before system deletes it)
                // Use moveItem instead of copyItem for better performance and to avoid file deletion
                do {
                    try FileManager.default.moveItem(at: localURL, to: dest)
                    print("FileMessageView: \(isGif ? "GIF" : "Video") moved to final destination: \(dest)")
                    DispatchQueue.main.async {
                        if isGif {
                            print("FileMessageView: Calling onPreviewVideo for GIF")
                            // GIFs are handled as videos in the preview
                            onPreviewVideo?(dest)
                        } else {
                            print("FileMessageView: Calling onPreviewVideo with local file")
                            onPreviewVideo?(dest)
                        }
                    }
                } catch {
                    print("FileMessageView: Failed to move downloaded \(isGif ? "GIF" : "video"): \(error)")
                    // Fallback: try to copy if move fails
                    do {
                        try FileManager.default.copyItem(at: localURL, to: dest)
                        print("FileMessageView: \(isGif ? "GIF" : "Video") copied to final destination (fallback): \(dest)")
                        DispatchQueue.main.async {
                            onPreviewVideo?(dest)
                        }
                    } catch {
                        print("FileMessageView: Failed to copy downloaded \(isGif ? "GIF" : "video"): \(error)")
                        NotificationCenter.default.post(
                            name: .attachmentCopyErrorNotification,
                            object:
                                "Failed to prepare downloaded \(isGif ? "GIF" : "video"): \(error.localizedDescription)"
                        )
                    }
                }
            }
            task.resume()
        } else if let localPath = message.fileLocalURL {
            let url = URL(fileURLWithPath: localPath)
            print("FileMessageView: Using local \(isGif ? "GIF" : "video") file: \(url)")
            onPreviewVideo?(url)
        } else if message.fileData != nil {
            print("FileMessageView: \(isGif ? "GIF" : "Video") has fileData but no URL yet - still uploading")
        } else {
            print("FileMessageView: No \(isGif ? "GIF" : "video") source available")
        }
    }
    
    // Handler for non-video file taps
    private func handleNonVideoTap() {
        print("📄 FileMessageView non-video file tapped for message \(message.id)")
        if let remote = message.fileURL {
            print("FileMessageView: Attempting to download remote file: \(remote)")
            // Download remote file to temp and preview
            let task = URLSession.shared.downloadTask(with: remote) {
                localURL, resp, err in
                guard let localURL = localURL else {
                    print(
                        "FileMessageView: Failed to download file: \(err?.localizedDescription ?? "Unknown")"
                    )
                    NotificationCenter.default.post(
                        name: .attachmentCopyErrorNotification,
                        object:
                            "Failed to download attachment: \(err?.localizedDescription ?? "Unknown")"
                    )
                    return
                }
                print("FileMessageView: File downloaded to: \(localURL)")
                
                // Prepare destination directory
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "NeighborHub/Attachments", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(
                        at: tmpDir, withIntermediateDirectories: true)
                } catch {
                    print("FileMessageView: Failed to create attachments directory: \(error)")
                }
                
                // Extract actual filename from Firebase Storage URL
                let fileName: String
                if let msgFileName = message.fileName, !msgFileName.isEmpty {
                    fileName = msgFileName
                } else {
                    // Fallback: try to extract from URL
                    let pathComponents = remote.path.components(separatedBy: "/")
                    if let lastComponent = pathComponents.last, !lastComponent.isEmpty {
                        fileName = lastComponent.removingPercentEncoding ?? "file"
                    } else {
                        fileName = "file"
                    }
                }
                
                // Create unique filename
                let uniqueName = "\(UUID().uuidString)-\(fileName)"
                let dest = tmpDir.appendingPathComponent(uniqueName)
                
                // Remove existing file if present
                try? FileManager.default.removeItem(at: dest)
                
                // Move the temporary file immediately (before system deletes it)
                do {
                    try FileManager.default.moveItem(at: localURL, to: dest)
                    print("FileMessageView: File moved to final destination: \(dest)")
                    DispatchQueue.main.async {
                        onPreviewDocument?(dest)
                    }
                } catch {
                    print("FileMessageView: Failed to move downloaded file: \(error)")
                    // Fallback: try to copy if move fails
                    do {
                        try FileManager.default.copyItem(at: localURL, to: dest)
                        print("FileMessageView: File copied to final destination (fallback): \(dest)")
                        DispatchQueue.main.async {
                            onPreviewDocument?(dest)
                        }
                    } catch {
                        print("FileMessageView: Failed to copy downloaded file: \(error)")
                        NotificationCenter.default.post(
                            name: .attachmentCopyErrorNotification,
                            object:
                                "Failed to prepare downloaded file: \(error.localizedDescription)"
                        )
                    }
                }
            }
            task.resume()
        } else if let localPath = message.fileLocalURL {
            let url = URL(fileURLWithPath: localPath)
            print("FileMessageView: Using local file: \(url)")
            onPreviewDocument?(url)
        } else if let data = message.fileData, let name = message.fileName {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
                "\(UUID().uuidString)-\(name)")
            do {
                try data.write(to: tmp, options: .atomic)
                onPreviewDocument?(tmp)
            } catch {
                NotificationCenter.default.post(
                    name: .attachmentCopyErrorNotification,
                    object:
                        "Failed to prepare file for preview: \(error.localizedDescription)")
            }
        }
    }
}

// Small subview for image/video previews inside bubbles
private struct ImageVideoPreviewView: View {
    let filePath: String
    // Callbacks for video and image previews
    let onPreviewVideo: ((URL) -> Void)?
    let onPreviewImage: ((UIImage) -> Void)?

    var body: some View {
        if isVideoFile(filePath) {
            let url = URL(fileURLWithPath: filePath)
            EnhancedVideoPreviewView(source: url) {
                onPreviewVideo?(url)
            }
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
            let ui = UIImage(data: data)
        {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .cornerRadius(8)
                .onTapGesture {
                    onPreviewImage?(ui)
                }
        } else {
            // Fallback placeholder
            HStack {
                Image(systemName: "doc")
                Text("File")
            }
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Simplified ViewModifiers
struct BubbleTransformModifier: ViewModifier {
    let scaleEffect: Double
    let opacity: Double
    let offsetX: Double
    let offsetY: Double
    let rotationDegrees: Double
    let blurRadius: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .offset(x: offsetX, y: offsetY)
            .rotationEffect(.degrees(rotationDegrees))
            .blur(radius: blurRadius)
    }
}

// MARK: - Video Preview
private func isVideoFile(_ path: String) -> Bool {
    let ext = (path as NSString).pathExtension.lowercased()
    return ["mp4", "mov", "avi", "m4v", "mkv", "webm", "gif"].contains(ext)
}

// Enhanced Video Thumbnail View - Shows a preview thumbnail and opens fullscreen player on tap
struct EnhancedVideoPreviewView: View {
    let source: URL
    let onPlay: () -> Void
    @State private var thumbnail: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var duration: String = "0:00"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.8))

                // Thumbnail or loading state
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .cornerRadius(12)
                } else if isLoading {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading video...")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                } else {
                    // Fallback when thumbnail generation fails
                    VStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Video File")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        if !duration.isEmpty && duration != "0:00" {
                            Text(duration)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }

                // Overlay with play button and duration
                VStack {
                    Spacer()
                    HStack {
                        // Play button
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 50, height: 50)

                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }

                        Spacer()

                        // Duration badge (show even if thumbnail failed)
                        if !duration.isEmpty && duration != "0:00" {
                            Text(duration)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                        } else if thumbnail == nil && !isLoading {
                            // Show a generic video indicator when no duration available
                            Text("VIDEO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(4)
                        }
                    }
                    .padding(12)
                }

                // Video file type indicator
                VStack {
                    HStack {
                        Text("VIDEO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(4)

                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxHeight: 200)
        .onTapGesture {
            onPlay()
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        guard thumbnail == nil else { return }
        isLoading = true

        // First validate the file exists if it's a local file
        if source.isFileURL {
            let fileExists = FileManager.default.fileExists(atPath: source.path)
            guard fileExists else {
                print("Video file does not exist at path: \(source.path)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            // Check file size - if it's 0 bytes, it's likely corrupted
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                guard fileSize > 0 else {
                    print("Video file is empty or corrupted: \(source.path)")
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    return
                }
            } catch {
                print("Could not read file attributes: \(error)")
            }
        }

        Task {
            do {
                let asset = AVAsset(url: source)

                // First check if the asset is playable
                let isPlayable = try await asset.load(.isPlayable)
                guard isPlayable else {
                    print("Video asset is not playable: \(source)")
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }

                // Check if asset has video tracks
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                guard !videoTracks.isEmpty else {
                    print("Video asset has no video tracks: \(source)")
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }

                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 300, height: 200)
                imageGenerator.requestedTimeToleranceBefore = .zero
                imageGenerator.requestedTimeToleranceAfter = .zero

                // Try multiple time points if the first fails
                let timePoints: [CMTime] = [
                    CMTime(seconds: 0.5, preferredTimescale: 60),
                    CMTime(seconds: 1.0, preferredTimescale: 60),
                    CMTime(seconds: 2.0, preferredTimescale: 60),
                    CMTime.zero,
                ]

                var thumbnailGenerated = false
                for timePoint in timePoints {
                    do {
                        let cgImage = try imageGenerator.copyCGImage(at: timePoint, actualTime: nil)
                        let uiImage = UIImage(cgImage: cgImage)

                        // Get duration
                        let durationTime = try await asset.load(.duration)
                        let seconds = CMTimeGetSeconds(durationTime)
                        let formattedDuration = formatDuration(seconds)

                        await MainActor.run {
                            self.thumbnail = uiImage
                            self.duration = formattedDuration
                            self.isLoading = false
                        }
                        thumbnailGenerated = true
                        break
                    } catch {
                        print("Failed to generate thumbnail at time \(timePoint.seconds): \(error)")
                        continue
                    }
                }

                if !thumbnailGenerated {
                    // If all time points fail, try async method
                    do {
                        let durationTime = try await asset.load(.duration)
                        let seconds = CMTimeGetSeconds(durationTime)
                        let formattedDuration = formatDuration(seconds)

                        await MainActor.run {
                            self.duration = formattedDuration
                            self.isLoading = false
                        }
                    } catch {
                        await MainActor.run {
                            self.isLoading = false
                        }
                    }
                }

            } catch {
                print("Failed to generate video thumbnail: \(error)")
                // Log more detailed error information
                if let nsError = error as NSError? {
                    print("Error domain: \(nsError.domain)")
                    print("Error code: \(nsError.code)")
                    print("Error description: \(nsError.localizedDescription)")
                    print("Error failure reason: \(nsError.localizedFailureReason ?? "Unknown")")
                }

                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// Simplified Video Player View for fullscreen playback
struct FullScreenVideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer?
    @State private var playerReady: Bool = false
    @State private var loadingFailed: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if loadingFailed {
                // Error state
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                    Text("Unable to play video")
                        .foregroundColor(.white)
                        .font(.headline)
                    Text("The video file may be corrupted or in an unsupported format.")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .font(.headline)
                }
            } else if let player = player, playerReady {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showControls.toggle()
                        }
                        if showControls {
                            resetControlsTimer()
                        }
                    }
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading video...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }

            // Always-visible close button in top-right corner
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.top, 50)  // Account for safe area
                .padding(.trailing, 20)
                Spacer()
            }

            // Custom controls overlay
            if showControls && playerReady && !loadingFailed {
                VStack {
                    Spacer()

                    // Bottom controls
                    HStack(spacing: 20) {
                        Button(action: {
                            player?.seek(to: .zero)
                            resetControlsTimer()
                        }) {
                            Image(systemName: "backward.end")
                                .font(.title2)
                                .foregroundColor(.white)
                        }

                        Button(action: togglePlayPause) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }

                        Button(action: {
                            if let player = player, let duration = player.currentItem?.duration {
                                let endTime = CMTimeSubtract(
                                    duration, CMTime(seconds: 1.0, preferredTimescale: 600))
                                player.seek(to: endTime)
                            }
                            resetControlsTimer()
                        }) {
                            Image(systemName: "forward.end")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(25)
                    .padding(.bottom, 50)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func setupPlayer() {
        print("Setting up player for URL: \(url)")

        // Validate URL first
        guard url.isFileURL || url.scheme == "http" || url.scheme == "https" else {
            print("Invalid URL scheme: \(url)")
            loadingFailed = true
            return
        }

        // Check if file exists for local URLs
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("Video file does not exist at path: \(url.path)")
                loadingFailed = true
                return
            }
        }

        // Create player
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer

        // Set up NotificationCenter observers for player status
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                self.isPlaying = false
                self.showControls = true
            }
        }

        // Monitor player status using a timer-based approach instead of KVO
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkPlayerStatus()
        }
    }

    private func checkPlayerStatus() {
        guard let player = player else {
            loadingFailed = true
            return
        }

        if let currentItem = player.currentItem {
            switch currentItem.status {
            case .readyToPlay:
                print("Player ready to play")
                playerReady = true
                player.play()
                isPlaying = true
                resetControlsTimer()
            case .failed:
                print(
                    "Player failed: \(currentItem.error?.localizedDescription ?? "Unknown error")")
                loadingFailed = true
            case .unknown:
                // Still loading, check again in a moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.checkPlayerStatus()
                }
            @unknown default:
                print("Player status unknown default")
                loadingFailed = true
            }
        } else {
            // No current item, something went wrong
            loadingFailed = true
        }
    }

    private func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
            controlsTimer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            resetControlsTimer()
        }
    }

    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        if isPlaying {
            controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.showControls = false
                    }
                }
            }
        }
    }

    private func cleanupPlayer() {
        controlsTimer?.invalidate()
        controlsTimer = nil

        if let player = player {
            player.pause()
            NotificationCenter.default.removeObserver(self)
        }

        player = nil
        playerReady = false
    }
}

// Popup Video Player View - Designed for sheet presentation with proper sizing
struct PopupVideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var playerReady: Bool = false
    @State private var loadingFailed: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black

                if loadingFailed {
                    // Error state
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                        Text("Unable to play video")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("The video file may be corrupted or in an unsupported format.")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(.blue)
                        .font(.headline)
                    }
                } else if let player = player, playerReady {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Loading video...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }

                // Custom controls overlay removed - using native video player controls
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func setupPlayer() {
        print("🎬 Setting up popup player for URL: \(url)")
        print("   - Is file URL: \(url.isFileURL)")
        print("   - Scheme: \(url.scheme ?? "nil")")
        print("   - Path: \(url.path)")
        print("   - Absolute string: \(url.absoluteString)")

        // Validate URL first
        guard url.isFileURL || url.scheme == "http" || url.scheme == "https" else {
            print("❌ Invalid URL scheme: \(url)")
            loadingFailed = true
            return
        }

        // Check if file exists for local URLs
        if url.isFileURL {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            print("   - File exists check: \(fileExists)")
            guard fileExists else {
                print("❌ Video file does not exist at path: \(url.path)")
                loadingFailed = true
                return
            }
            
            // Check file size
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("   - File size: \(fileSize) bytes")
                guard fileSize > 0 else {
                    print("❌ Video file is empty (0 bytes)")
                    loadingFailed = true
                    return
                }
            } catch {
                print("⚠️ Could not read file attributes: \(error)")
            }
        }

        // Create player
        print("📺 Creating AVPlayer with URL...")
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        
        // Log player item details
        if let item = newPlayer.currentItem {
            print("   - AVPlayerItem created: \(item)")
            print("   - Initial status: \(item.status.rawValue)")
        } else {
            print("⚠️ No AVPlayerItem created!")
        }

        // Set up NotificationCenter observers for player status
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in
            print("📹 Video playback completed")
        }
        
        // Observer for player item errors
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("❌ AVPlayerItem failed to play to end: \(error.localizedDescription)")
            }
        }

        // Monitor player status using a timer-based approach instead of KVO
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkPlayerStatus()
        }
    }

    private func checkPlayerStatus() {
        guard let player = player else {
            print("❌ Player is nil in checkPlayerStatus")
            loadingFailed = true
            return
        }

        if let currentItem = player.currentItem {
            print("📊 Checking player item status: \(currentItem.status.rawValue)")
            switch currentItem.status {
            case .readyToPlay:
                print("✅ Popup player ready to play")
                playerReady = true
                player.play()
            case .failed:
                let errorDescription = currentItem.error?.localizedDescription ?? "Unknown error"
                let errorCode = (currentItem.error as? NSError)?.code ?? 0
                let errorDomain = (currentItem.error as? NSError)?.domain ?? "Unknown"
                print("❌ Popup player failed!")
                print("   - Error: \(errorDescription)")
                print("   - Code: \(errorCode)")
                print("   - Domain: \(errorDomain)")
                if let error = currentItem.error {
                    print("   - Full error: \(error)")
                }
                loadingFailed = true
            case .unknown:
                print("⏳ Player status still unknown, checking again...")
                // Still loading, check again in a moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.checkPlayerStatus()
                }
            @unknown default:
                print("❌ Popup player status unknown default")
                loadingFailed = true
            }
        } else {
            print("❌ No current item in player")
            loadingFailed = true
        }
    }

    private func cleanupPlayer() {
        if let player = player {
            player.pause()
            NotificationCenter.default.removeObserver(self)
        }

        player = nil
        playerReady = false
    }
}

// MARK: - GIF Viewer
struct PopupGifView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var gifData: Data? = nil
    @State private var loadingFailed: Bool = false
    @State private var isLoading: Bool = true

    var body: some View {
        NavigationView {
            ZStack {
                Color.black

                if loadingFailed {
                    // Error state
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                        Text("Unable to load GIF")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("The GIF file may be corrupted or unavailable.")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(.blue)
                        .font(.headline)
                    }
                } else if let gifData = gifData {
                    // Display the GIF using UIImage with animated image data
                    AnimatedGifView(data: gifData)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if isLoading {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Loading GIF...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadGif()
        }
    }

    private func loadGif() {
        print("🎬 Loading GIF from URL: \(url)")
        
        // Check if file exists for local URLs
        if url.isFileURL {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            print("   - File exists: \(fileExists)")
            guard fileExists else {
                print("❌ GIF file does not exist at path: \(url.path)")
                isLoading = false
                loadingFailed = true
                return
            }
        }
        
        // Load the GIF data
        do {
            let data = try Data(contentsOf: url)
            print("✅ GIF data loaded: \(data.count) bytes")
            gifData = data
            isLoading = false
        } catch {
            print("❌ Failed to load GIF: \(error.localizedDescription)")
            isLoading = false
            loadingFailed = true
        }
    }
}

// SwiftUI wrapper for animated GIF display
struct AnimatedGifView: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        
        // Create animated image from GIF data
        if let image = UIImage.animatedImageWithGIFData(data) {
            imageView.image = image
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Update if needed
    }
}

// AsyncGifView - Downloads and displays animated GIF from URL
struct AsyncGifView: View {
    let url: URL
    let onTap: () -> Void
    
    @State private var gifData: Data? = nil
    @State private var isLoading: Bool = true
    @State private var loadingFailed: Bool = false
    
    var body: some View {
        ZStack {
            if let data = gifData {
                // Show animated GIF
                AnimatedGifView(data: data)
            } else if isLoading {
                // Loading state
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            } else if loadingFailed {
                // Error state
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                    
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.gray)
                        Text("Failed to load")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            downloadGif()
        }
        .onTapGesture {
            onTap()
        }
    }
    
    private func downloadGif() {
        isLoading = true
        loadingFailed = false
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    print("❌ Failed to download GIF: \(error.localizedDescription)")
                    loadingFailed = true
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    print("❌ GIF data is empty")
                    loadingFailed = true
                    return
                }
                
                print("✅ GIF downloaded successfully (\(data.count) bytes)")
                gifData = data
            }
        }.resume()
    }
}

// Extension to support animated GIF loading
extension UIImage {
    static func animatedImageWithGIFData(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        let frameCount = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var totalDuration: TimeInterval = 0
        
        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                continue
            }
            
            // Get frame duration
            let frameDuration = UIImage.getFrameDuration(from: source, at: i)
            totalDuration += frameDuration
            
            images.append(UIImage(cgImage: cgImage))
        }
        
        guard !images.isEmpty else {
            return nil
        }
        
        // Create animated image
        return UIImage.animatedImage(with: images, duration: totalDuration)
    }
    
    private static func getFrameDuration(from source: CGImageSource, at index: Int) -> TimeInterval {
        var frameDuration: TimeInterval = 0.1 // Default 100ms
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return frameDuration
        }
        
        // Try to get the unclampedDelayTime first
        if let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval, unclampedDelay > 0 {
            frameDuration = unclampedDelay
        } else if let delay = gifProperties[kCGImagePropertyGIFDelayTime as String] as? TimeInterval, delay > 0 {
            frameDuration = delay
        }
        
        // Clamp to minimum of 10ms (browsers often do this)
        return max(frameDuration, 0.01)
    }
}

// MARK: - Audio Player Helper & View
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    // Local file player
    private var audioPlayer: AVAudioPlayer?

    // Remote/streaming player
    private var avPlayer: AVPlayer?
    private var timeObserverToken: Any?

    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isBuffering: Bool = false
    @Published var playbackError: String? = nil

    private var timer: Timer?

    deinit {
        removePeriodicTimeObserver()
        stop()
    }

    // Unified loader: accepts either local file URL or remote http(s) URL
    func load(source url: URL) {
        stop()

        if url.isFileURL {
            // Local file - use AVAudioPlayer for accurate duration/seek
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.delegate = self  // Set delegate for completion handling
                audioPlayer?.prepareToPlay()
                duration = audioPlayer?.duration ?? 0
            } catch {
                print("AudioPlayer load error: \(error)")
            }
        } else {
            // Remote stream - use AVPlayer
            avPlayer = AVPlayer(url: url)

            // Observe duration when ready
            if let currentItem = avPlayer?.currentItem {
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemNewAccessLogEntry, object: currentItem, queue: .main
                ) { _ in
                    self.updateDurationFromCurrentItem()
                }

                // Observe playback completion to allow replay
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: currentItem, queue: .main
                ) { _ in
                    print("AudioPlayer: Remote audio finished playing")
                    DispatchQueue.main.async {
                        self.isPlaying = false
                        self.currentTime = 0
                        self.avPlayer?.seek(to: .zero)  // Reset to beginning for replay
                    }
                }
            }

            // Observe player item status/buffering
            addPlayerItemObservers()

            // Add periodic time observer to update currentTime
            addPeriodicTimeObserver()
        }
    }

    // Backwards-compatible local loader
    func loadFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        load(source: url)
    }

    func play() {
        if let p = audioPlayer {
            p.play()
            isPlaying = true
            startTimerForAudioPlayer()
        } else if let av = avPlayer {
            av.play()
            isPlaying = true
            // currentTime will be updated via periodic observer
        }
    }

    func pause() {
        if let p = audioPlayer {
            p.pause()
            isPlaying = false
            stopTimerForAudioPlayer()
        } else if let av = avPlayer {
            av.pause()
            isPlaying = false
        }
    }

    func stop() {
        if let p = audioPlayer {
            p.stop()
            audioPlayer = nil
            stopTimerForAudioPlayer()
        }

        if let av = avPlayer {
            av.pause()
            // remove KVO/notifications on the current item
            removePlayerItemObservers()
            av.replaceCurrentItem(with: nil)
            avPlayer = nil
            removePeriodicTimeObserver()
        }

        isPlaying = false
        currentTime = 0
        duration = 0
    }

    // MARK: - AVPlayer periodic observer
    private func addPeriodicTimeObserver() {
        guard let av = avPlayer else { return }
        // Observe every 0.2s
        let interval = CMTime(seconds: 0.2, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = av.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.updateDurationFromCurrentItem()
        }
    }

    private func removePeriodicTimeObserver() {
        if let token = timeObserverToken, let av = avPlayer {
            av.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func updateDurationFromCurrentItem() {
        guard let asset = avPlayer?.currentItem?.asset else { return }
        // Use the modern async load API for duration (iOS 16+)
        Task { @MainActor in
            do {
                let d = try await asset.load(.duration)
                let secs = CMTimeGetSeconds(d)
                if !secs.isNaN && secs.isFinite {
                    duration = secs
                }
            } catch {
                // ignore loading errors, keep previous duration
            }
        }
    }

    // MARK: - AVPlayerItem KVO and buffering handlers
    private var playerItemContext = 0

    private func addPlayerItemObservers() {
        guard let item = avPlayer?.currentItem else { return }

        // Observe status and buffering-related keys
        item.addObserver(
            self, forKeyPath: "status", options: [.initial, .new], context: &playerItemContext)
        item.addObserver(
            self, forKeyPath: "isPlaybackBufferEmpty", options: [.new], context: &playerItemContext)
        item.addObserver(
            self, forKeyPath: "isPlaybackLikelyToKeepUp", options: [.new],
            context: &playerItemContext)

        NotificationCenter.default.addObserver(
            self, selector: #selector(playerItemFailed(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        NotificationCenter.default.addObserver(
            self, selector: #selector(playerItemStalled(_:)), name: .AVPlayerItemPlaybackStalled,
            object: item)
    }

    private func removePlayerItemObservers() {
        if let item = avPlayer?.currentItem {
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemPlaybackStalled, object: item)
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemNewAccessLogEntry, object: item)
            // Safe remove (try? to avoid exceptions if already removed)
            // remove observers (removeObserver does not throw)
            item.removeObserver(self, forKeyPath: "status", context: &playerItemContext)
            item.removeObserver(
                self, forKeyPath: "isPlaybackBufferEmpty", context: &playerItemContext)
            item.removeObserver(
                self, forKeyPath: "isPlaybackLikelyToKeepUp", context: &playerItemContext)
        }
    }

    @objc private func playerItemFailed(_ n: Notification) {
        if let item = n.object as? AVPlayerItem {
            playbackError = item.error?.localizedDescription ?? "Playback failed"
            isBuffering = false
        }
    }

    @objc private func playerItemStalled(_ n: Notification) {
        isBuffering = true
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        if let key = keyPath {
            switch key {
            case "status":
                if let item = object as? AVPlayerItem {
                    switch item.status {
                    case .readyToPlay:
                        playbackError = nil
                        isBuffering = false
                        updateDurationFromCurrentItem()
                    case .failed:
                        playbackError = item.error?.localizedDescription ?? "Playback failed"
                        isBuffering = false
                    default:
                        break
                    }
                }

            case "isPlaybackBufferEmpty":
                if let empty = change?[.newKey] as? Bool {
                    isBuffering = empty
                }

            case "isPlaybackLikelyToKeepUp":
                if let ok = change?[.newKey] as? Bool {
                    isBuffering = !ok
                }

            default:
                break
            }
        }
    }

    // MARK: - AVAudioPlayer timer
    private func startTimerForAudioPlayer() {
        stopTimerForAudioPlayer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.audioPlayer else { return }
            self.currentTime = p.currentTime
            if !p.isPlaying {
                self.isPlaying = false
                self.stopTimerForAudioPlayer()
            }
        }
    }

    private func stopTimerForAudioPlayer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("AudioPlayer: Local audio finished playing successfully: \(flag)")
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = 0
            // Reset player position to beginning for replay
            player.currentTime = 0
        }
    }
}

struct AudioMessageView: View {
    let message: CommunityMessage
    @StateObject private var player = AudioPlayer()
    @State private var showError: Bool = false
    @State private var isRetrying: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlay) {
                ZStack {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)

                    if player.isBuffering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.6)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(timeString(player.currentTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ProgressView(
                        value: player.duration > 0 ? player.currentTime / player.duration : 0
                    )
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }

                // Playback error + retry
                if let err = player.playbackError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(err)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(action: {
                            // Retry: reload source and attempt play
                            isRetrying = true
                            player.playbackError = nil
                            if let remote = message.audioURL {
                                player.load(source: remote)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    player.play()
                                    isRetrying = false
                                }
                            } else if let path = message.audioFileURL {
                                player.loadFile(at: path)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    player.play()
                                    isRetrying = false
                                }
                            } else {
                                isRetrying = false
                            }
                        }) {
                            HStack {
                                if isRetrying { ProgressView().scaleEffect(0.6) }
                                Text("Retry")
                            }
                            .font(.caption2)
                            .padding(6)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .onAppear {
            // Prefer remote audio URL (streaming) if available
            if let remote = message.audioURL {
                player.load(source: remote)
            } else if let path = message.audioFileURL {
                player.loadFile(at: path)
            } else if let name = message.audioFileName {
                // Try to locate in caches
                let fm = FileManager.default
                let caches =
                    fm.urls(for: .cachesDirectory, in: .userDomainMask).first
                    ?? fm.temporaryDirectory
                let candidate = caches.appendingPathComponent("NeighborHub/Audio/")
                let full = candidate.appendingPathComponent(name).path
                if fm.fileExists(atPath: full) {
                    player.loadFile(at: full)
                } else {
                    showError = true
                }
            }
        }
    }

    private func togglePlay() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let ti = Int(t)
        let s = ti % 60
        let m = (ti / 60) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct BubbleAnimationModifier: ViewModifier {
    let isJustAdded: Bool
    let isDeleting: Bool
    let isEditingAnimation: Bool
    let isShaking: Bool
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .animation(
                .spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.3), value: isJustAdded
            )
            .animation(.easeInOut(duration: 0.6), value: isDeleting)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isEditingAnimation)
            .animation(
                .easeInOut(duration: 0.08).repeatCount(3, autoreverses: true), value: isShaking
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isHighlighted)
    }
}

// MARK: - Enhanced Animation Extensions
extension Animation {
    static func easeOutQuart(duration: Double) -> Animation {
        return .timingCurve(0.25, 1, 0.5, 1, duration: duration)
    }
}

struct DateSeparatorView: View {
    let date: Date

    var body: some View {
        HStack {
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.systemGray4))

            Text(dateString)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(.systemBackground))
                .cornerRadius(12)

            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.systemGray4))
        }
        .padding(.vertical, 8)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

}

// MARK: - Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Camera Picker Delegate
class CameraPickerDelegate: NSObject, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate
{
    static let shared = CameraPickerDelegate()
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        // You can handle the captured image here
        // For example, save to chat or process
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - Image Picker State
extension CommunityChatCard {
    private func showImagePicker(sourceType: UIImagePickerController.SourceType) {
        imagePickerSourceType = sourceType
        showingImagePicker = true
    }
}

// MARK: - SwiftUI Image Picker Wrapper
private enum ChatMedia {
    case image(UIImage)
    case video(URL)
}

private struct ChatImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    var completion: (ChatMedia?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator

        // Allow photos and movies when using the camera
        if sourceType == .camera {
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.cameraCaptureMode = .photo
            // Set to allow both — user can switch to video in the camera UI
        } else {
            picker.mediaTypes = ["public.image"]
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ChatImagePicker
        init(_ parent: ChatImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Check for a media URL first (video)
            if let mediaURL = info[.mediaURL] as? URL {
                parent.completion(.video(mediaURL))
                picker.dismiss(animated: true)
                return
            }

            // Otherwise try image
            if let image = info[.originalImage] as? UIImage {
                parent.completion(.image(image))
                picker.dismiss(animated: true)
                return
            }

            parent.completion(nil)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(nil)
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Document Picker for File Attachments
struct ChatDocumentPicker: UIViewControllerRepresentable {
    var completion: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .item,  // All file types
            .data,
            .content,
            .pdf,
            .text,
            .image,
            .movie,
            .audio,
            .archive,
            .spreadsheet,
            .presentation,
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController, context: Context
    ) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ChatDocumentPicker

        init(_ parent: ChatDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
        ) {
            parent.completion(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.completion(nil)
        }
    }
}

// MARK: - Shared Business Card in Chat View
struct SharedBusinessCardInChatView: View {
    let business: LocalBusiness
    let sharedBy: String
    let sharedAt: Date
    let isCurrentUser: Bool
    let onTap: () -> Void
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Helper function to extract first name
    private func extractFirstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: " ")
        return components.first?.capitalized ?? trimmed
    }
    
    // Detect small screens
    private var isSmallScreen: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with sharing info - more compact
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption2)

                Text("Shared by \(extractFirstName(from: sharedBy))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)

                Spacer()

                Text(sharedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.05))

            // Business card content - optimized for smaller screens
            VStack(spacing: isSmallScreen ? 10 : 14) {
                // Business header - more compact layout
                HStack(spacing: isSmallScreen ? 8 : 12) {
                    // Business icon - smaller on small screens
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(categoryColor(for: business.category).opacity(0.15))
                            .frame(width: isSmallScreen ? 50 : 60, height: isSmallScreen ? 50 : 60)

                        Image(systemName: categoryIcon(for: business.category))
                            .font(isSmallScreen ? .title3 : .title)
                            .foregroundColor(categoryColor(for: business.category))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(business.name)
                            .font(isSmallScreen ? .headline : .title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        // Category and status in compact layout
                        VStack(alignment: .leading, spacing: 4) {
                            Text(business.category)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(categoryColor(for: business.category))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(categoryColor(for: business.category).opacity(0.1))
                                .cornerRadius(4)

                            HStack(spacing: 3) {
                                Circle()
                                    .fill(business.isOpen ? .green : .red)
                                    .frame(width: 6, height: 6)
                                Text(business.isOpen ? "Open" : "Closed")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(business.isOpen ? .green : .red)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                // Compact info display
                VStack(spacing: 8) {
                    // Phone number - more compact
                    if let phone = business.phone {
                        Button(action: {
                            if let url = URL(string: "tel:\(phone)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.green)
                                    .font(.callout)
                                    .frame(width: 20)

                                Text(phone)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "phone.arrow.up.right")
                                    .foregroundColor(.green)
                                    .font(.caption2)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.green.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Address - compact
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .font(.callout)
                            .frame(width: 20)

                        Text(business.address)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        Spacer()
                    }

                    // Rating and distance - single line
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            HStack(spacing: 1) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(
                                            Double(star) <= business.rating
                                                ? .yellow : .gray.opacity(0.3))
                                }
                            }
                            Text(String(format: "%.1f", business.rating))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "location.circle")
                                .foregroundColor(.blue)
                                .font(.caption2)
                            Text(String(format: "%.1f km", business.distance))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Website (if available) - compact
                    if let website = business.website {
                        Button(action: {
                            if let url = URL(string: "https://\(website)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .foregroundColor(.purple)
                                    .font(.callout)
                                    .frame(width: 20)

                                Text(website)
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .foregroundColor(.purple)
                                    .font(.caption2)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.purple.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Action buttons - stack vertically on very small screens
                if isSmallScreen {
                    VStack(spacing: 8) {
                        Button(action: onTap) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                Text("View Details")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }

                        Button(action: {
                            // Open in Maps
                            let address =
                                business.address.addingPercentEncoding(
                                    withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "http://maps.apple.com/?q=\(address)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "map")
                                    .font(.caption)
                                Text("Directions")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .cornerRadius(8)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(action: onTap) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                Text("View Details")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.blue)
                            .cornerRadius(9)
                        }

                        Button(action: {
                            // Open in Maps
                            let address =
                                business.address.addingPercentEncoding(
                                    withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "http://maps.apple.com/?q=\(address)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "map")
                                Text("Directions")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.green)
                            .cornerRadius(9)
                        }
                    }
                }
            }
            .padding(isSmallScreen ? 12 : 14)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case "restaurant": return "fork.knife"
        case "grocery": return "cart"
        case "services": return "wrench.and.screwdriver"
        case "healthcare": return "cross.case"
        case "automotive": return "car"
        case "retail": return "bag"
        case "pet services": return "pawprint"
        default: return "storefront"
        }
    }

    private func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case "restaurant": return .orange
        case "grocery": return .green
        case "services": return .blue
        case "healthcare": return .red
        case "automotive": return .gray
        case "retail": return .purple
        case "pet services": return .brown
        default: return .cyan
        }
    }
}

// MARK: - Shared Business List in Chat View
struct SharedBusinessListInChatView: View {
    let businesses: [LocalBusiness]
    let searchQuery: String
    let sharedBy: String
    let sharedAt: Date
    let isCurrentUser: Bool
    let onBusinessTap: (LocalBusiness) -> Void

    @State private var isExpanded: Bool = false
    @State private var selectedBusiness: LocalBusiness?
    @State private var showBusinessDetail: Bool = false

    // Helper function to extract first name
    private func extractFirstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: " ")
        return components.first?.capitalized ?? trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with sharing info and AI branding
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.cyan)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Business Discovery Results")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)

                        Text("Search: \"\(searchQuery)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(
                            systemName: isExpanded
                                ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
                        )
                        .foregroundColor(.cyan)
                        .font(.title2)
                    }
                }

                // Summary bar
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text("\(businesses.count) businesses found")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)

                        if let nearest = businesses.min(by: { $0.distance < $1.distance }) {
                            Text("Nearest: \(String(format: "%.1f km", nearest.distance))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .padding(16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.cyan.opacity(0.1), .blue.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // Expandable business list
            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(Array(businesses.enumerated()), id: \.element.id) { index, business in
                        CompactBusinessRowView(
                            business: business,
                            index: index + 1,
                            onTap: {
                                selectedBusiness = business
                                onBusinessTap(business)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Collapsed view showing top 3 businesses
                VStack(spacing: 6) {
                    ForEach(Array(businesses.prefix(3).enumerated()), id: \.element.id) {
                        index, business in
                        CompactBusinessRowView(
                            business: business,
                            index: index + 1,
                            onTap: {
                                selectedBusiness = business
                                onBusinessTap(business)
                            },
                            isCompact: true
                        )
                    }

                    if businesses.count > 3 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isExpanded = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("View \(businesses.count - 3) more businesses")
                                Spacer()
                                Image(systemName: "chevron.down")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            // Footer with sharing attribution
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)

                Text("Shared by \(extractFirstName(from: sharedBy))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)

                Spacer()

                Text(sharedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Color.blue.opacity(0.05))
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showBusinessDetail) {
            if let business = selectedBusiness {
                BusinessDetailView(business: business) { business in
                    // Handle share from detail view
                }
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Compact Business Row for List View
struct CompactBusinessRowView: View {
    let business: LocalBusiness
    let index: Int
    let onTap: () -> Void
    var isCompact: Bool = false
    @State private var showingActions: Bool = false
    @State private var showingBusinessDetail = false
    @State private var showingToast: Bool = false
    @State private var toastMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Main business info button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingActions.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Index number with category icon
                    ZStack {
                        Circle()
                            .fill(categoryColor(for: business.category).opacity(0.15))
                            .frame(width: isCompact ? 32 : 40, height: isCompact ? 32 : 40)

                        VStack(spacing: 1) {
                            Text("\(index)")
                                .font(isCompact ? .caption2 : .caption)
                                .fontWeight(.bold)
                                .foregroundColor(categoryColor(for: business.category))

                            Image(systemName: categoryIcon(for: business.category))
                                .font(isCompact ? .system(size: 8) : .system(size: 10))
                                .foregroundColor(categoryColor(for: business.category))
                        }
                    }

                    // Business info
                    VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
                        // Business name - full width, wraps if needed
                        Text(business.name)
                            .font(isCompact ? .caption : .subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(isCompact ? 2 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Open status indicator on separate line for clarity
                        HStack(spacing: 2) {
                            Circle()
                                .fill(business.isOpen ? .green : .red)
                                .frame(width: 6, height: 6)

                            Text(business.isOpen ? "Open" : "Closed")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(business.isOpen ? .green : .red)
                            
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            Text(business.category)
                                .font(.caption2)
                                .foregroundColor(categoryColor(for: business.category))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(categoryColor(for: business.category).opacity(0.1))
                                .cornerRadius(4)
                                .lineLimit(1)

                            // Rating
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", business.rating))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }

                            // Distance
                            HStack(spacing: 2) {
                                Image(systemName: "location.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text(String(format: "%.1f km", business.distance))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }

                        // Phone number if available and not compact
                        if !isCompact, let phone = business.phone {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text(phone)
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .fontDesign(.monospaced)
                            }
                        }
                    }

                    // Action indicator with quick actions
                    HStack(spacing: 12) {
                        // Quick Call Button (always visible if phone available)
                        if let phone = business.phone {
                            Button(action: {
                                // Haptic feedback
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if let url = URL(string: "tel:\(phone)") {
                                    UIApplication.shared.open(url)
                                }
                                // Show toast
                                showToast("Calling \(business.name)...")
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "phone.fill")
                                        .font(.caption)
                                    if !isCompact {
                                        Text("Call")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, isCompact ? 8 : 10)
                                .padding(.vertical, isCompact ? 4 : 6)
                                .background(Color.green)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Quick Directions Button (always visible)
                        Button(action: {
                            // Haptic feedback
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let address =
                                business.address.addingPercentEncoding(
                                    withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "http://maps.apple.com/?q=\(address)") {
                                UIApplication.shared.open(url)
                            }
                            // Show toast
                            showToast("Opening directions to \(business.name)")
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.caption)
                                if !isCompact {
                                    Text("Directions")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, isCompact ? 8 : 10)
                            .padding(.vertical, isCompact ? 4 : 6)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Expand/collapse indicator
                        Image(systemName: showingActions ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.cyan)
                            .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, isCompact ? 6 : 8)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Interactive action buttons (expandable)
            if showingActions {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 12)

                    HStack(spacing: 8) {
                        // Call Button
                        if let phone = business.phone {
                            Button(action: {
                                // Haptic feedback
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if let url = URL(string: "tel:\(phone)") {
                                    UIApplication.shared.open(url)
                                }
                                showToast("Calling \(business.name)...")
                                // Auto-collapse after action
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingActions = false
                                }
                            }) {
                                VStack(spacing: 2) {
                                    Image(systemName: "phone.fill")
                                        .font(.subheadline)
                                    Text("Call")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .frame(width: 50, height: 44)
                                .background(Color.green)
                                .cornerRadius(8)
                            }
                        }

                        // Directions Button
                        Button(action: {
                            // Haptic feedback
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let address =
                                business.address.addingPercentEncoding(
                                    withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "http://maps.apple.com/?q=\(address)") {
                                UIApplication.shared.open(url)
                            }
                            showToast("Opening directions to \(business.name)")
                            // Auto-collapse after action
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingActions = false
                            }
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "location.fill")
                                    .font(.subheadline)
                                Text("Directions")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .frame(width: 65, height: 44)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }

                        // Website Button
                        if let website = business.website {
                            Button(action: {
                                // Haptic feedback
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                let urlString =
                                    website.hasPrefix("http") ? website : "https://\(website)"
                                if let url = URL(string: urlString) {
                                    UIApplication.shared.open(url)
                                }
                                showToast("Opening website for \(business.name)")
                                // Auto-collapse after action
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingActions = false
                                }
                            }) {
                                VStack(spacing: 2) {
                                    Image(systemName: "globe")
                                        .font(.subheadline)
                                    Text("Website")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .frame(width: 55, height: 44)
                                .background(Color.purple)
                                .cornerRadius(8)
                            }
                        }

                        // Details Button
                        Button(action: {
                            // Haptic feedback
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showingBusinessDetail = true
                            showToast("Opening details for \(business.name)")
                            // Auto-collapse after action
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingActions = false
                            }
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "info.circle")
                                    .font(.subheadline)
                                Text("Details")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .frame(width: 50, height: 44)
                            .background(Color.orange)
                            .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .sheet(isPresented: $showingBusinessDetail) {
            BusinessDetailView(business: business) { _ in
                // Share action can be handled here if needed
            }
            .presentationDetents([.fraction(0.75), .large])
            .presentationDragIndicator(.visible)
        }
        .overlay(
            // Toast notification
            Group {
                if showingToast {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(toastMessage)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .padding(.bottom, 20)
                    .animation(.easeInOut(duration: 0.3), value: showingToast)
                }
            }
        )
    }

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.3)) {
            showingToast = true
        }

        // Auto-hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingToast = false
            }
        }
    }

    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case "restaurant": return "fork.knife"
        case "grocery": return "cart"
        case "services": return "wrench.and.screwdriver"
        case "healthcare": return "cross.case"
        case "automotive": return "car"
        case "retail": return "bag"
        case "pet services": return "pawprint"
        default: return "storefront"
        }
    }

    private func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case "restaurant": return .orange
        case "grocery": return .green
        case "services": return .blue
        case "healthcare": return .red
        case "automotive": return .gray
        case "retail": return .purple
        case "pet services": return .brown
        default: return .cyan
        }
    }
}

// MARK: - Tappable Links Text View
/// A SwiftUI view that detects URLs in text and makes them tappable
struct TappableLinksText: View {
    let text: String
    let fontSize: Double
    let textColor: Color
    
    var body: some View {
        Text(attributedString)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(textColor)
    }
    
    private var attributedString: AttributedString {
        var attributedString = AttributedString(text)
        
        // Detect URLs in the text
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributedString
        }
        
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            guard let url = match.url else { continue }
            
            // Convert String.Index range to AttributedString.Index range
            let startIndex = AttributedString.Index(range.lowerBound, within: attributedString)
            let endIndex = AttributedString.Index(range.upperBound, within: attributedString)
            
            guard let start = startIndex, let end = endIndex else { continue }
            
            // Apply link attributes
            attributedString[start..<end].foregroundColor = .blue
            attributedString[start..<end].underlineStyle = .single
            attributedString[start..<end].link = url
        }
        
        return attributedString
    }
}
