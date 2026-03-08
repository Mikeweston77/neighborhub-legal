import SwiftUI
import PDFKit
import QuickLook
import Compression

// MARK: - Newsletter File Preview Component (WhatsApp-style)
struct NewsletterFilePreview: View {
    let newsletter: Newsletter
    @State private var downloadedFileURL: URL?
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    
    var body: some View {
        Group {
            if let fileURL = downloadedFileURL {
                // File is ready - show it
                QuickLookPreview(url: fileURL)
                    .onAppear {
                        print("📄 NewsletterFilePreview: Displaying PDF at: \(fileURL.path)")
                    }
            } else if isDownloading {
                // Currently downloading
                VStack(spacing: 20) {
                    ProgressView(value: downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    
                    Text("Downloading document...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if downloadProgress > 0 {
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            } else if let error = downloadError {
                // Download failed
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Download Failed")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Try Again") {
                        prepareFile()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                // Preparing
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Preparing document...")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            print("📱 NewsletterFilePreview: View appeared for newsletter: \(newsletter.title)")
            print("   - Has fileName: \(newsletter.fileName != nil)")
            print("   - Has fileData: \(newsletter.fileData != nil)")
            print("   - Current downloadedFileURL: \(downloadedFileURL?.path ?? "nil")")
            print("   - Is downloading: \(isDownloading)")
            prepareFile()
            
            // Listen for download completion notification
            NotificationCenter.default.addObserver(forName: NSNotification.Name("NewsletterFileDownloaded"), object: nil, queue: .main) { notification in
                if let newsletterId = notification.userInfo?["newsletterId"] as? String,
                   newsletterId == newsletter.id.uuidString {
                    print("📥 NewsletterFilePreview: Received download completion notification")
                    // Re-check file existence
                    prepareFile()
                }
            }
        }
        .onDisappear {
            print("📱 NewsletterFilePreview: View disappeared")
            // Clean up notification observer
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("NewsletterFileDownloaded"), object: nil)
        }
    }
    
    private func prepareFile() {
        print("🔍 NewsletterFilePreview: prepareFile() called")
        downloadError = nil
        
        // Check if we already have a fileURL (cached or from Firestore data)
        if let fileURL = newsletter.fileURL {
            print("   - Newsletter has fileURL: \(fileURL.path)")
            // Check if file exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                self.downloadedFileURL = fileURL
                print("✅ NewsletterFilePreview: Using existing file at: \(fileURL.path)")
                return
            } else {
                print("⚠️ NewsletterFilePreview: File path exists but file not found")
            }
        } else {
            print("   - Newsletter has NO fileURL")
        }
        
        // If we have fileData, create temp file from it
        if let fileData = newsletter.fileData, let fileName = newsletter.fileName {
            print("   - Newsletter has fileData (\(fileData.count) bytes) and fileName: \(fileName)")
            createTempFileFromData(fileData, fileName: fileName)
            return
        } else {
            print("   - Newsletter has NO fileData")
        }
        
        // If we have a fileName but no fileURL, file is downloading from Storage
        if let fileName = newsletter.fileName {
            print("⏳ NewsletterFilePreview: File is downloading from Storage, monitoring progress...")
            print("   - fileName: \(fileName)")
            isDownloading = true
            monitorFileDownload(fileName: fileName)
        } else {
            print("❌ NewsletterFilePreview: No file data or fileName available")
            downloadError = "No attachment available"
        }
    }
    
    private func createTempFileFromData(_ data: Data, fileName: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("newsletter_\(newsletter.id.uuidString)_\(fileName)")
        
        do {
            try data.write(to: tempFile)
            self.downloadedFileURL = tempFile
            print("✅ NewsletterFilePreview: Created temp file from data: \(tempFile.path)")
        } catch {
            self.downloadError = "Could not create temporary file: \(error.localizedDescription)"
            print("❌ NewsletterFilePreview: Error creating temp file: \(error)")
        }
    }
    
    private func monitorFileDownload(fileName: String) {
        // Calculate expected cache path
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let expectedPath = cacheDir.appendingPathComponent("newsletters/\(newsletter.id.uuidString)/\(fileName)")
        
        print("📥 NewsletterFilePreview: Monitoring for file at: \(expectedPath.path)")
        
        // Poll for file existence (Firebase Storage download is async)
        var attempts = 0
        let maxAttempts = 60 // 30 seconds max wait
        
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            attempts += 1
            
            if FileManager.default.fileExists(atPath: expectedPath.path) {
                timer.invalidate()
                self.downloadedFileURL = expectedPath
                self.isDownloading = false
                print("✅ NewsletterFilePreview: File download completed: \(expectedPath.path)")
            } else if attempts >= maxAttempts {
                timer.invalidate()
                self.isDownloading = false
                self.downloadError = "Download timed out. Please check your internet connection and try again."
                print("❌ NewsletterFilePreview: Download timed out after \(maxAttempts/2) seconds")
            } else {
                // Update progress indicator
                self.downloadProgress = Double(attempts) / Double(maxAttempts)
            }
        }
    }
}

// MARK: - Legacy Firestore File Preview Component
struct FirestoreFilePreview: View {
    let fileData: Data
    let fileName: String
    @State private var tempFileURL: URL?
    
    var body: some View {
        Group {
            if let tempFileURL = tempFileURL {
                QuickLookPreview(url: tempFileURL)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Preparing document...")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            createTempFile()
        }
        .onDisappear {
            cleanupTempFile()
        }
    }
    
    private func createTempFile() {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("newsletter_\(UUID().uuidString)_\(fileName)")
        
        do {
            try fileData.write(to: tempFile)
            self.tempFileURL = tempFile
            print("FirestoreFilePreview: Created temp file for preview: \(tempFile)")
        } catch {
            print("FirestoreFilePreview: Error creating temp file: \(error)")
        }
    }
    
    private func cleanupTempFile() {
        if let tempFileURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempFileURL)
            print("FirestoreFilePreview: Cleaned up temp file")
        }
    }
}

import UniformTypeIdentifiers
import FirebaseAuth

// MARK: - Newsletter Image Cache
class NewsletterImageCache: ObservableObject {
    static let shared = NewsletterImageCache()
    
    @Published private var cache: [UUID: UIImage] = [:]
    private var loadingQueue = DispatchQueue(label: "com.neighborhub.newsletter.imageloader", qos: .userInitiated)
    private var currentlyLoading: Set<UUID> = []
    
    private init() {}
    
    func getImage(for newsletter: Newsletter) -> UIImage? {
        return cache[newsletter.id]
    }
    
    func hasAttachment(for newsletter: Newsletter) -> Bool {
        return newsletter.imageData != nil || newsletter.fileURL != nil
    }
    
    func preloadImage(for newsletter: Newsletter) {
        // Skip if already cached or loading
        guard cache[newsletter.id] == nil, !currentlyLoading.contains(newsletter.id) else {
            return
        }
        
        // Try to get image from imageData first
        if let imageData = newsletter.imageData {
            currentlyLoading.insert(newsletter.id)
            
            loadingQueue.async { [weak self] in
                guard let self = self else { return }
                
                if let image = UIImage(data: imageData) {
                    DispatchQueue.main.async {
                        self.cache[newsletter.id] = image
                        self.currentlyLoading.remove(newsletter.id)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.currentlyLoading.remove(newsletter.id)
                    }
                }
            }
        } else if let fileData = newsletter.fileData, let fileName = newsletter.fileName {
            // Try to generate preview from Firestore file data (PDF, etc.)
            currentlyLoading.insert(newsletter.id)
            
            loadingQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Create temporary file from Firestore data
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("preview_\(newsletter.id.uuidString)_\(fileName)")
                do {
                    try fileData.write(to: tempFile)
                    if let image = generateImageFromFile(url: tempFile) {
                        DispatchQueue.main.async {
                            self.cache[newsletter.id] = image
                            self.currentlyLoading.remove(newsletter.id)
                        }
                    } else {
                        // No image could be generated from file
                        DispatchQueue.main.async {
                            self.currentlyLoading.remove(newsletter.id)
                        }
                    }
                } catch {
                    print("NewsletterImageCache: Error creating temp file: \(error)")
                    DispatchQueue.main.async {
                        self.currentlyLoading.remove(newsletter.id)
                    }
                }
            }
        }
    }
    
    func clearCache() {
        cache.removeAll()
        currentlyLoading.removeAll()
    }
    
    func removeImage(for newsletterId: UUID) {
        cache.removeValue(forKey: newsletterId)
    }
}

// MARK: - Newsletter Manager
class NewsletterManager: ObservableObject {
    @Published var newsletters: [Newsletter] = []
    @AppStorage("newsletters") private var newslettersData: String = ""

    private var usingFirestore: Bool = false

    init() {
        #if canImport(FirebaseFirestore)
            usingFirestore = true
            print("NewsletterManager: Using Firestore database for all newsletter data and attachments")
            FirebaseManager.shared.watchNewsletters { [weak self] items in
                print("NewsletterManager: Received \(items.count) newsletters from Firestore")
                let newslettersWithFiles = items.filter { $0.fileURL != nil }
                if !newslettersWithFiles.isEmpty {
                    print("NewsletterManager: Found \(newslettersWithFiles.count) newsletters with file attachments from Firestore")
                }
                DispatchQueue.main.async {
                    self?.newsletters = items.sorted { $0.date > $1.date }
                }
            }
        #else
            loadNewsletters()
        #endif
    }

    deinit {
        #if canImport(FirebaseFirestore)
            FirebaseManager.shared.stopWatchingNewsletters()
        #endif
    }

    func loadNewsletters() {
        guard !newslettersData.isEmpty,
            let data = newslettersData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([Newsletter].self, from: data)
        else {
            // Load default newsletters if no data exists
            loadDefaultNewsletters()
            return
        }
        newsletters = decoded.sorted { $0.date > $1.date }
    }

    func saveNewsletters() {
        guard !usingFirestore,
            let encoded = try? JSONEncoder().encode(newsletters),
            let string = String(data: encoded, encoding: .utf8)
        else { return }
        newslettersData = string
    }

    func addNewsletter(_ newsletter: Newsletter) {
        print("NewsletterManager: Adding newsletter to Firestore: \(newsletter.title)")
        print("NewsletterManager: Newsletter author: \(newsletter.author), email: \(newsletter.authorEmail)")
        print("NewsletterManager: Newsletter category: \(newsletter.category)")
        print("NewsletterManager: Newsletter is published: \(newsletter.isPublished)")
        
        if let fileName = newsletter.fileName, let fileData = newsletter.fileData {
            print("NewsletterManager: Newsletter has file attachment: \(fileName) (\(fileData.count) bytes)")
        } else {
            print("NewsletterManager: Newsletter has no file attachment")
        }
        
        // Optimistic update - add to local array immediately
        newsletters.insert(newsletter, at: 0)
        print("NewsletterManager: Added newsletter to local array, total count: \(newsletters.count)")
        
        if usingFirestore {
            print("NewsletterManager: Using Firestore, calling Firebase manager...")
            FirebaseManager.shared.createOrUpdateNewsletter(newsletter) { err in
                if let err = err {
                    print("NewsletterManager: ERROR creating newsletter: \(err)")
                    // Remove from local array on error
                    DispatchQueue.main.async {
                        self.newsletters.removeAll { $0.id == newsletter.id }
                        print("NewsletterManager: Removed failed newsletter from local array")
                    }
                } else {
                    print("NewsletterManager: Newsletter created successfully: \(newsletter.title)")
                }
            }
        } else {
            print("NewsletterManager: Not using Firestore, saving locally only")
            saveNewsletters()
        }
    }

    func updateNewsletter(_ newsletter: Newsletter) {
        // Optimistic update - update local array immediately
        if let index = newsletters.firstIndex(where: { $0.id == newsletter.id }) {
            newsletters[index] = newsletter
        }
        
        if usingFirestore {
            FirebaseManager.shared.createOrUpdateNewsletter(newsletter) { err in
                if let err = err {
                    print("Failed to update newsletter: \(err)")
                }
            }
        } else {
            saveNewsletters()
        }
    }

    func deleteNewsletter(_ newsletter: Newsletter) {
        if usingFirestore {
            // Optimistically remove from local UI first for better responsiveness
            newsletters.removeAll { $0.id == newsletter.id }
            
            // Clear cached image for deleted newsletter
            NewsletterImageCache.shared.removeImage(for: newsletter.id)

            FirebaseManager.shared.deleteNewsletter(id: newsletter.id.uuidString) { err in
                if let err = err {
                    print("Failed to delete newsletter: \(err)")
                    // Restore newsletter to local UI if delete failed
                    DispatchQueue.main.async {
                        self.newsletters.append(newsletter)
                        self.newsletters.sort { $0.date > $1.date }
                    }
                }
            }
        } else {
            newsletters.removeAll { $0.id == newsletter.id }
            // Clear cached image for deleted newsletter
            NewsletterImageCache.shared.removeImage(for: newsletter.id)
            saveNewsletters()
        }
    }

    func togglePin(_ newsletter: Newsletter) {
        var modified = newsletter
        modified.isPinned.toggle()

        // Optimistically update local UI first for better responsiveness
        if let index = newsletters.firstIndex(where: { $0.id == newsletter.id }) {
            newsletters[index].isPinned = modified.isPinned
        }

        updateNewsletter(modified)
    }

    private func loadDefaultNewsletters() {
        newsletters = [
            Newsletter(
                title: "Welcome to NeighborHub Newsletter",
                summary:
                    "Get the latest community updates, safety tips, and upcoming events delivered right to your home screen.",
                content:
                    "Welcome to the NeighborHub Newsletter system! This is where you'll find important community updates, safety alerts, event announcements, and more.\n\nFeatures:\n• Real-time community updates\n• Safety and security alerts\n• Event announcements\n• Local business highlights\n• Maintenance notifications\n\nStay connected with your neighborhood!",
                author: "NeighborHub Team",
                authorEmail: "admin@neighborhub.app",
                category: .general
            ),
            Newsletter(
                title: "July Community Update",
                summary: "Highlights from this month, upcoming events, and more!",
                content:
                    "July has been an amazing month for our community! Here are the highlights:\n\n• Community BBQ Success: Over 150 neighbors attended\n• New Playground Equipment: Installation completed\n• Safety Patrol Update: 5 new volunteers joined\n\nUpcoming in August:\n• Back-to-School Safety Drive\n• Community Garden Harvest Festival\n• Monthly Committee Meeting",
                author: "Community Committee",
                authorEmail: "committee@neighborhub.app",
                category: .events
            ),
            Newsletter(
                title: "Safety Tips for Summer",
                summary: "Stay safe with these tips from your neighborhood watch.",
                content:
                    "As summer continues, here are important safety reminders:\n\n🏠 Home Security:\n• Lock doors and windows when away\n• Use timer lights when traveling\n• Keep valuables out of sight\n\n🚗 Vehicle Safety:\n• Park in well-lit areas\n• Never leave items visible in cars\n• Report suspicious activity\n\n👥 Personal Safety:\n• Walk in groups when possible\n• Stay aware of surroundings\n• Know your neighbors\n\nRemember: If you see something, say something!",
                author: "Neighborhood Watch",
                authorEmail: "watch@neighborhub.app",
                category: .safety
            ),
        ]
        saveNewsletters()
    }
}

// MARK: - Enhanced NewslettersCard
struct NewslettersCard: View {
    @StateObject private var newsletterManager = NewsletterManager()
    @State private var selectedNewsletter: Newsletter?
    @State private var showAllNewsletters = false
    @State private var showCreateNewsletter = false

    // Admin logic
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

    // Add this property to receive the new flag from HomeView
    var allowEveryoneToCreateNewsletters: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with action buttons
            HStack {
                Image(systemName: "envelope.open.fill")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Community Newsletters")
                        .font(.headline)
                    if isAdmin {
                        Text("Committee Member")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if allowEveryoneToCreateNewsletters {
                        Text("Create Enabled")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else {
                        Text("View Only")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()

                // Show plus button if allowed for everyone or if admin
                if allowEveryoneToCreateNewsletters || isAdmin {
                    Button(action: { showCreateNewsletter = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                // View all button
                Button(action: { showAllNewsletters = true }) {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding([.top, .horizontal])

            Divider()

            // Newsletter previews (latest 3, pinned always first, published only)
            let sortedNewsletters = newsletterManager.newsletters.filter { $0.isPublished }.sorted {
                if $0.isPinned && !$1.isPinned { return true }
                if !$0.isPinned && $1.isPinned { return false }
                return $0.date > $1.date
            }
            if sortedNewsletters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "envelope.badge")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No newsletters yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if allowEveryoneToCreateNewsletters || isAdmin {
                        Button("Create First Newsletter") {
                            showCreateNewsletter = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(sortedNewsletters.prefix(3)) { newsletter in
                    NewsletterPreviewRow(newsletter: newsletter) {
                        selectedNewsletter = newsletter
                    }
                    if newsletter.id != sortedNewsletters.prefix(3).last?.id {
                        Divider()
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping the card (outside inner buttons) opens the full archive
            showAllNewsletters = true
        }
        .background(Color(.systemGray6).opacity(0.95))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        // Give the newsletters card its own top spacing and a slightly larger horizontal inset
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .sheet(item: $selectedNewsletter) { newsletter in
            NewsletterDetailView(newsletter: newsletter, newsletterManager: newsletterManager)
        }
        .sheet(isPresented: $showAllNewsletters) {
            NewsletterArchiveView(
                newsletterManager: newsletterManager,
                isAdmin: isAdmin,
                allowEveryoneToCreateNewsletters: allowEveryoneToCreateNewsletters
            )
        }
        .sheet(isPresented: $showCreateNewsletter) {
            CreateNewsletterView(
                newsletterManager: newsletterManager, userName: userName,
                userEmail: "\(userName.lowercased())@neighborhub.app")
        }
    }
}

// MARK: - Newsletter Preview Row
struct NewsletterPreviewRow: View {
    let newsletter: Newsletter
    let onTap: () -> Void
    @ObservedObject private var imageCache = NewsletterImageCache.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail image if available
                if let cachedImage = imageCache.getImage(for: newsletter) {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if imageCache.hasAttachment(for: newsletter) {
                    // Show placeholder while loading or if we expect an attachment
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundColor(.accentColor.opacity(0.5))
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: newsletter.category.icon)
                                .font(.caption2)
                                .foregroundColor(newsletter.category == .safety ? .red : .accentColor)
                            Text(newsletter.category.rawValue)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Show subcategory if available
                        if let businessSubcategory = newsletter.businessSubcategory {
                            HStack(spacing: 4) {
                                Image(systemName: businessSubcategory.icon)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text(businessSubcategory.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        } else if let advertSubcategory = newsletter.advertSubcategory {
                            HStack(spacing: 4) {
                                Image(systemName: advertSubcategory.icon)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(advertSubcategory.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Spacer()
                        if newsletter.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        Text(newsletter.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Text(newsletter.title)
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(newsletter.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Preload image when newsletter appears in list
            NewsletterImageCache.shared.preloadImage(for: newsletter)
        }
    }
}

// MARK: - Newsletter Detail View
struct NewsletterDetailView: View {
    let newsletter: Newsletter
    @ObservedObject var newsletterManager: NewsletterManager
    @ObservedObject private var imageCache = NewsletterImageCache.shared
    @StateObject private var submissionManager = NewsletterFormSubmissionManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var showEditView = false
    @State private var showFullScreenImage = false
    @State private var loadedImage: UIImage? = nil
    @State private var isLoadingImage = false
    @State private var showFormSubmission = false
    @State private var showFormSubmissions = false
    @State private var showFilePreview = false

    // Admin logic
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("userEmail") private var userEmail: String = ""
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
    
    // Load image asynchronously from data
    private func loadImageAsync() {
        guard let imageData = newsletter.imageData, loadedImage == nil, !isLoadingImage else {
            return
        }
        
        isLoadingImage = true
        DispatchQueue.global(qos: .userInitiated).async {
            let image = UIImage(data: imageData)
            DispatchQueue.main.async {
                self.loadedImage = image
                self.isLoadingImage = false
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: newsletter.category.icon)
                                    .foregroundColor(
                                        newsletter.category == .safety ? .red : .accentColor)
                                Text(newsletter.category.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if newsletter.isPinned {
                                HStack(spacing: 4) {
                                    Image(systemName: "pin.fill")
                                    Text("Pinned")
                                }
                                .font(.caption)
                                .foregroundColor(.orange)
                            }
                        }
                        Text(newsletter.title)
                            .font(.largeTitle)
                            .bold()
                        Text(newsletter.summary)
                            .font(.title3)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("By \(newsletter.author)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(newsletter.date, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Divider()

                    // Attachment display
                    if let cachedImage = imageCache.getImage(for: newsletter) {
                        // Display cached image - INSTANT!
                        VStack(spacing: 8) {
                            Button(action: { showFullScreenImage = true }) {
                                Image(uiImage: cachedImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 220)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Show document viewer button if newsletter has an attachment
                            // Check fileName (works for both Firestore and Storage files)
                            if let fileName = newsletter.fileName {
                                Button(action: { showFilePreview = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: fileName.lowercased().hasSuffix(".pdf") ? "doc.text.magnifyingglass" : "doc.text.viewfinder")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        Text(fileName.lowercased().hasSuffix(".pdf") ? "View PDF" : "Open Document")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.square")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            else {
                                // No file attachment available - this is normal for newsletters without PDFs
                                EmptyView()
                            }
                        }
                    } else if let image = loadedImage {
                        // Display async loaded image from embedded data
                        VStack(spacing: 8) {
                            Button(action: { showFullScreenImage = true }) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 220)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Show document viewer button if newsletter has an attachment
                            if let fileName = newsletter.fileName {
                                Button(action: { showFilePreview = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: fileName.lowercased().hasSuffix(".pdf") ? "doc.text.magnifyingglass" : "doc.text.viewfinder")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        Text(fileName.lowercased().hasSuffix(".pdf") ? "View PDF" : "Open Document")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.square")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    } else if newsletter.imageData != nil {
                        // Show loading indicator while image is being decoded
                        VStack(spacing: 8) {
                            ZStack {
                                Color.gray.opacity(0.1)
                                    .frame(maxHeight: 220)
                                    .cornerRadius(10)
                                
                                if isLoadingImage {
                                    ProgressView()
                                }
                            }
                            .onAppear {
                                loadImageAsync()
                            }
                            
                            // Show document viewer button if newsletter has an attachment
                            if let fileName = newsletter.fileName {
                                Button(action: { showFilePreview = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: fileName.lowercased().hasSuffix(".pdf") ? "doc.text.magnifyingglass" : "doc.text.viewfinder")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        Text(fileName.lowercased().hasSuffix(".pdf") ? "View PDF" : "Open Document")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.square")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    } else if newsletter.fileData != nil && newsletter.fileName != nil {
                        // Newsletter files are stored in Firestore - show file attachment info  
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                Text(newsletter.fileName ?? "Document")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }

                    // Content
                    Text(newsletter.content)
                        .font(.body)
                        .lineSpacing(4)

                    // Tags if any
                    if !newsletter.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.headline)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible()), count: 3),
                                spacing: 8
                            ) {
                                ForEach(newsletter.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    
                    // Form section if enabled
                    if newsletter.isFormEnabled && !newsletter.formFields.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.accentColor)
                                Text("Fillable Form Available")
                                    .font(.headline)
                            }
                            Text("This newsletter includes a form that you can fill out")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // Check if user already submitted
                            let userSubmissions = submissionManager.submissions.filter { submission in
                                guard let uid = Auth.auth().currentUser?.uid else { return false }
                                return submission.newsletterId == newsletter.id && submission.submitterId == uid
                            }
                            
                            if userSubmissions.isEmpty {
                                Button(action: { showFormSubmission = true }) {
                                    HStack {
                                        Image(systemName: "pencil.circle.fill")
                                        Text("Fill Form")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.accentColor)
                                    .cornerRadius(12)
                                }
                            } else {
                                VStack(spacing: 8) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Form Already Submitted")
                                            .font(.headline)
                                            .foregroundColor(.green)
                                    }
                                    Text("Submitted \(userSubmissions[0].submissionDate, style: .relative)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Status: \(userSubmissions[0].status.rawValue)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                            }
                            
                            if isAdmin || newsletter.allowPublicSubmissionView {
                                let submissionCount = submissionManager.submissions.filter { $0.newsletterId == newsletter.id }.count
                                Button(action: { showFormSubmissions = true }) {
                                    HStack {
                                        Image(systemName: "tray.full.fill")
                                        Text("View Submissions (\(submissionCount))")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if isAdmin {
                            Button(action: { showEditView = true }) {
                                Label("Edit", systemImage: "pencil")
                            }

                            Divider()
                        }

                        Button(action: { showShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button(action: { copyToClipboard() }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [newsletter.title, newsletter.summary])
        }
        .sheet(isPresented: $showEditView) {
            EditNewsletterView(newsletter: newsletter, newsletterManager: newsletterManager)
        }
        .sheet(isPresented: $showFormSubmission) {
            NewsletterFormSubmissionView(newsletter: newsletter, submissionManager: submissionManager)
        }
        .sheet(isPresented: $showFormSubmissions) {
            NewsletterSubmissionsView(newsletter: newsletter, submissionManager: submissionManager, isAdmin: isAdmin)
        }
        .sheet(isPresented: $showFilePreview) {
            NavigationView {
                NewsletterFilePreview(newsletter: newsletter)
                    .navigationTitle("Document")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            if let fileName = newsletter.fileName {
                                Text(fileName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showFilePreview = false
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showFullScreenImage) {
            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    VStack {
                        Spacer()
                        // Check cache first for instant display
                        if let cachedImage = imageCache.getImage(for: newsletter) {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(
                                    maxWidth: geometry.size.width, maxHeight: geometry.size.height
                                )
                                .background(Color.black)
                        }
                        // Show cached loaded image if available
                        else if let image = loadedImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(
                                    maxWidth: geometry.size.width, maxHeight: geometry.size.height
                                )
                                .background(Color.black)
                        }
                        // Otherwise show remote image
                        else if let fileURL = newsletter.fileURL, fileURL.scheme?.starts(with: "http") == true {
                            AsyncImage(url: fileURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .tint(.white)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(
                                            maxWidth: geometry.size.width, maxHeight: geometry.size.height
                                        )
                                case .failure:
                                    VStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.largeTitle)
                                            .foregroundColor(.white)
                                        Text("Failed to load image")
                                            .foregroundColor(.white)
                                    }
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        Spacer()
                    }
                    Button(action: { showFullScreenImage = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .padding()
                    }
                }
            }
        }
    }

    private func copyToClipboard() {
        let text = """
            \(newsletter.title)

            \(newsletter.summary)

            \(newsletter.content)

            By: \(newsletter.author)
            Date: \(newsletter.date.formatted(date: .abbreviated, time: .omitted))
            """
        UIPasteboard.general.string = text
    }
}

// MARK: - Image Compression Helper
extension UIImage {
    /// Compress and resize image to fit within Firestore's 1MB document limit
    /// Target: ~500KB after base64 encoding to leave room for other fields
    func compressedForFirestore() -> Data? {
        let maxSizeKB = 500
        let maxDimension: CGFloat = 1920 // Max width/height
        
        // Resize if needed
        var image = self
        if size.width > maxDimension || size.height > maxDimension {
            let scale = min(maxDimension / size.width, maxDimension / size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            draw(in: CGRect(origin: .zero, size: newSize))
            image = UIGraphicsGetImageFromCurrentImageContext() ?? self
            UIGraphicsEndImageContext()
        }
        
        // Compress with progressive quality reduction
        var compression: CGFloat = 0.85
        var data = image.jpegData(compressionQuality: compression)
        
        while let currentData = data, currentData.count > maxSizeKB * 1024 && compression > 0.1 {
            compression -= 0.1
            data = image.jpegData(compressionQuality: compression)
        }
        
        return data
    }
}

// MARK: - Document Compression Helper
extension Data {
    /// Compress document data to fit within Firestore's 1MB document limit
    /// Target: ~500KB after compression to leave room for base64 encoding and other fields
    func compressedForFirestore(originalFileName: String) -> Data? {
        let maxSizeKB = 500
        let targetSize = maxSizeKB * 1024
        
        // If already small enough, return as-is
        if self.count <= targetSize {
            print("Document \(originalFileName) is already small enough: \(self.count) bytes")
            return self
        }
        
        print("Document \(originalFileName) needs compression: \(self.count) bytes -> target: \(targetSize) bytes")
        
        // Try different compression strategies based on file type
        let fileExtension = (originalFileName as NSString).pathExtension.lowercased()
        
        switch fileExtension {
        case "pdf":
            // For PDFs, try to convert to compressed image if reasonable size
            if let compressedImageData = tryPDFToCompressedImage() {
                return compressedImageData
            }
            // Fallback to general compression
            fallthrough
        default:
            // Use zlib compression for general documents
            return try? (self as NSData).compressed(using: .zlib) as Data
        }
    }
    
    private func tryPDFToCompressedImage() -> Data? {
        guard let document = PDFDocument(data: self),
              let page = document.page(at: 0) else {
            return nil
        }
        
        // Render PDF page to image
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 1.5 // Reasonable quality for preview
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(size, true, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // White background
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Render PDF page
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Compress the rendered image
        return image?.compressedForFirestore()
    }
}

// MARK: - PDF Conversion Helper
/// Convert PDF document to UIImage (first page only for newsletters)
/// Returns nil if the URL is not a PDF or if conversion fails
func convertPDFToImage(from url: URL) -> UIImage? {
    // Use the centralized PDFToImageConverter with local method for files in app directory
    return PDFToImageConverter.convertLocalPDFToPreviewImage(url)
}

/// Try to generate an image preview from a file URL.
/// Handles: images, PDFs (first page), and falls back to QuickLook thumbnails for other file types (docx, xlsx, txt, etc.)
func generateImageFromFile(url: URL, maxDimension: CGFloat = 1200, scale: CGFloat = 2.0) -> UIImage? {
    // First, quick check for image types
    let pathExt = url.pathExtension.lowercased()
    if ["jpg","jpeg","png","heic","heif","tiff","gif"].contains(pathExt) {
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return img
        }
    }

    // PDF -> render first page
    if (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .pdf) == true || pathExt == "pdf" {
        return convertPDFToImage(from: url)
    }

    // Fallback: QuickLook thumbnail generation (async, so we block briefly to get a sync-like result)
    let size = CGSize(width: maxDimension, height: maxDimension)
    let semaphore = DispatchSemaphore(value: 0)
    var resultImage: UIImage? = nil

    let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: UIScreen.main.scale, representationTypes: .thumbnail)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { (thumb, error) in
        if let rep = thumb {
            // QLThumbnailRepresentation provides image data - prefer the UIImage representation when available
            // Some SDKs expose non-optional cgImage/uiImage; avoid optional binding on non-optional types.
            if let uiImage = rep.uiImage as UIImage? {
                resultImage = uiImage
            } else {
                // Fall back to CGImage-based initializer
                resultImage = UIImage(cgImage: rep.cgImage)
            }
        } else if let error = error {
            print("⚠️ Thumbnail generation failed: \(error)")
        }
        semaphore.signal()
    }

    // Wait up to 1 second for thumbnail (should be quick)
    _ = semaphore.wait(timeout: .now() + 1.0)
    return resultImage
}

// MARK: - Create Newsletter View
struct CreateNewsletterView: View {
    @ObservedObject var newsletterManager: NewsletterManager
    let userName: String
    let userEmail: String
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var summary = ""
    @State private var content = ""
    @State private var selectedCategory: NewsletterCategory = .localAdverts
    @State private var selectedBusinessSubcategory: BusinessSubcategory? = nil
    @State private var selectedAdvertSubcategory: AdvertSubcategory? = nil
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var isPinned = false
    @State private var enableForm = false
    @State private var formFields: [NewsletterFormField] = []
    @State private var allowPublicSubmissions = false
    @State private var showFormBuilder = false

    // Attachment state
    @State private var showAttachmentSheet = false
    @State private var showAttachmentPicker = false
    @State private var showDocumentPicker = false
    @State private var attachmentPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImage: UIImage? = nil
    @State private var selectedFileURL: URL? = nil
    @State private var originalFileURL: URL? = nil // Keep original file for PDFs
    @State private var originalPDFURL: URL? = nil // Store original PDF separately for full viewing
    @State private var showPDFPreview = false

    // For document picker image binding compatibility
    @State private var selectedImageFromDoc: UIImage? = nil
    
    // Check if user is admin/committee
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    private var isAdmin: Bool {
        return userIsAdmin || userIsCommittee
    }
    
    private var availableCategories: [NewsletterCategory] {
        if isAdmin {
            return NewsletterCategory.allCases
        } else {
            return [.localAdverts, .business]
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Category") {
                    Picker("Select Category", selection: $selectedCategory) {
                        ForEach(availableCategories) { category in
                            Label {
                                Text(category.rawValue)
                            } icon: {
                                Image(systemName: category.icon)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Show subcategory picker if Local Business is selected
                if selectedCategory == .business {
                    Section("Business Type") {
                        Picker("Business Type", selection: $selectedBusinessSubcategory) {
                            Text("Select Type").tag(nil as BusinessSubcategory?)
                            ForEach(BusinessSubcategory.allCases) { subcategory in
                                Label {
                                    Text(subcategory.rawValue)
                                } icon: {
                                    Image(systemName: subcategory.icon)
                                }
                                .tag(subcategory as BusinessSubcategory?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                // Show subcategory picker if Local Adverts is selected
                if selectedCategory == .localAdverts {
                    Section("Advert Type") {
                        Picker("Advert Type", selection: $selectedAdvertSubcategory) {
                            Text("Select Type").tag(nil as AdvertSubcategory?)
                            ForEach(AdvertSubcategory.allCases) { subcategory in
                                Label {
                                    Text(subcategory.rawValue)
                                } icon: {
                                    Image(systemName: subcategory.icon)
                                }
                                .tag(subcategory as AdvertSubcategory?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section("Newsletter Details") {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...3)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                        .contextMenu {
                            Button(action: {
                                if let pasteboardString = UIPasteboard.general.string {
                                    content += pasteboardString
                                }
                            }) {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .disabled(UIPasteboard.general.string == nil)
                        }
                }
                
                if isAdmin {
                    Section("Options") {
                        Toggle("Pin to Top", isOn: $isPinned)
                    }
                }
                
                // Form Section
                if isAdmin {
                    Section {
                        Toggle("Enable Form", isOn: $enableForm)
                    
                        if enableForm {
                        Button(action: { showFormBuilder = true }) {
                            HStack {
                                Image(systemName: formFields.isEmpty ? "doc.text.fill.badge.plus" : "doc.text.fill")
                                    .foregroundColor(.accentColor)
                                Text(formFields.isEmpty ? "Add Form Fields" : "\(formFields.count) Field\(formFields.count == 1 ? "" : "s")")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if !formFields.isEmpty {
                            Text("Users will be able to fill out this form and submit responses")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Toggle("Allow users to view submissions", isOn: $allowPublicSubmissions)
                            .font(.subheadline)
                    }
                } header: {
                    Text("Fillable Form")
                } footer: {
                    if enableForm && formFields.isEmpty {
                        Text("Add form fields to collect information from community members")
                    }
                }
                }

                // Attachment Section
                Section("Attachment") {
                    HStack(spacing: 16) {
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
                        Spacer()
                    }
                    .padding(.leading, 4)
                    .padding(.top, -8)
                    .actionSheet(isPresented: $showAttachmentSheet) {
                        ActionSheet(
                            title: Text("Attach"),
                            buttons: [
                                .default(Text("Photo Library")) {
                                    attachmentPickerSource = .photoLibrary
                                    showAttachmentPicker = true
                                },
                                .default(Text("Camera")) {
                                    attachmentPickerSource = .camera
                                    showAttachmentPicker = true
                                },
                                .default(Text("Files")) {
                                    showDocumentPicker = true
                                },
                                .cancel(),
                            ])
                    }
                    // Preview selected image
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                            .cornerRadius(8)
                    }
                    // Preview selected file
                    if let fileURL = selectedFileURL {
                        HStack {
                            Image(systemName: "doc")
                            Text(fileURL.lastPathComponent)
                                .font(.caption)
                        }
                    }
                    // Show PDF preview option if we have an original PDF
                    if originalPDFURL != nil {
                        Button(action: { showPDFPreview = true }) {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                Text("View Full PDF")
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                // Dismiss keyboard when tapping outside text fields
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("Create Newsletter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Publish") {
                        createNewsletter()
                    }
                    .disabled(title.isEmpty || summary.isEmpty || content.isEmpty)
                }
            }
            // Attachment pickers
            .sheet(isPresented: $showAttachmentPicker) {
                ImagePicker(image: $selectedImage, sourceType: attachmentPickerSource)
            }
            .sheet(isPresented: $showDocumentPicker) {
                LocalListingDocumentPicker(
                    fileURL: $selectedFileURL, 
                    image: $selectedImageFromDoc,
                    onPDFSelected: { copiedURL, pageImages, metadata in
                        // Check PDF file size (10MB limit)
                        if let metadata = metadata, metadata.fileSize > 10 * 1024 * 1024 {
                            print("Newsletter: PDF file too large (\(metadata.displaySize)), skipping conversion")
                            return
                        }
                        
                        if let firstImage = pageImages.first {
                            print("Newsletter: PDF conversion successful - \(pageImages.count) pages")
                            print("Newsletter: Setting preview image and original PDF URL")
                            
                            // Set BOTH selectedImage and originalPDFURL directly (don't rely on onChange)
                            selectedImage = firstImage
                            originalPDFURL = copiedURL
                            
                            // Also set selectedImageFromDoc for backward compatibility
                            selectedImageFromDoc = firstImage
                            selectedFileURL = nil
                            
                            print("Newsletter: Preview image size: \(firstImage.size)")
                            print("Newsletter: Original PDF saved at: \(copiedURL.lastPathComponent)")
                        } else {
                            print("Newsletter: PDF conversion failed - no images generated")
                        }
                    },
                    subdirectory: "Newsletters"
                )
                    .onChange(of: selectedFileURL) { _, newURL in
                        // Try to generate an image preview for a broad set of files
                        if let url = newURL, let preview = generateImageFromFile(url: url) {
                            selectedImage = preview
                            originalFileURL = url // Keep original file for full viewing
                            selectedFileURL = nil // Clear temp URL since we have preview
                        }
                    }
                    .onChange(of: selectedImageFromDoc) { _, newImage in
                        if let img = newImage {
                            selectedImage = img
                            selectedFileURL = nil
                            originalFileURL = nil
                            // Don't clear originalPDFURL here - it's set by onPDFSelected callback
                        }
                    }
            }
            .sheet(isPresented: $showFormBuilder) {
                NewsletterFormBuilderView(newsletter: Binding(
                    get: {
                        var tempNewsletter = Newsletter(
                            title: title,
                            summary: summary,
                            content: content,
                            author: userName,
                            authorEmail: userEmail,
                            category: selectedCategory
                        )
                        tempNewsletter.formFields = formFields
                        tempNewsletter.isFormEnabled = enableForm
                        tempNewsletter.allowPublicSubmissionView = allowPublicSubmissions
                        return tempNewsletter
                    },
                    set: { (updatedNewsletter: Newsletter) in
                        formFields = updatedNewsletter.formFields
                        enableForm = updatedNewsletter.isFormEnabled
                        allowPublicSubmissions = updatedNewsletter.allowPublicSubmissionView
                    }
                ))
            }
            .sheet(isPresented: $showPDFPreview) {
                if let pdfURL = originalPDFURL {
                    NavigationView {
                        QuickLookPreview(url: pdfURL)
                            .navigationTitle("PDF Document")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    if let url = originalPDFURL {
                                        Text(url.lastPathComponent)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") {
                                        showPDFPreview = false
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    private func createNewsletter() {
        var newsletter = Newsletter(
            title: title,
            summary: summary,
            content: content,
            author: userName.isEmpty ? "Anonymous" : userName,
            authorEmail: userEmail,
            category: selectedCategory
        )
        newsletter.isPinned = isPinned
        newsletter.isPublished = true  // Ensure newsletter is published when created
        newsletter.businessSubcategory = selectedCategory == .business ? selectedBusinessSubcategory : nil
        newsletter.advertSubcategory = selectedCategory == .localAdverts ? selectedAdvertSubcategory : nil
        newsletter.isFormEnabled = enableForm && !formFields.isEmpty
        newsletter.formFields = formFields
        newsletter.allowPublicSubmissionView = allowPublicSubmissions
        
        // Store image and file data directly for Firestore storage
        if let image = selectedImage {
            if let imageData = image.compressedForFirestore() {
                newsletter.imageData = imageData
                print("CreateNewsletterView: Stored preview image data (\(imageData.count) bytes)")
            } else {
                print("CreateNewsletterView: WARNING - Image compression failed!")
            }
        } else {
            print("CreateNewsletterView: WARNING - No preview image to save!")
        }
        
        // NOTE: Do NOT store local fileURL - it won't work for other users!
        // Instead, we store fileData + fileName which will be uploaded to Firebase Storage
        
        // Handle file attachment - store RAW data (FirebaseManager will handle Storage upload)
        if let fileURL = selectedFileURL {
            print("CreateNewsletterView: Processing file attachment: \(fileURL.lastPathComponent)")
            do {
                let rawFileData = try Data(contentsOf: fileURL)
                print("CreateNewsletterView: Read file data: \(rawFileData.count) bytes")
                
                // Store raw data - FirebaseManager will upload to Storage if needed
                newsletter.fileData = rawFileData
                newsletter.fileName = fileURL.lastPathComponent
                print("CreateNewsletterView: Stored file data for upload (\(rawFileData.count) bytes)")
            } catch {
                print("CreateNewsletterView: Error reading file data: \(error)")
            }
        } else if let pdfURL = originalPDFURL {
            print("CreateNewsletterView: Processing original PDF attachment: \(pdfURL.lastPathComponent)")
            do {
                let rawFileData = try Data(contentsOf: pdfURL)
                print("CreateNewsletterView: Read original PDF data: \(rawFileData.count) bytes")
                
                // Store raw data - FirebaseManager will upload to Storage if needed
                newsletter.fileData = rawFileData
                newsletter.fileName = pdfURL.lastPathComponent
                print("CreateNewsletterView: Stored original PDF data for upload (\(rawFileData.count) bytes)")
            } catch {
                print("CreateNewsletterView: Error reading original PDF data: \(error)")
            }
        }
        
        newsletterManager.addNewsletter(newsletter)
        
        // Dismiss immediately
        dismiss()
    }
}

// MARK: - Edit Newsletter View
struct EditNewsletterView: View {
    let newsletter: Newsletter
    @ObservedObject var newsletterManager: NewsletterManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var summary: String
    @State private var content: String
    @State private var selectedCategory: NewsletterCategory
    @State private var selectedBusinessSubcategory: BusinessSubcategory?
    @State private var selectedAdvertSubcategory: AdvertSubcategory?
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var isPinned: Bool
    // Attachment state
    @State private var imageData: Data?
    @State private var fileURL: URL?
    @State private var originalFileURL: URL? = nil // Keep original file for PDFs
    @State private var originalPDFURL: URL? = nil // Store original PDF separately for full viewing
    @State private var showPDFPreview = false
    @State private var showAttachmentSheet = false
    @State private var showAttachmentPicker = false
    @State private var showDocumentPicker = false
    @State private var attachmentPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImageFromDoc: UIImage? = nil

    init(newsletter: Newsletter, newsletterManager: NewsletterManager) {
        self.newsletter = newsletter
        self.newsletterManager = newsletterManager
        self._title = State(initialValue: newsletter.title)
        self._summary = State(initialValue: newsletter.summary)
        self._content = State(initialValue: newsletter.content)
        self._selectedCategory = State(initialValue: newsletter.category)
        self._selectedBusinessSubcategory = State(initialValue: newsletter.businessSubcategory)
        self._selectedAdvertSubcategory = State(initialValue: newsletter.advertSubcategory)
        self._tags = State(initialValue: newsletter.tags)
        self._isPinned = State(initialValue: newsletter.isPinned)
        self._imageData = State(initialValue: newsletter.imageData)
        self._fileURL = State(initialValue: newsletter.fileURL)
        self._originalFileURL = State(initialValue: newsletter.fileURL)
        // Check if it's a PDF for full viewing
        if let url = newsletter.fileURL, url.pathExtension.lowercased() == "pdf" {
            self._originalPDFURL = State(initialValue: url)
        }
    }
    
    // Check if user is admin/committee
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    private var isAdmin: Bool {
        return userIsAdmin || userIsCommittee
    }
    
    private var availableCategories: [NewsletterCategory] {
        if isAdmin {
            return NewsletterCategory.allCases
        } else {
            return [.localAdverts, .business]
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Category") {
                    Picker("Select Category", selection: $selectedCategory) {
                        ForEach(availableCategories) { category in
                            Label {
                                Text(category.rawValue)
                            } icon: {
                                Image(systemName: category.icon)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Show subcategory picker if Local Business is selected
                if selectedCategory == .business {
                    Section("Business Type") {
                        Picker("Business Type", selection: $selectedBusinessSubcategory) {
                            Text("Select Type").tag(nil as BusinessSubcategory?)
                            ForEach(BusinessSubcategory.allCases) { subcategory in
                                Label {
                                    Text(subcategory.rawValue)
                                } icon: {
                                    Image(systemName: subcategory.icon)
                                }
                                .tag(subcategory as BusinessSubcategory?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                // Show subcategory picker if Local Adverts is selected
                if selectedCategory == .localAdverts {
                    Section("Advert Type") {
                        Picker("Advert Type", selection: $selectedAdvertSubcategory) {
                            Text("Select Type").tag(nil as AdvertSubcategory?)
                            ForEach(AdvertSubcategory.allCases) { subcategory in
                                Label {
                                    Text(subcategory.rawValue)
                                } icon: {
                                    Image(systemName: subcategory.icon)
                                }
                                .tag(subcategory as AdvertSubcategory?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section("Newsletter Details") {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...3)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                        .contextMenu {
                            Button(action: {
                                if let pasteboardString = UIPasteboard.general.string {
                                    content += pasteboardString
                                }
                            }) {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .disabled(UIPasteboard.general.string == nil)
                        }
                }
                
                if isAdmin {
                    Section("Options") {
                        Toggle("Pin to Top", isOn: $isPinned)
                    }
                }

                // Attachment section (add/remove)
                Section("Attachment") {
                    if imageData != nil || fileURL != nil {
                        if let data = imageData, let uiImage = UIImage(data: data) {
                            HStack {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 80)
                                    .cornerRadius(8)
                                Spacer()
                                Button(action: { self.imageData = Optional<Data>.none }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .accessibilityLabel("Remove Image")
                            }
                        } else if let url = fileURL {
                            HStack {
                                Image(systemName: "doc")
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                Spacer()
                                Button(action: { self.fileURL = Optional<URL>.none }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .accessibilityLabel("Remove File")
                            }
                        }
                    }
                    Button(action: { showAttachmentSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "paperclip")
                                .font(.body)
                                .foregroundColor(.accentColor)
                            Text("Add Attachment")
                                .font(.callout)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Add Attachment")
                    .actionSheet(isPresented: $showAttachmentSheet) {
                        ActionSheet(
                            title: Text("Attach"),
                            buttons: [
                                .default(Text("Photo Library")) {
                                    attachmentPickerSource = .photoLibrary
                                    showAttachmentPicker = true
                                },
                                .default(Text("Camera")) {
                                    attachmentPickerSource = .camera
                                    showAttachmentPicker = true
                                },
                                .default(Text("Files")) {
                                    showDocumentPicker = true
                                },
                                .cancel(),
                            ])
                    }
                }

                Section("Newsletter Info") {
                    HStack {
                        Text("Author")
                        Spacer()
                        Text(newsletter.author)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(newsletter.date, style: .date)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                // Dismiss keyboard when tapping outside text fields
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("Edit Newsletter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updateNewsletter()
                    }
                    .disabled(title.isEmpty || summary.isEmpty || content.isEmpty)
                }
            }
            // Attachment pickers
            .sheet(isPresented: $showAttachmentPicker) {
                ImagePicker(
                    image: Binding(
                        get: { imageData != nil ? UIImage(data: imageData!) : nil },
                        set: { newImage in imageData = newImage?.jpegData(compressionQuality: 0.92)
                        }
                    ), sourceType: attachmentPickerSource)
            }
            .sheet(isPresented: $showDocumentPicker) {
                LocalListingDocumentPicker(
                    fileURL: Binding(
                        get: { fileURL },
                        set: { newURL in fileURL = newURL }
                    ),
                    image: $selectedImageFromDoc,
                    onPDFSelected: { copiedURL, pageImages, metadata in
                        // Check PDF file size (10MB limit)
                        if let metadata = metadata, metadata.fileSize > 10 * 1024 * 1024 {
                            print("Newsletter: PDF file too large (\(metadata.displaySize)), skipping conversion")
                            return
                        }
                        
                        if let firstImage = pageImages.first {
                            imageData = firstImage.compressedForFirestore()
                            originalPDFURL = copiedURL // Save original PDF for full viewing
                            originalFileURL = nil
                            fileURL = nil // Clear temp URL since we have preview
                            print("Newsletter: PDF converted to image successfully, original PDF saved (\(metadata?.displaySize ?? "unknown size"))")
                        } else {
                            print("Newsletter: PDF conversion failed - no images generated")
                        }
                    },
                    subdirectory: "Newsletters"
                )
                .onChange(of: fileURL) { _, newURL in
                    // Handle non-PDF files
                    if let url = newURL, url.pathExtension.lowercased() != "pdf" {
                        if let preview = generateImageFromFile(url: url) {
                            imageData = preview.compressedForFirestore()
                            originalFileURL = url // Keep original file for full viewing
                            originalPDFURL = nil
                            fileURL = nil // Clear temp URL since we have preview
                        }
                    }
                }
                                .onChange(of: selectedImageFromDoc) { _, newImage in
                    if let img = newImage {
                        imageData = img.compressedForFirestore()
                        fileURL = nil
                        originalFileURL = nil
                        // Don't clear originalPDFURL here - it's set by onPDFSelected callback
                    }
                }
            }
            
            // Show PDF preview option if we have an original PDF
            if originalPDFURL != nil {
                Button(action: { showPDFPreview = true }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("View Full PDF")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showPDFPreview) {
            if let pdfURL = originalPDFURL {
                NavigationView {
                    QuickLookPreview(url: pdfURL)
                        .navigationTitle("PDF Document")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                if let url = originalPDFURL {
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showPDFPreview = false
                                }
                            }
                        }
                }
            }
        }
    }

    private func updateNewsletter() {
        var updatedNewsletter = newsletter
        updatedNewsletter.title = title
        updatedNewsletter.summary = summary
        updatedNewsletter.content = content
        updatedNewsletter.category = selectedCategory
        updatedNewsletter.businessSubcategory = selectedCategory == .business ? selectedBusinessSubcategory : nil
        updatedNewsletter.advertSubcategory = selectedCategory == .localAdverts ? selectedAdvertSubcategory : nil
        updatedNewsletter.isPinned = isPinned
        
        // Store image and file data directly for Firestore storage
        if let data = imageData {
            updatedNewsletter.imageData = data
        }
        
        // NOTE: Do NOT store local fileURL - it won't work for other users!
        // Instead, we store fileData + fileName which will be uploaded to Firebase Storage
        
        // Handle file attachment - store RAW data (FirebaseManager will handle Storage upload)
        if let pdfURL = originalPDFURL {
            print("EditNewsletterView: Processing original PDF attachment: \(pdfURL.lastPathComponent)")
            do {
                let rawFileData = try Data(contentsOf: pdfURL)
                print("EditNewsletterView: Read original PDF data: \(rawFileData.count) bytes")
                
                // Store raw data - FirebaseManager will upload to Storage if needed
                updatedNewsletter.fileData = rawFileData
                updatedNewsletter.fileName = pdfURL.lastPathComponent
                print("EditNewsletterView: Stored original PDF data for upload (\(rawFileData.count) bytes)")
            } catch {
                print("EditNewsletterView: Error reading original PDF data: \(error)")
            }
        } else if let originalURL = originalFileURL {
            print("EditNewsletterView: Processing file attachment: \(originalURL.lastPathComponent)")
            do {
                let rawFileData = try Data(contentsOf: originalURL)
                print("EditNewsletterView: Read file data: \(rawFileData.count) bytes")
                
                // Store raw data - FirebaseManager will upload to Storage if needed
                updatedNewsletter.fileData = rawFileData
                updatedNewsletter.fileName = originalURL.lastPathComponent
                print("EditNewsletterView: Stored file data for upload (\(rawFileData.count) bytes)")
            } catch {
                print("EditNewsletterView: Error reading file data: \(error)")
            }
        } else if let localURL = fileURL {
            print("EditNewsletterView: Processing local file attachment: \(localURL.lastPathComponent)")
            do {
                let rawFileData = try Data(contentsOf: localURL)
                print("EditNewsletterView: Read file data: \(rawFileData.count) bytes")
                
                // Store raw data - FirebaseManager will upload to Storage if needed
                updatedNewsletter.fileData = rawFileData
                updatedNewsletter.fileName = localURL.lastPathComponent
                print("EditNewsletterView: Stored file data for upload (\(rawFileData.count) bytes)")
            } catch {
                print("EditNewsletterView: Error reading file data: \(error)")
            }
        }
        
        newsletterManager.updateNewsletter(updatedNewsletter)
        
        // Dismiss immediately
        dismiss()
    }
}

// MARK: - Newsletter Archive View
struct NewsletterArchiveView: View {
    @ObservedObject var newsletterManager: NewsletterManager
    let isAdmin: Bool
    let allowEveryoneToCreateNewsletters: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: NewsletterCategory? = nil
    @State private var newsletterToDelete: Newsletter?
    @State private var showDeleteAlert = false

    var filteredNewsletters: [Newsletter] {
        let filtered = newsletterManager.newsletters.filter { newsletter in
            let matchesSearch =
                searchText.isEmpty || newsletter.title.localizedCaseInsensitiveContains(searchText)
                || newsletter.summary.localizedCaseInsensitiveContains(searchText)
                || newsletter.content.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || newsletter.category == selectedCategory
            let isPublished = newsletter.isPublished  // Only show published newsletters
            return matchesSearch && matchesCategory && isPublished
        }
        // Pinned always first, then by date
        return filtered.sorted {
            if $0.isPinned && !$1.isPinned { return true }
            if !$0.isPinned && $1.isPinned { return false }
            return $0.date > $1.date
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                // Filters
                VStack(spacing: 12) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search newsletters...", text: $searchText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Category filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            FilterChip(
                                title: "All",
                                isSelected: selectedCategory == nil
                            ) {
                                selectedCategory = nil
                            }

                            ForEach(NewsletterCategory.allCases) { category in
                                FilterChip(
                                    title: category.rawValue,
                                    icon: category.icon,
                                    isSelected: selectedCategory == category
                                ) {
                                    selectedCategory = selectedCategory == category ? nil : category
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.horizontal)

                // Newsletter list
                List {
                    ForEach(filteredNewsletters) { newsletter in
                        NewsletterListRow(
                            newsletter: newsletter,
                            newsletterManager: newsletterManager,
                            isAdmin: isAdmin,
                            onPin: { newsletterManager.togglePin(newsletter) },
                            onDelete: {
                                newsletterToDelete = newsletter
                                showDeleteAlert = true
                            }
                        )
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("All Newsletters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Delete Newsletter", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let newsletter = newsletterToDelete {
                    newsletterManager.deleteNewsletter(newsletter)
                }
            }
        } message: {
            Text("Are you sure you want to delete this newsletter? This action cannot be undone.")
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    init(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - Newsletter List Row
struct NewsletterListRow: View {
    let newsletter: Newsletter
    @ObservedObject var newsletterManager: NewsletterManager
    let isAdmin: Bool
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var selectedNewsletter: Newsletter?
    @ObservedObject private var imageCache = NewsletterImageCache.shared

    var body: some View {
        Button(action: { selectedNewsletter = newsletter }) {
            HStack(spacing: 12) {
                // Thumbnail image if available
                if let cachedImage = imageCache.getImage(for: newsletter) {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if imageCache.hasAttachment(for: newsletter) {
                    // Show placeholder while loading or if we expect an attachment
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(.accentColor.opacity(0.5))
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: newsletter.category.icon)
                                .font(.caption)
                                .foregroundColor(newsletter.category == .safety ? .red : .accentColor)
                            Text(newsletter.category.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Show subcategory if available
                        if let businessSubcategory = newsletter.businessSubcategory {
                            HStack(spacing: 4) {
                                Image(systemName: businessSubcategory.icon)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text(businessSubcategory.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        } else if let advertSubcategory = newsletter.advertSubcategory {
                            HStack(spacing: 4) {
                                Image(systemName: advertSubcategory.icon)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text(advertSubcategory.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Spacer()
                        if newsletter.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Text(newsletter.date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(newsletter.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(newsletter.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack {
                        Text("By \(newsletter.author)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !newsletter.tags.isEmpty {
                            Text("#\(newsletter.tags.first ?? "")")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Preload image when newsletter appears in list
            NewsletterImageCache.shared.preloadImage(for: newsletter)
        }
        .contextMenu {
            if isAdmin {
                Button(action: onPin) {
                    Label(
                        newsletter.isPinned ? "Unpin" : "Pin to Top",
                        systemImage: newsletter.isPinned ? "pin.slash" : "pin")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(item: $selectedNewsletter) { newsletter in
            NewsletterDetailView(newsletter: newsletter, newsletterManager: newsletterManager)
        }
    }
}

// MARK: - Activity View Controller for Sharing
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
