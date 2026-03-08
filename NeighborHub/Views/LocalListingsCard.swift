import SwiftUI
import PDFKit
import QuickLook
import QuickLookThumbnailing
import UniformTypeIdentifiers
import PhotosUI
import FirebaseAuth
import WebKit

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

// MARK: - Local Listings Card (Combined Local Adverts & Business Listings)
// This card displays both Local Adverts and Local Business listings in a unified interface
// It replaces the previous separate Marketplace functionality

// MARK: - Listing Image Cache
class ListingImageCache: ObservableObject {
    static let shared = ListingImageCache()
    
    @Published private var cache: [UUID: UIImage] = [:]
    private var loadingQueue = DispatchQueue(label: "com.neighborhub.listing.imageloader", qos: .userInitiated)
    private var currentlyLoading: Set<UUID> = []
    
    private init() {}
    
    func getImage(for listing: LocalListing) -> UIImage? {
        return cache[listing.id]
    }
    
    func hasAttachment(for listing: LocalListing) -> Bool {
        return listing.imageData != nil || listing.imagesData != nil || listing.fileURL != nil
    }
    
    func preloadImage(for listing: LocalListing) {
        // Skip if already cached or loading
        guard cache[listing.id] == nil, !currentlyLoading.contains(listing.id) else {
            return
        }
        
        currentlyLoading.insert(listing.id)
        
        // Prioritize immediate imageData loading
        if let imageData = listing.imageData {
            loadingQueue.async { [weak self] in
                guard let strongSelf = self else { return }
                
                // Fast UIImage creation with optimized decoding
                let image = UIImage(data: imageData)
                
                DispatchQueue.main.async {
                    if let image = image {
                        strongSelf.cache[listing.id] = image
                    }
                    strongSelf.currentlyLoading.remove(listing.id)
                }
            }
        } else if let imagesData = listing.imagesData, let firstImageData = imagesData.first {
            // Use first image from multiple images array
            loadingQueue.async { [weak self] in
                guard let strongSelf = self else { return }
                
                let image = UIImage(data: firstImageData)
                
                DispatchQueue.main.async {
                    if let image = image {
                        strongSelf.cache[listing.id] = image
                    }
                    strongSelf.currentlyLoading.remove(listing.id)
                }
            }
        } else if let fileURL = listing.fileURL {
            // Only generate thumbnails for files when absolutely needed
            loadingQueue.async { [weak self] in
                guard let strongSelf = self else { return }
                
                // Use faster thumbnail generation for common file types
                let image = generateThumbnailFromFile(url: fileURL)
                
                DispatchQueue.main.async {
                    if let image = image {
                        strongSelf.cache[listing.id] = image
                    }
                    strongSelf.currentlyLoading.remove(listing.id)
                }
            }
        } else {
            currentlyLoading.remove(listing.id)
        }
    }
    
    func clearCache() {
        cache.removeAll()
        currentlyLoading.removeAll()
    }
    
    func removeImage(for listingId: UUID) {
        cache.removeValue(forKey: listingId)
    }
}

// MARK: - Local Listing Model
struct LocalListing: Identifiable, Codable {
    var id: UUID
    var title: String
    var summary: String
    var content: String
    var author: String
    var authorEmail: String
    var authorUID: String?
    var date: Date
    var category: NewsletterCategory  // Reusing the existing category enum
    var businessSubcategory: BusinessSubcategory?
    var advertSubcategory: AdvertSubcategory?
    var tags: [String]
    var isPublished: Bool
    var imageData: Data?  // Legacy single image support
    var imagesData: [Data]?  // Multiple images support
    var fileURL: URL?
    var fileData: Data?  // NEW: File data for hybrid storage
    var fileName: String?  // NEW: File name for hybrid storage
    var contactName: String?
    var contactPhone: String?
    var isSold: Bool?
    var soldDate: Date?
    
    init(
        title: String,
        summary: String,
        content: String,
        author: String,
        authorEmail: String,
        authorUID: String? = nil,
        category: NewsletterCategory
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.content = content
        self.author = author
        self.authorEmail = authorEmail
        self.authorUID = authorUID
        self.date = Date()
        self.category = category
        self.tags = []
        self.isPublished = true
        self.imageData = nil
        self.imagesData = nil
        self.fileURL = nil
    }
}

// MARK: - Local Listing Manager
class LocalListingManager: ObservableObject {
    @Published var listings: [LocalListing] = []
    @AppStorage("localListings") private var listingsData: String = ""
    @Published var isLoading: Bool = false

    private var usingFirestore: Bool = true  // Enable Firebase integration

    init() {
        print("LocalListingManager: Initializing...")
        #if canImport(FirebaseFirestore)
            usingFirestore = true
            print("LocalListingManager: Firebase enabled, setting up listener...")
            // Start watching Firebase immediately
            startWatchingFirebaseListings()
        #else
            print("LocalListingManager: Firebase not available, loading from cache...")
            loadListings()
        #endif
    }
    
    deinit {
        #if canImport(FirebaseFirestore)
            FirebaseManager.shared.stopWatchingLocalListings()
        #endif
    }
    


    func loadListings() {
        guard !listingsData.isEmpty,
            let data = listingsData.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([LocalListing].self, from: data)
        else {
            loadDefaultListings()
            return
        }
        listings = decoded.sorted { $0.date > $1.date }
        cleanupSoldListings()
    }
    
    private func cleanupSoldListings() {
        let now = Date()
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60) // 24 hours ago
        
        let originalCount = listings.count
        listings.removeAll { listing in
            // Remove listings that are sold and were marked as sold more than 24 hours ago
            if let soldDate = listing.soldDate, listing.isSold == true {
                return soldDate < twentyFourHoursAgo
            }
            return false
        }
        
        // Save if any items were removed
        if listings.count != originalCount {
            saveListings()
        }
    }

    func saveListings() {
        guard !usingFirestore,  // Only save locally when NOT using Firestore (like newsletters)
              let encoded = try? JSONEncoder().encode(listings),
              let string = String(data: encoded, encoding: .utf8)
        else { return }
        listingsData = string
    }

    func addListing(_ listing: LocalListing) {
        listings.insert(listing, at: 0)
        saveListings()
        
        // Add to Firebase if enabled
        #if canImport(FirebaseFirestore)
        if usingFirestore {
            addListingToFirebase(listing)
        }
        #endif
    }

    func updateListing(_ listing: LocalListing) {
        if let index = listings.firstIndex(where: { $0.id == listing.id }) {
            listings[index] = listing
        }
        saveListings()
        cleanupSoldListings()
        
        // Update in Firebase if enabled
        #if canImport(FirebaseFirestore)
        if usingFirestore {
            updateListingInFirebase(listing)
        }
        #endif
    }
    
    func performCleanup() {
        cleanupSoldListings()
    }

    func deleteListing(_ listing: LocalListing) {
        listings.removeAll { $0.id == listing.id }
        ListingImageCache.shared.removeImage(for: listing.id)
        saveListings()
        
        // Delete from Firebase if enabled
        #if canImport(FirebaseFirestore)
        if usingFirestore {
            FirebaseManager.shared.deleteLocalListing(id: listing.id.uuidString) { error in
                if let error = error {
                    print("Error deleting listing from Firebase: \(error)")
                }
            }
        }
        #endif
    }
    
    #if canImport(FirebaseFirestore)
    private func startWatchingFirebaseListings() {
        print("LocalListingManager: Starting Firebase listener for local listings")
        FirebaseManager.shared.watchLocalListings { [weak self] dtos in
            print("LocalListingManager: Received \(dtos.count) listings from Firebase")
            DispatchQueue.main.async {
                self?.syncWithFirebaseListings(dtos)
            }
        }
    }
    
    func refreshIfNeeded() {
        // If using Firestore but no listings loaded yet, the listener should be working
        // This is a no-op as the listener is always active
        print("LocalListingManager: Refresh check - currently have \(listings.count) listings")
    }
    
    private func syncWithFirebaseListings(_ dtos: [FirebaseManager.LocalListingDTO]) {
        print("LocalListingManager: Syncing \(dtos.count) Firebase listings")
        
        // Convert Firebase DTOs to LocalListing objects with optimized processing
        let firebaseListings: [LocalListing] = dtos.compactMap { dto in
            guard let category = NewsletterCategory(rawValue: dto.category) else { 
                print("LocalListingManager: Warning - Unknown category: \(dto.category)")
                return nil 
            }
            
            var listing = LocalListing(
                title: dto.title,
                summary: dto.summary,
                content: dto.content,
                author: dto.author,
                authorEmail: dto.authorEmail,
                authorUID: dto.authorUID,
                category: category
            )
            
            listing.id = dto.id
            listing.date = dto.date
            listing.tags = dto.tags
            listing.isPublished = dto.isPublished
            listing.contactName = dto.contactName
            listing.contactPhone = dto.contactPhone
            listing.isSold = dto.isSold
            listing.soldDate = dto.soldDate
            
            if let businessSubStr = dto.businessSubcategory {
                listing.businessSubcategory = BusinessSubcategory(rawValue: businessSubStr)
            }
            if let advertSubStr = dto.advertSubcategory {
                listing.advertSubcategory = AdvertSubcategory(rawValue: advertSubStr)
            }
            
            // Set file URL and fileName from Firebase (no immediate download)
            listing.fileURL = dto.fileURL
            listing.fileName = dto.fileName
            
            return listing
        }
        
        // Update listings immediately for fast UI update
        listings = firebaseListings.sorted { $0.date > $1.date }
        
        // Save to cache for instant loading on next app launch (preserves offline access)
        if let encoded = try? JSONEncoder().encode(listings),
           let string = String(data: encoded, encoding: .utf8) {
            listingsData = string
            print("LocalListingManager: Cached \(listings.count) listings to AppStorage")
        }
        
        // Download images in background with batching
        downloadImagesForFirebaseListingsBatched(firebaseListings, dtos: dtos)
    }
    
    func addListingToFirebase(_ listing: LocalListing) {
        print("LocalListingManager: Adding listing to Firebase: \(listing.title)")
        if let fileURL = listing.fileURL {
            print("LocalListingManager: Listing has file attachment: \(fileURL)")
            print("LocalListingManager: File URL scheme: \(fileURL.scheme ?? "none"), isFileURL: \(fileURL.isFileURL)")
        } else {
            print("LocalListingManager: Listing has no file attachment")
        }
        let dto = convertToDTO(listing)
        
        // Extract image data for upload
        let primaryImageData = listing.imageData
        let additionalImageData = listing.imagesData ?? []
        
        FirebaseManager.shared.createOrUpdateLocalListing(
            dto, primaryImageData: primaryImageData, additionalImageData: additionalImageData
        ) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("LocalListingManager: Error adding listing to Firebase: \(error)")
                    // Could add UI error handling here
                } else {
                    print("LocalListingManager: Successfully added listing to Firebase: \(listing.title)")
                }
            }
        }
    }
    
    private func updateListingInFirebase(_ listing: LocalListing) {
        print("LocalListingManager: Updating listing in Firebase: \(listing.title)")
        let dto = convertToDTO(listing)
        
        // Extract image data for upload
        let primaryImageData = listing.imageData
        let additionalImageData = listing.imagesData ?? []
        
        FirebaseManager.shared.createOrUpdateLocalListing(
            dto, primaryImageData: primaryImageData, additionalImageData: additionalImageData
        ) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("LocalListingManager: Error updating listing in Firebase: \(error)")
                    // Could add UI error handling here
                } else {
                    print("LocalListingManager: Successfully updated listing in Firebase: \(listing.title)")
                }
            }
        }
    }
    
    private func convertToDTO(_ listing: LocalListing) -> FirebaseManager.LocalListingDTO {
        var dto = FirebaseManager.LocalListingDTO(
            id: listing.id,
            title: listing.title,
            summary: listing.summary,
            content: listing.content,
            author: listing.author,
            authorEmail: listing.authorEmail,
            authorUID: listing.authorUID,
            date: listing.date,
            category: listing.category.rawValue,
            businessSubcategory: listing.businessSubcategory?.rawValue,
            advertSubcategory: listing.advertSubcategory?.rawValue,
            tags: listing.tags,
            isPublished: listing.isPublished,
            imageURL: nil,  // Will be set during upload
            imagesURLs: [],  // Will be set during upload
            fileURL: nil,  // Don't use legacy fileURL
            contactName: listing.contactName,
            contactPhone: listing.contactPhone,
            isSold: listing.isSold,
            soldDate: listing.soldDate
        )
        // NEW: Pass file data for hybrid storage
        dto.fileData = listing.fileData
        dto.fileName = listing.fileName
        return dto
    }
    
    private func downloadImagesForFirebaseListings(_ firebaseListings: [LocalListing], dtos: [FirebaseManager.LocalListingDTO]) {
        // Match each listing with its DTO to download images
        for (listing, dto) in zip(firebaseListings, dtos) {
            var _ = false
            let listingID = listing.id
            
            // Download primary image
            if let imageURL = dto.imageURL {
                downloadImageFromFirebase(url: imageURL) { [weak self] imageData in
                    DispatchQueue.main.async {
                        self?.updateListingImage(id: listingID, imageData: imageData, isAdditional: false)
                    }
                }
            }
            
            // Download additional images
            if !dto.imagesURLs.isEmpty {
                downloadMultipleImagesFromFirebase(urls: dto.imagesURLs) { [weak self] imagesDataArray in
                    DispatchQueue.main.async {
                        self?.updateListingImages(id: listingID, imagesData: imagesDataArray)
                    }
                }
            }
        }
    }
    
    private func downloadImagesForFirebaseListingsBatched(_ firebaseListings: [LocalListing], dtos: [FirebaseManager.LocalListingDTO]) {
        print("LocalListingManager: Starting batched image download for \(firebaseListings.count) listings")
        
        let batchSize = 5 // Download 5 images at a time to avoid overwhelming the system
        let batches = stride(from: 0, to: firebaseListings.count, by: batchSize).map {
            Array(zip(firebaseListings[$0..<min($0 + batchSize, firebaseListings.count)], 
                     dtos[$0..<min($0 + batchSize, dtos.count)]))
        }
        
        for (batchIndex, batch) in batches.enumerated() {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Double(batchIndex) * 0.5) {
                for (listing, dto) in batch {
                    let listingID = listing.id
                    
                    // Download primary image with higher priority
                    if let imageURL = dto.imageURL {
                        self.downloadImageFromFirebase(url: imageURL) { [weak self] imageData in
                            DispatchQueue.main.async {
                                self?.updateListingImage(id: listingID, imageData: imageData, isAdditional: false)
                            }
                        }
                    }
                    
                    // Download additional images with lower priority
                    if !dto.imagesURLs.isEmpty {
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                            self.downloadMultipleImagesFromFirebase(urls: dto.imagesURLs) { [weak self] imagesDataArray in
                                DispatchQueue.main.async {
                                    self?.updateListingImages(id: listingID, imagesData: imagesDataArray)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateListingImage(id: UUID, imageData: Data?, isAdditional: Bool) {
        guard let imageData = imageData else { return }
        
        if let index = listings.firstIndex(where: { $0.id == id }) {
            listings[index].imageData = imageData
            saveListings()
            print("LocalListingManager: Updated primary image for listing: \(listings[index].title)")
            // Trigger UI update
            objectWillChange.send()
        }
    }
    
    private func updateListingImages(id: UUID, imagesData: [Data]) {
        guard !imagesData.isEmpty else { return }
        
        if let index = listings.firstIndex(where: { $0.id == id }) {
            listings[index].imagesData = imagesData
            saveListings()
            print("LocalListingManager: Updated \(imagesData.count) additional images for listing: \(listings[index].title)")
            // Trigger UI update
            objectWillChange.send()
        }
    }
    
    private func downloadImageFromFirebase(url: URL, completion: @escaping (Data?) -> Void) {
        // Check if we already have this image cached locally
        let urlKey = url.absoluteString
        if let cachedData = UserDefaults.standard.data(forKey: "cachedImage_\(urlKey)") {
            print("LocalListingManager: Using cached image from Firebase URL")
            completion(cachedData)
            return
        }
        
        print("LocalListingManager: Downloading image from Firebase: \(url)")
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("LocalListingManager: Error downloading image: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data, UIImage(data: data) != nil else {
                print("LocalListingManager: Invalid image data from URL: \(url)")
                completion(nil)
                return
            }
            
            // Cache the downloaded image
            UserDefaults.standard.set(data, forKey: "cachedImage_\(urlKey)")
            print("LocalListingManager: Successfully downloaded and cached image from Firebase")
            completion(data)
        }.resume()
    }
    
    private func downloadMultipleImagesFromFirebase(urls: [URL], completion: @escaping ([Data]) -> Void) {
        guard !urls.isEmpty else {
            completion([])
            return
        }
        
        var downloadedData: [Data] = []
        let group = DispatchGroup()
        
        for url in urls {
            group.enter()
            downloadImageFromFirebase(url: url) { data in
                if let data = data {
                    downloadedData.append(data)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(downloadedData)
        }
    }
    #endif

    private func loadDefaultListings() {
        listings = [
            LocalListing(
                title: "Welcome to Local Listings",
                summary: "Find local businesses and community adverts all in one place",
                content: "This is your central hub for discovering local businesses and browsing community advertisements.\n\nFeatures:\n• Local Business Directory\n• Community Classifieds\n• Service Listings\n• Items For Sale\n• Job Opportunities\n\nConnect with your local community!",
                author: "NeighborHub Team",
                authorEmail: "admin@neighborhub.app",
                category: .general
            )
        ]
        saveListings()
    }
}

// MARK: - Local Listings Card
struct LocalListingsCard: View {
    @ObservedObject var listingManager: LocalListingManager
    @State private var selectedListing: LocalListing?
    @State private var showAllListings = false
    @State private var showCreateListing = false

    // Admin logic
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

    var allowEveryoneToCreateListings: Bool = true  // Default to true for community listings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with action buttons
            HStack {
                Image(systemName: "storefront.fill")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Listings")
                        .font(.headline)
                    if isAdmin {
                        Text("Committee Member")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if allowEveryoneToCreateListings {
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
                if allowEveryoneToCreateListings || isAdmin {
                    Button(action: { showCreateListing = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                }

                // View all button
                Button(action: { showAllListings = true }) {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding([.top, .horizontal])

            Divider()

            // Listing previews (latest 3, published only)
            let sortedListings = listingManager.listings.filter { $0.isPublished }.sorted {
                return $0.date > $1.date
            }
            
            Group {
                if sortedListings.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "storefront.badge")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No listings yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if allowEveryoneToCreateListings || isAdmin {
                            Button("Create First Listing") {
                                showCreateListing = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(sortedListings.prefix(4)) { listing in
                            ListingPreviewCard(listing: listing) {
                                selectedListing = listing
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Tap on the listings area to show all listings
                        showAllListings = true
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color(.systemGray6).opacity(0.95))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .sheet(item: $selectedListing) { listing in
            ListingDetailView(listing: listing, listingManager: listingManager)
        }
        .sheet(isPresented: $showAllListings) {
            ListingArchiveView(
                listingManager: listingManager,
                isAdmin: isAdmin,
                allowEveryoneToCreateListings: allowEveryoneToCreateListings
            )
        }
        .sheet(isPresented: $showCreateListing) {
            CreateListingView(
                listingManager: listingManager,
                userName: userName,
                userEmail: "\(userName.lowercased())@neighborhub.app"
            )
        }
        .onAppear {
            print("LocalListingsCard: View appeared, triggering cleanup...")
            listingManager.performCleanup()
            #if canImport(FirebaseFirestore)
            listingManager.refreshIfNeeded()
            #endif
        }
    }
}

// MARK: - Listing Preview Card (Grid Style)
struct ListingPreviewCard: View {
    let listing: LocalListing
    let onTap: () -> Void
    @ObservedObject private var imageCache = ListingImageCache.shared

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Large thumbnail image
                ZStack(alignment: .topTrailing) {
                    if let cachedImage = imageCache.getImage(for: listing) {
                        Image(uiImage: cachedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipped()
                    } else if imageCache.hasAttachment(for: listing) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(height: 120)
                            .overlay(
                                ProgressView()
                            )
                    } else {
                        Rectangle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [
                                    listing.category.color.opacity(0.3),
                                    listing.category.color.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(height: 120)
                            .overlay(
                                Image(systemName: listing.category.icon)
                                    .font(.largeTitle)
                                    .foregroundColor(listing.category.color.opacity(0.4))
                            )
                    }
                    
                    // SOLD badge overlay
                    if let advertSubcategory = listing.advertSubcategory,
                       advertSubcategory == .forSale && listing.isSold == true {
                        Text("SOLD")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .cornerRadius(4)
                            .padding(6)
                    }
                }
                
                // Content area
                VStack(alignment: .leading, spacing: 6) {
                    // Category badge
                    HStack(spacing: 4) {
                        Image(systemName: listing.category.icon)
                            .font(.caption2)
                        Text(listing.category.rawValue)
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(listing.category.color)
                    .cornerRadius(6)
                    
                    // Title
                    Text(listing.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Subcategory if available
                    if let businessSubcategory = listing.businessSubcategory {
                        HStack(spacing: 4) {
                            Image(systemName: businessSubcategory.icon)
                                .font(.caption2)
                            Text(businessSubcategory.rawValue)
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    } else if let advertSubcategory = listing.advertSubcategory {
                        HStack(spacing: 4) {
                            Image(systemName: advertSubcategory.icon)
                                .font(.caption2)
                            Text(advertSubcategory.rawValue)
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Date
                    Text(listing.date, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(height: 120)
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .shadow(color: listing.category.color.opacity(0.25), radius: 5, x: 0, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(listing.category.color.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            ListingImageCache.shared.preloadImage(for: listing)
        }
    }
}

// MARK: - Listing Preview Row
struct ListingPreviewRow: View {
    let listing: LocalListing
    let onTap: () -> Void
    @ObservedObject private var imageCache = ListingImageCache.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail image if available
                if let cachedImage = imageCache.getImage(for: listing) {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if imageCache.hasAttachment(for: listing) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.7)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: listing.category.icon)
                                .font(.caption2)
                                .foregroundColor(listing.category.color)
                            Text(listing.category.rawValue)
                                .font(.caption2)
                                .foregroundColor(listing.category.color)
                        }
                        
                        Spacer()
                        
                        Text(listing.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    // Show subcategory on separate line if available
                    if let businessSubcategory = listing.businessSubcategory {
                        HStack(spacing: 4) {
                            Image(systemName: businessSubcategory.icon)
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(businessSubcategory.rawValue)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    } else if let advertSubcategory = listing.advertSubcategory {
                        HStack(spacing: 4) {
                            Image(systemName: advertSubcategory.icon)
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(advertSubcategory.rawValue)
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            // Show SOLD badge for For Sale items
                            if advertSubcategory == .forSale && listing.isSold == true {
                                Text("SOLD")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            }
                        }
                    }

                    Text(listing.title)
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(listing.summary)
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
            ListingImageCache.shared.preloadImage(for: listing)
        }
    }
}

// MARK: - Listing Detail View
struct ListingDetailView: View {
    let listing: LocalListing
    @ObservedObject var listingManager: LocalListingManager
    @ObservedObject private var imageCache = ListingImageCache.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var showEditView = false
    @State private var showFullScreenImage = false
    @State private var showFilePreview = false
    @State private var selectedImageIndex: Int = 0
    @State private var loadedImage: UIImage? = nil
    @State private var loadedImages: [UIImage] = []
    @State private var isLoadingImage = false

    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userEmail") private var userEmail: String = ""
    @AppStorage("userUID") private var userUID: String = ""
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false

    private var isAdmin: Bool {
        return userIsAdmin || userIsCommittee
    }
    
    private var isOwner: Bool {
        // Use Firebase UID for ownership check (primary method)
        if let authorUID = listing.authorUID, !authorUID.isEmpty, !userUID.isEmpty {
            return authorUID == userUID
        }
        // Fallback to email comparison for legacy listings without UID
        return listing.authorEmail.lowercased() == userEmail.lowercased()
    }
    
    private var canEdit: Bool {
        return isOwner || isAdmin
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: listing.category.icon)
                                .font(.caption)
                                .foregroundColor(listing.category.color)
                            Text(listing.category.rawValue)
                                .font(.caption)
                                .foregroundColor(listing.category.color)
                            
                            // Show SOLD badge for For Sale items
                            if listing.advertSubcategory == .forSale && listing.isSold == true {
                                Text("• SOLD")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.red)
                                    .cornerRadius(6)
                            }
                        }
                        Text(listing.title)
                            .font(.largeTitle)
                            .bold()
                        Text(listing.summary)
                            .font(.title3)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("By \(listing.author)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(listing.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Divider()

                    // Attachment display - Multiple images support (including PDF pages)
                    if let imagesData = listing.imagesData, !imagesData.isEmpty {
                        VStack(spacing: 12) {
                            ZStack(alignment: .topLeading) {
                                TabView(selection: $selectedImageIndex) {
                                    ForEach(imagesData.indices, id: \.self) { index in
                                        if let image = UIImage(data: imagesData[index]) {
                                            Button(action: { 
                                                selectedImageIndex = index
                                                showFullScreenImage = true 
                                            }) {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .cornerRadius(12)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .tag(index)
                                        }
                                    }
                                }
                                .frame(height: 300)
                                .tabViewStyle(.page(indexDisplayMode: .always))
                                
                                // Check for PDF tag to show document indicator
                                if listing.tags.contains(where: { $0.hasPrefix("PDF-") }) {
                                    HStack {
                                        Image(systemName: "doc.fill")
                                            .foregroundColor(.white)
                                        Text("Document")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                                    .padding(8)
                                }
                                
                                // SOLD badge overlay for For Sale items
                                if listing.advertSubcategory == .forSale && listing.isSold == true {
                                    VStack {
                                        Text("SOLD")
                                            .font(.system(size: 60, weight: .black, design: .rounded))
                                            .foregroundColor(.white)
                                            .tracking(8)
                                            .padding(.horizontal, 40)
                                            .padding(.vertical, 20)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.red)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .strokeBorder(Color.white, lineWidth: 6)
                                                    )
                                                    .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 8)
                                            )
                                            .rotationEffect(.degrees(-15))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 3)
                                                    .blur(radius: 2)
                                                    .offset(x: 4, y: 4)
                                                    .rotationEffect(.degrees(-15))
                                            )
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            
                            HStack {
                                if imagesData.count > 1 {
                                    Text("\(selectedImageIndex + 1) of \(imagesData.count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if listing.tags.contains(where: { $0.hasPrefix("PDF-") }) {
                                    if let pdfTag = listing.tags.first(where: { $0.hasPrefix("PDF-") }) {
                                        Text("• \(pdfTag.replacingOccurrences(of: "PDF-", with: ""))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            
                            // NEW: Show document viewer button if listing has a file attachment (like newsletters)
                            if let fileName = listing.fileName {
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
                    }
                    // Single image fallback
                    else if let cachedImage = imageCache.getImage(for: listing) {
                        VStack(spacing: 8) {
                            ZStack {
                                Button(action: { showFullScreenImage = true }) {
                                    Image(uiImage: cachedImage)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                // SOLD badge overlay for For Sale items
                                if listing.advertSubcategory == .forSale && listing.isSold == true {
                                    VStack {
                                        Text("SOLD")
                                            .font(.system(size: 60, weight: .black, design: .rounded))
                                            .foregroundColor(.white)
                                            .tracking(8)
                                            .padding(.horizontal, 40)
                                            .padding(.vertical, 20)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.red)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .strokeBorder(Color.white, lineWidth: 6)
                                                    )
                                                    .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 8)
                                            )
                                            .rotationEffect(.degrees(-15))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 3)
                                                    .blur(radius: 2)
                                                    .offset(x: 4, y: 4)
                                                    .rotationEffect(.degrees(-15))
                                            )
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            
                            // Show document viewer button if listing has a file attachment (matches newsletters pattern)
                            if let fileName = listing.fileName {
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
                    }
                    
                    // File attachment display (legacy - new files converted to images)
                    if let fileURL = listing.fileURL {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Document Attached")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text(fileURL.lastPathComponent)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            
                            // Debug info for testing
                            Text("Legacy file attachment - new uploads convert to images")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }

                    // Content
                    Text(listing.content)
                        .font(.body)
                        .lineSpacing(4)
                    
                    // Contact Information
                    if let contactName = listing.contactName, let contactPhone = listing.contactPhone, 
                       !contactName.isEmpty, !contactPhone.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "person.crop.circle")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                Text("Contact Information")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.bottom, 4)
                            
                            VStack(spacing: 12) {
                                // Contact Name
                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Name")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(contactName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                }
                                
                                Divider()
                                
                                // Phone Number
                                HStack(spacing: 12) {
                                    Image(systemName: "phone.fill")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Phone")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(contactPhone)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                }
                                
                                Divider()
                                
                                // Action Buttons
                                HStack(spacing: 10) {
                                    Button(action: {
                                        if let url = URL(string: "tel:\(contactPhone)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Label("Call", systemImage: "phone.fill")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.accentColor)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                    }
                                    
                                    Button(action: {
                                        var waNumber = contactPhone.filter { $0.isNumber }
                                        if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                            waNumber = "27" + waNumber.dropFirst()
                                        }
                                        if let url = URL(string: "https://wa.me/\(waNumber)") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Label("WhatsApp", systemImage: "message.fill")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.green)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                    }
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = contactPhone
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.body)
                                            .frame(width: 44, height: 44)
                                            .background(Color(.systemGray5))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // Tags if any
                    if !listing.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.headline)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible()), count: 3),
                                spacing: 8
                            ) {
                                ForEach(listing.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(8)
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
                        if canEdit {
                            Button(action: { showEditView = true }) {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        
                        // Show sold toggle only for For Sale items and only for owner/admin
                        if listing.advertSubcategory == .forSale && canEdit {
                            Button(action: { toggleSoldStatus() }) {
                                if listing.isSold == true {
                                    Label("Mark as Available", systemImage: "checkmark.circle")
                                } else {
                                    Label("Mark as Sold", systemImage: "checkmark.circle.fill")
                                }
                            }
                        }
                        
                        if canEdit {
                            Divider()
                            
                            Button(role: .destructive, action: { showDeleteAlert = true }) {
                                Label("Delete Listing", systemImage: "trash")
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
            ActivityViewController(activityItems: [listing.title, listing.summary])
        }
        .sheet(isPresented: $showEditView) {
            EditListingView(listing: listing, listingManager: listingManager)
        }
        .sheet(isPresented: $showFilePreview) {
            NavigationView {
                LocalListingFilePreview(listing: listing)
                    .navigationTitle("Document")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showFilePreview = false
                            }
                        }
                    }
            }
        }
        .alert("Delete Listing", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                listingManager.deleteListing(listing)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete '\(listing.title)'? This action cannot be undone.")
        }
        .fullScreenCover(isPresented: $showFullScreenImage) {
            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    
                    // Multiple images gallery
                    if let imagesData = listing.imagesData, !imagesData.isEmpty {
                        TabView(selection: $selectedImageIndex) {
                            ForEach(imagesData.indices, id: \.self) { index in
                                if let image = UIImage(data: imagesData[index]) {
                                    VStack {
                                        Spacer()
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                        Spacer()
                                    }
                                    .tag(index)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                    }
                    // Single image fallback
                    else if let cachedImage = imageCache.getImage(for: listing) {
                        VStack {
                            Spacer()
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                            Spacer()
                        }
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
            \(listing.title)

            \(listing.summary)

            \(listing.content)

            By: \(listing.author)
            Date: \(listing.date.formatted(date: .abbreviated, time: .omitted))
            """
        UIPasteboard.general.string = text
    }
    
    private func toggleSoldStatus() {
        var updatedListing = listing
        let newSoldStatus = !(listing.isSold ?? false)
        updatedListing.isSold = newSoldStatus
        updatedListing.soldDate = newSoldStatus ? Date() : nil
        listingManager.updateListing(updatedListing)
    }
}

// MARK: - Create Listing View
struct CreateListingView: View {
    @ObservedObject var listingManager: LocalListingManager
    let userName: String
    let userEmail: String
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var summary = ""
    @State private var content = ""
    @State private var selectedCategory: NewsletterCategory = .localAdverts
    @State private var selectedBusinessSubcategory: BusinessSubcategory? = nil
    @State private var selectedAdvertSubcategory: AdvertSubcategory? = nil
    
    // Attachment state
    @State private var showAttachmentSheet = false
    @State private var showAttachmentPicker = false
    @State private var showDocumentPicker = false
    @State private var showPhotosPicker = false
    @State private var attachmentPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImage: UIImage? = nil
    @State private var selectedImages: [UIImage] = []  // Multiple images support
    @State private var selectedFileURL: URL? = nil
    @State private var originalFileURL: URL? = nil // Keep original file for PDFs
    @State private var originalPDFURL: URL? = nil // Store original PDF separately for full viewing (matches newsletters)
    @State private var showPDFPreview = false
    @State private var selectedImageFromDoc: UIImage? = nil
    @State private var attachedFileData: Data? = nil  // NEW: Direct file data for hybrid storage
    @State private var attachedFileName: String? = nil  // NEW: File name for hybrid storage
    @State private var showFileSizeError = false
    @State private var fileSizeErrorMessage = ""

    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    // Contact information state
    @AppStorage("userName") private var registeredFirstName: String = ""
    @AppStorage("userCell") private var registeredPhone: String = ""
    @AppStorage("userUID") private var userUID: String = ""
    @State private var useRegisteredContact = true
    @State private var contactName = ""
    @State private var contactPhone = ""
    @State private var tags: [String] = []
    
    private var isAdmin: Bool {
        return userIsAdmin || userIsCommittee
    }
    
    private var availableCategories: [NewsletterCategory] {
        return [.localAdverts, .business]
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
                
                Section("Listing Details") {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...3)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                }
                
                // Contact Information Section
                Section("Contact Information") {
                    Toggle("Use my registered contact details", isOn: $useRegisteredContact)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    if useRegisteredContact {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Name:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(registeredFirstName.isEmpty ? "Not set" : registeredFirstName)
                                    .font(.callout)
                            }
                            
                            HStack {
                                Text("Phone:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(registeredPhone.isEmpty ? "Not set" : registeredPhone)
                                    .font(.callout)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 12) {
                            TextField("Contact Name", text: $contactName)
                                .textContentType(.name)
                            
                            TextField("Contact Phone", text: $contactPhone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
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
                                .default(Text("Multiple Photos")) {
                                    showPhotosPicker = true
                                },
                                .default(Text("Single Photo")) {
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
                    
                    // Preview multiple images (including PDF pages)
                    if !selectedImages.isEmpty {
                        let isPDF = tags.contains { $0.hasPrefix("PDF-") }
                        let _ = print("CreateListingView UI: Showing \(selectedImages.count) images, isPDF: \(isPDF), tags: \(tags)")
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                // Show appropriate label for PDF vs. regular images
                                let countText = isPDF ? "\(selectedImages.count) page(s)" : "\(selectedImages.count) photo(s) selected"
                                Text(countText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // Show PDF indicator badge
                                if isPDF {
                                    Image(systemName: "doc.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text("Document")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                                
                                // Show PDF metadata
                                if isPDF, let pdfTag = tags.first(where: { $0.hasPrefix("PDF-") }) {
                                    Text(pdfTag.replacingOccurrences(of: "PDF-", with: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(selectedImages.indices, id: \.self) { index in
                                        ZStack(alignment: .topTrailing) {
                                            ZStack(alignment: .bottomLeading) {
                                                Image(uiImage: selectedImages[index])
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 100, height: 100)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                
                                                // Page number indicator for PDFs
                                                if isPDF && selectedImages.count > 1 {
                                                    Text("\(index + 1)")
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.white)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.black.opacity(0.7))
                                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                                        .padding(4)
                                                }
                                            }
                                            
                                            Button(action: {
                                                selectedImages.remove(at: index)
                                                // Clear PDF tags if all images removed
                                                if selectedImages.isEmpty {
                                                    tags.removeAll { $0.hasPrefix("PDF-") }
                                                }
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(Color.black.opacity(0.6)))
                                            }
                                            .padding(4)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Preview single image (including single-page PDF)
                    else if let image = selectedImage {
                        let isPDF = tags.contains { $0.hasPrefix("PDF-") }
                        let _ = print("CreateListingView UI: Showing single image, isPDF: \(isPDF), tags: \(tags)")
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // Show PDF indicator for single-page PDFs
                                let isPDF = tags.contains { $0.hasPrefix("PDF-") }
                                if isPDF {
                                    Image(systemName: "doc.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text("Document")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .fontWeight(.medium)
                                    
                                    // Show PDF metadata
                                    if let pdfTag = tags.first(where: { $0.hasPrefix("PDF-") }) {
                                        Text("• \(pdfTag.replacingOccurrences(of: "PDF-", with: ""))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120)
                                .cornerRadius(8)
                        }
                    }
                    // Show PDF preview option if we have an original PDF (matches newsletters)
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
                    // Preview selected file
                    if let fileURL = selectedFileURL {
                        HStack {
                            Image(systemName: "doc")
                            Text(fileURL.lastPathComponent)
                                .font(.caption)
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
            .navigationTitle("Create Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Publish") {
                        createListing()
                    }
                    .disabled(title.isEmpty || summary.isEmpty || content.isEmpty)
                }
            }
            // Attachment pickers
            .sheet(isPresented: $showPhotosPicker) {
                PhotoPicker(limit: 10) { images in
                    selectedImages = images
                    selectedImage = nil  // Clear single image if multiple selected
                    selectedFileURL = nil
                    // Clear PDF tags when regular photos are selected
                    tags.removeAll { $0.hasPrefix("PDF-") }
                    print("CreateListingView: Selected \(images.count) regular photos, cleared PDF tags")
                }
            }
            .sheet(isPresented: $showAttachmentPicker) {
                ImagePicker(image: $selectedImage, sourceType: attachmentPickerSource)
                    .onChange(of: selectedImage) { _, newImage in
                        if newImage != nil {
                            selectedImages = []  // Clear multiple images if single selected
                            // Clear PDF tags when regular image is selected
                            tags.removeAll { $0.hasPrefix("PDF-") }
                            print("CreateListingView: Selected single regular image, cleared PDF tags")
                        }
                    }
            }
            .sheet(isPresented: $showDocumentPicker) {
                LocalListingDocumentPicker(
                    fileURL: $selectedFileURL, 
                    image: $selectedImageFromDoc,
                    onPDFSelected: { copiedURL, pageImages, metadata in
                        // Check PDF file size (100MB limit for local listings)
                        if let metadata = metadata, metadata.fileSize > 100 * 1024 * 1024 {
                            print("LocalListing: PDF file too large (\(metadata.displaySize)), skipping conversion")
                            return
                        }
                        
                        if let firstImage = pageImages.first {
                            print("LocalListing: PDF conversion successful - \(pageImages.count) pages")
                            print("LocalListing: Setting preview image and original PDF URL")
                            
                            // Set BOTH selectedImage and originalPDFURL directly (matches newsletters pattern)
                            selectedImage = firstImage
                            originalPDFURL = copiedURL
                            
                            // Also set selectedImageFromDoc for backward compatibility
                            selectedImageFromDoc = firstImage
                            selectedFileURL = nil
                            
                            print("LocalListing: Preview image size: \(firstImage.size)")
                            print("LocalListing: Original PDF saved at: \(copiedURL.lastPathComponent)")
                        } else {
                            print("LocalListing: PDF conversion failed - no images generated")
                        }
                    },
                    subdirectory: "LocalListings"
                )
                    .onChange(of: selectedFileURL) { _, newURL in
                        // Try to generate an image preview for a broad set of files (matches newsletters)
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
            .alert("File Size Error", isPresented: $showFileSizeError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(fileSizeErrorMessage)
            }
        }
    }

    private func createListing() {
        var listing = LocalListing(
            title: title,
            summary: summary,
            content: content,
            author: userName.isEmpty ? "Anonymous" : userName,
            authorEmail: userEmail,
            authorUID: userUID.isEmpty ? nil : userUID,
            category: selectedCategory
        )
        listing.isPublished = true
        listing.businessSubcategory = selectedCategory == .business ? selectedBusinessSubcategory : nil
        listing.advertSubcategory = selectedCategory == .localAdverts ? selectedAdvertSubcategory : nil
        
        // Store contact information
        if useRegisteredContact {
            listing.contactName = registeredFirstName
            listing.contactPhone = registeredPhone
        } else {
            listing.contactName = contactName.isEmpty ? nil : contactName
            listing.contactPhone = contactPhone.isEmpty ? nil : contactPhone
        }
        
        // Store image and file data directly for Firestore storage (matches newsletters)
        // Store images - prioritize multiple images, then single image
        if !selectedImages.isEmpty {
            let compressedImages = selectedImages.compactMap { $0.compressedForFirestore() }
            if !compressedImages.isEmpty {
                listing.imagesData = compressedImages
                listing.imageData = compressedImages.first  // Set first as primary for legacy support
                print("CreateListingView: Stored \(compressedImages.count) image(s) data")
            }
        } else if let image = selectedImage {
            if let imageData = image.compressedForFirestore() {
                listing.imageData = imageData
                print("CreateListingView: Stored preview image data (\(imageData.count) bytes)")
            } else {
                print("CreateListingView: WARNING - Image compression failed!")
            }
        }
        
        // NOTE: Do NOT store local fileURL - it won't work for other users!
        // Instead, we store fileData + fileName which will be uploaded to Firebase Storage
        
        // Handle file attachment - store RAW data (FirebaseManager will handle Storage upload)
        if let fileURL = selectedFileURL {
            print("CreateListingView: Processing file attachment: \(fileURL.lastPathComponent)")
            do {
                let rawFileData = try Data(contentsOf: fileURL)
                print("CreateListingView: Read file data: \(rawFileData.count) bytes")
                
                // Validate file size (100MB limit)
                if rawFileData.count > 100 * 1024 * 1024 {
                    let fileSizeMB = Double(rawFileData.count) / 1024.0 / 1024.0
                    fileSizeErrorMessage = String(format: "File too large (%.1f MB). Maximum size: 100 MB", fileSizeMB)
                    showFileSizeError = true
                    print("CreateListingView: File size validation failed: \(fileSizeErrorMessage)")
                    return
                }
                
                // Store raw data - FirebaseManager will upload to Storage if needed
                listing.fileData = rawFileData
                listing.fileName = fileURL.lastPathComponent
                print("CreateListingView: Stored file data for upload (\(rawFileData.count) bytes)")
            } catch {
                print("CreateListingView: Error reading file data: \(error)")
            }
        } else if let pdfURL = originalPDFURL {
            print("CreateListingView: Processing original PDF attachment: \(pdfURL.lastPathComponent)")
            do {
                let rawFileData = try Data(contentsOf: pdfURL)
                print("CreateListingView: Read original PDF data: \(rawFileData.count) bytes")
                
                // Validate file size (100MB limit)
                if rawFileData.count > 100 * 1024 * 1024 {
                    let fileSizeMB = Double(rawFileData.count) / 1024.0 / 1024.0
                    fileSizeErrorMessage = String(format: "File too large (%.1f MB). Maximum size: 100 MB", fileSizeMB)
                    showFileSizeError = true
                    print("CreateListingView: File size validation failed: \(fileSizeErrorMessage)")
                    return
                }
                
                // Store raw data - FirebaseManager will upload to Storage if needed
                listing.fileData = rawFileData
                listing.fileName = pdfURL.lastPathComponent
                print("CreateListingView: Stored original PDF data for upload (\(rawFileData.count) bytes)")
            } catch {
                print("CreateListingView: Error reading original PDF data: \(error)")
            }
        }
        
        // Store tags (including PDF metadata)
        listing.tags = tags
        
        listingManager.addListing(listing)
        dismiss()
    }
    
    private func handlePDFConversionResults(copiedURL: URL, pageImages: [UIImage], metadata: PDFMetadata?) {
        print("CreateListingView: Processing PDF conversion results for: \(copiedURL.lastPathComponent)")
        
        guard !pageImages.isEmpty else {
            print("CreateListingView: No page images generated from PDF")
            return
        }
        
        if pageImages.count > 1 {
            // Multiple pages - store as image array
            selectedImages = pageImages
            selectedImage = nil
            print("CreateListingView: Stored \(pageImages.count) pages as multiple images")
        } else {
            // Single page - store as single image
            selectedImage = pageImages.first
            selectedImages = []
            print("CreateListingView: Stored single page as single image")
        }
        
        // Store PDF metadata as tags for reference
        if let metadata = metadata {
            let pdfTag = "PDF-\(metadata.pageCount)pages-\(metadata.displaySize)"
            if !tags.contains(pdfTag) {
                tags.append(pdfTag)
            }
            print("CreateListingView: Added PDF metadata tag: \(pdfTag)")
        }
        
        // Keep the original PDF URL for full viewing
        originalFileURL = copiedURL
        selectedFileURL = nil  // Clear temp URL
        
        print("CreateListingView: Successfully processed PDF conversion results, original PDF saved at: \(copiedURL.lastPathComponent)")
    }
}

// MARK: - Edit Listing View
struct EditListingView: View {
    let listing: LocalListing
    @ObservedObject var listingManager: LocalListingManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var summary: String
    @State private var content: String
    @State private var selectedCategory: NewsletterCategory
    @State private var selectedBusinessSubcategory: BusinessSubcategory?
    @State private var selectedAdvertSubcategory: AdvertSubcategory?
    
    // Attachment state
    @State private var imageData: Data?
    @State private var imagesData: [Data]?
    @State private var fileURL: URL?
    @State private var originalFileURL: URL? = nil // Keep original file for PDFs
    @State private var originalPDFURL: URL? = nil // Original PDF for "View Full PDF" button
    @State private var showPDFPreview = false // Sheet for PDF preview
    @State private var showAttachmentSheet = false
    @State private var showAttachmentPicker = false
    @State private var showDocumentPicker = false
    @State private var showPhotosPicker = false
    @State private var attachmentPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImageFromDoc: UIImage? = nil
    
    // File size validation
    @State private var showFileSizeError = false
    @State private var fileSizeErrorMessage = ""
    
    // Contact information state
    @AppStorage("userName") private var registeredFirstName: String = ""
    @AppStorage("userCell") private var registeredPhone: String = ""
    @State private var useRegisteredContact: Bool
    @State private var contactName: String
    @State private var contactPhone: String

    init(listing: LocalListing, listingManager: LocalListingManager) {
        self.listing = listing
        self.listingManager = listingManager
        self._title = State(initialValue: listing.title)
        self._summary = State(initialValue: listing.summary)
        self._content = State(initialValue: listing.content)
        self._selectedCategory = State(initialValue: listing.category)
        self._selectedBusinessSubcategory = State(initialValue: listing.businessSubcategory)
        self._selectedAdvertSubcategory = State(initialValue: listing.advertSubcategory)
        self._imageData = State(initialValue: listing.imageData)
        self._imagesData = State(initialValue: listing.imagesData)
        self._fileURL = State(initialValue: listing.fileURL)
        self._originalFileURL = State(initialValue: listing.fileURL)
        
        // Initialize contact information
        let hasCustomContact = listing.contactName != nil && listing.contactPhone != nil
        self._useRegisteredContact = State(initialValue: !hasCustomContact)
        self._contactName = State(initialValue: listing.contactName ?? "")
        self._contactPhone = State(initialValue: listing.contactPhone ?? "")
    }
    
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false
    
    private var isAdmin: Bool {
        return userIsAdmin || userIsCommittee
    }
    
    private var availableCategories: [NewsletterCategory] {
        return [.localAdverts, .business]
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
                
                Section("Listing Details") {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...3)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                }
                
                // Contact Information Section
                Section("Contact Information") {
                    Toggle("Use my registered contact details", isOn: $useRegisteredContact)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    if useRegisteredContact {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Name:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(registeredFirstName.isEmpty ? "Not set" : registeredFirstName)
                                    .font(.callout)
                            }
                            
                            HStack {
                                Text("Phone:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(registeredPhone.isEmpty ? "Not set" : registeredPhone)
                                    .font(.callout)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 12) {
                            TextField("Contact Name", text: $contactName)
                                .textContentType(.name)
                            
                            TextField("Contact Phone", text: $contactPhone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                        }
                    }
                }

                // Attachment section (add/remove)
                Section("Attachment") {
                    if let images = imagesData, !images.isEmpty {
                        // Show preview of multiple images (including PDF pages)
                        let isPDF = listing.tags.contains { $0.hasPrefix("PDF-") }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                // Show appropriate label for PDF vs. regular images
                                let countText = isPDF ? "\(images.count) page(s)" : "\(images.count) photo(s)"
                                Text(countText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // Show PDF indicator badge
                                if isPDF {
                                    Image(systemName: "doc.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text("Document")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                                
                                // Show PDF metadata
                                if isPDF, let pdfTag = listing.tags.first(where: { $0.hasPrefix("PDF-") }) {
                                    Text(pdfTag.replacingOccurrences(of: "PDF-", with: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(images.indices, id: \.self) { index in
                                        if let img = UIImage(data: images[index]) {
                                            ZStack(alignment: .topTrailing) {
                                                ZStack(alignment: .bottomLeading) {
                                                    Image(uiImage: img)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 100, height: 100)
                                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    
                                                    // Page number indicator for PDFs
                                                    if isPDF && images.count > 1 {
                                                        Text("\(index + 1)")
                                                            .font(.caption)
                                                            .fontWeight(.semibold)
                                                            .foregroundColor(.white)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.black.opacity(0.7))
                                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                                            .padding(4)
                                                    }
                                                }
                                                
                                                Button(action: {
                                                    var mutableImages = images
                                                    mutableImages.remove(at: index)
                                                    imagesData = mutableImages.isEmpty ? nil : mutableImages
                                                    imageData = mutableImages.first
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.white)
                                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                                }
                                                .padding(4)
                                            }
                                        }
                                    }
                                }
                            }
                            Button("Remove All Photos") {
                                imageData = nil
                                imagesData = nil
                            }
                            .foregroundColor(.red)
                        }
                    } else if imageData != nil || fileURL != nil {
                        // Show preview of existing attachment (including single-page PDF)
                        VStack(alignment: .leading, spacing: 8) {
                            if let data = imageData, let image = UIImage(data: data) {
                                HStack {
                                    // Show PDF indicator for single-page PDFs
                                    let isPDF = listing.tags.contains { $0.hasPrefix("PDF-") }
                                    if isPDF {
                                        Image(systemName: "doc.fill")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Text("Document")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .fontWeight(.medium)
                                        
                                        // Show PDF metadata
                                        if let pdfTag = listing.tags.first(where: { $0.hasPrefix("PDF-") }) {
                                            Text("• \(pdfTag.replacingOccurrences(of: "PDF-", with: ""))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 120)
                                    .cornerRadius(8)
                            } else if let url = fileURL {
                                HStack {
                                    Image(systemName: "doc")
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                }
                            }
                            Button("Remove Attachment") {
                                imageData = nil
                                fileURL = nil
                                originalFileURL = nil
                            }
                            .foregroundColor(.red)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        Button(action: { showAttachmentSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperclip")
                                    .font(.body)
                                    .foregroundColor(.accentColor)
                                Text(imageData != nil || fileURL != nil ? "Replace Attachment" : "Attach Image or File")
                                    .font(.callout)
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // "View Full PDF" button if we have original PDF
                        if let pdfURL = originalPDFURL {
                            Button(action: { showPDFPreview = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.body)
                                        .foregroundColor(.blue)
                                    Text("View Full PDF")
                                        .font(.callout)
                                        .foregroundColor(.blue)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                    }
                    .padding(.leading, 4)
                    .padding(.top, -8)
                    .sheet(isPresented: $showPDFPreview) {
                        if let pdfURL = originalPDFURL {
                            NavigationView {
                                QuickLookPreview(url: pdfURL)
                                    .navigationTitle("PDF Preview")
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                        ToolbarItem(placement: .navigationBarTrailing) {
                                            Button("Done") {
                                                showPDFPreview = false
                                            }
                                        }
                                    }
                            }
                        }
                    }
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
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                // Dismiss keyboard when tapping outside text fields
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("Edit Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updateListing()
                    }
                    .disabled(title.isEmpty || summary.isEmpty || content.isEmpty)
                }
            }
            // Attachment pickers
            .sheet(isPresented: $showAttachmentPicker) {
                ImagePicker(image: Binding(
                    get: {
                        if let data = imageData {
                            return UIImage(data: data)
                        }
                        return nil
                    },
                    set: { newImage in
                        if let image = newImage, let compressed = image.compressedForFirestore() {
                            imageData = compressed
                            fileURL = nil
                            originalFileURL = nil
                        }
                    }
                ), sourceType: attachmentPickerSource)
            }
            .sheet(isPresented: $showDocumentPicker) {
                LocalListingDocumentPicker(
                    fileURL: $fileURL, 
                    image: $selectedImageFromDoc,
                    onPDFSelected: { copiedURL, pageImages, metadata in
                        print("EditListingView: PDF conversion completed with \(pageImages.count) images")
                        handlePDFConversionResultsForEdit(copiedURL: copiedURL, pageImages: pageImages, metadata: metadata)
                    }
                )
                    .onChange(of: fileURL) { _, newURL in
                        if let url = newURL {
                            // Only handle non-PDF files here (PDFs are handled by callback)
                            if url.pathExtension.lowercased() != "pdf" {
                                print("EditListingView: Processing non-PDF file: \(url.lastPathComponent)")
                                if let preview = generateImageFromFile(url: url) {
                                    imageData = preview.compressedForFirestore()
                                }
                                fileURL = nil // Don't store file URLs anymore
                                originalFileURL = nil
                                // Don't clear originalPDFURL - might still have original PDF
                            }
                        }
                    }
                    .onChange(of: selectedImageFromDoc) { _, newImage in
                        if let img = newImage, let compressed = img.compressedForFirestore() {
                            imageData = compressed
                            fileURL = nil
                            // Don't clear originalPDFURL - might still have original PDF
                        }
                    }
            }
            .alert("File Size Error", isPresented: $showFileSizeError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(fileSizeErrorMessage)
            }
        }
    }
    
    private func handlePDFConversionResultsForEdit(copiedURL: URL, pageImages: [UIImage], metadata: PDFMetadata?) {
        print("EditListingView: Processing PDF conversion results for: \(copiedURL.lastPathComponent)")
        
        guard !pageImages.isEmpty else {
            print("EditListingView: No page images generated from PDF")
            return
        }
        
        if pageImages.count > 1 {
            // Multiple pages - store as image array
            imagesData = pageImages.compactMap { $0.compressedForPDFPreview() }
            imageData = nil
            print("EditListingView: Stored \(pageImages.count) pages as multiple images")
        } else {
            // Single page - store as single image
            imageData = pageImages.first?.compressedForPDFPreview()
            imagesData = nil
            print("EditListingView: Stored single page as single image")
        }
        
        // Preserve original PDF URL for "View Full PDF" functionality
        originalPDFURL = copiedURL
        fileURL = nil
        originalFileURL = nil
        
        print("EditListingView: Successfully processed PDF conversion results with original PDF preserved")
    }

    private func updateListing() {
        // File size validation for originalPDFURL
        if let pdfURL = originalPDFURL {
            do {
                let rawFileData = try Data(contentsOf: pdfURL)
                if rawFileData.count > 100 * 1024 * 1024 {
                    let fileSizeMB = Double(rawFileData.count) / 1024.0 / 1024.0
                    fileSizeErrorMessage = String(format: "File too large (%.1f MB). Maximum size: 100 MB", fileSizeMB)
                    showFileSizeError = true
                    return
                }
            } catch {
                print("Error reading file for size validation: \(error.localizedDescription)")
            }
        }
        
        var updatedListing = listing
        updatedListing.title = title
        updatedListing.summary = summary
        updatedListing.content = content
        updatedListing.category = selectedCategory
        updatedListing.businessSubcategory = selectedCategory == .business ? selectedBusinessSubcategory : nil
        updatedListing.advertSubcategory = selectedCategory == .localAdverts ? selectedAdvertSubcategory : nil
        
        // Store contact information
        if useRegisteredContact {
            updatedListing.contactName = registeredFirstName
            updatedListing.contactPhone = registeredPhone
        } else {
            updatedListing.contactName = contactName.isEmpty ? nil : contactName
            updatedListing.contactPhone = contactPhone.isEmpty ? nil : contactPhone
        }
        
        // Store images - prioritize multiple images, then single image
        if let images = imagesData, !images.isEmpty {
            updatedListing.imagesData = images
            updatedListing.imageData = images.first
        } else if let data = imageData {
            updatedListing.imageData = data
            updatedListing.imagesData = nil
        } else {
            updatedListing.imageData = nil
            updatedListing.imagesData = nil
        }
        
        // Store original PDF URL if we have one (for hybrid preview/full view system)
        if let pdfURL = originalPDFURL {
            updatedListing.fileURL = pdfURL
            print("EditListingView: Preserved original PDF URL for full viewing: \(pdfURL.lastPathComponent)")
        } else {
            updatedListing.fileURL = nil
        }
        
        listingManager.updateListing(updatedListing)
        dismiss()
    }
}

// MARK: - Listing Archive View
struct ListingArchiveView: View {
    @ObservedObject var listingManager: LocalListingManager
    let isAdmin: Bool
    let allowEveryoneToCreateListings: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: NewsletterCategory? = nil
    @State private var listingToDelete: LocalListing?
    @State private var showDeleteAlert = false
    @State private var selectedListing: LocalListing? = nil
    @State private var showDetailView = false

    var filteredListings: [LocalListing] {
        let filtered = listingManager.listings.filter { listing in
            let matchesSearch = searchText.isEmpty ||
                listing.title.localizedCaseInsensitiveContains(searchText) ||
                listing.summary.localizedCaseInsensitiveContains(searchText) ||
                listing.content.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || listing.category == selectedCategory
            return matchesSearch && matchesCategory && listing.isPublished
        }
        return filtered.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search listings...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()

                // Category filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        FilterChip(
                            title: "Local Adverts",
                            icon: "tag.fill",
                            isSelected: selectedCategory == .localAdverts
                        ) {
                            selectedCategory = .localAdverts
                        }
                        FilterChip(
                            title: "Business",
                            icon: "briefcase.fill",
                            isSelected: selectedCategory == .business
                        ) {
                            selectedCategory = .business
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)

                // Listings list
                if filteredListings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No listings found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        if !searchText.isEmpty {
                            Text("Try adjusting your search")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredListings) { listing in
                            Button(action: {
                                selectedListing = listing
                                showDetailView = true
                            }) {
                                ListingListRow(listing: listing, isAdmin: isAdmin) { action in
                                    handleListingAction(action, for: listing)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Local Listings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showDetailView) {
            if let listing = selectedListing {
                ListingDetailView(listing: listing, listingManager: listingManager)
            }
        }
        .alert("Delete Listing", isPresented: $showDeleteAlert, presenting: listingToDelete) { listing in
            Button("Delete", role: .destructive) {
                listingManager.deleteListing(listing)
            }
            Button("Cancel", role: .cancel) {}
        } message: { listing in
            Text("Are you sure you want to delete '\(listing.title)'?")
        }
    }

    private func handleListingAction(_ action: ListingAction, for listing: LocalListing) {
        switch action {
        case .delete:
            listingToDelete = listing
            showDeleteAlert = true
        }
    }
}

enum ListingAction {
    case delete
}

// MARK: - Listing List Row
struct ListingListRow: View {
    let listing: LocalListing
    let isAdmin: Bool
    let onAction: (ListingAction) -> Void
    @ObservedObject private var imageCache = ListingImageCache.shared
    @AppStorage("userEmail") private var userEmail: String = ""
    @AppStorage("userUID") private var userUID: String = ""
    
    private var isOwner: Bool {
        // Use Firebase UID for ownership check (primary method)
        if let authorUID = listing.authorUID, !authorUID.isEmpty, !userUID.isEmpty {
            return authorUID == userUID
        }
        // Fallback to email comparison for legacy listings without UID
        return listing.authorEmail.lowercased() == userEmail.lowercased()
    }
    
    private var canDelete: Bool {
        return isOwner || isAdmin
    }

    var body: some View {
        HStack(spacing: 12) {
            if let cachedImage = imageCache.getImage(for: listing) {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if imageCache.hasAttachment(for: listing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay(ProgressView().scaleEffect(0.7))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: listing.category.icon)
                            .font(.caption2)
                            .foregroundColor(listing.category.color)
                        Text(listing.category.rawValue)
                            .font(.caption2)
                            .foregroundColor(listing.category.color)
                        
                        if let businessSubcategory = listing.businessSubcategory {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Image(systemName: businessSubcategory.icon)
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(businessSubcategory.rawValue)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else if let advertSubcategory = listing.advertSubcategory {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Image(systemName: advertSubcategory.icon)
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(advertSubcategory.rawValue)
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            // Show SOLD badge for For Sale items
                            if advertSubcategory == .forSale && listing.isSold == true {
                                Text("• SOLD")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    Spacer()
                }

                Text(listing.title)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(2)

                Text(listing.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Text(listing.date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if canDelete {
                Menu {
                    Button(role: .destructive, action: { onAction(.delete) }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            ListingImageCache.shared.preloadImage(for: listing)
        }
    }
}

// MARK: - Document Picker for Local Listings
struct LocalListingDocumentPicker: UIViewControllerRepresentable {
    @Binding var fileURL: URL?
    @Binding var image: UIImage?
    var onPDFSelected: ((URL, [UIImage], PDFMetadata?) -> Void)? = nil
    var onFileSelected: ((Data, String) -> Void)? = nil  // New callback for direct file data
    var subdirectory: String = "LocalListings"  // Allow customization, default to LocalListings

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
        let parent: LocalListingDocumentPicker

        init(_ parent: LocalListingDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
        ) {
            print("LocalListingDocumentPicker: Document picked from URLs: \(urls)")
            guard let src = urls.first else {
                print("LocalListingDocumentPicker: No URL selected")
                parent.fileURL = nil
                parent.image = nil
                return
            }
            print("LocalListingDocumentPicker: Processing file: \(src.lastPathComponent)")

            // Use centralized DocumentStorageManager for file storage
            guard let copiedURL = DocumentStorageManager.shared.storeDocument(from: src, subdirectory: parent.subdirectory) else {
                print("LocalListingDocumentPicker: Failed to store document to \(parent.subdirectory)")
                parent.fileURL = nil
                parent.image = nil
                return
            }
            
            parent.fileURL = copiedURL
            
            print("LocalListingDocumentPicker: Successfully set fileURL: \(copiedURL)")
            print("LocalListingDocumentPicker: File extension: \(copiedURL.pathExtension.lowercased())")
            
            // Handle PDF conversion (matches newsletters pattern)
            if copiedURL.pathExtension.lowercased() == "pdf" {
                print("LocalListingDocumentPicker: Converting PDF using local file methods")
                
                // Convert PDF using the copied file (no security scoped access needed)
                let pageImages = PDFToImageConverter.convertLocalPDFToPageImages(copiedURL)
                let metadata = PDFToImageConverter.extractLocalPDFMetadata(copiedURL)
                
                if !pageImages.isEmpty {
                    print("LocalListingDocumentPicker: Successfully converted PDF to \(pageImages.count) images")
                    parent.onPDFSelected?(copiedURL, pageImages, metadata)
                } else {
                    print("LocalListingDocumentPicker: Failed to convert PDF")
                    parent.onPDFSelected?(copiedURL, [], nil)
                }
            } else {
                print("LocalListingDocumentPicker: Non-PDF file selected")
                // Pass file data for non-PDF files if callback exists
                if let fileData = try? Data(contentsOf: copiedURL) {
                    parent.onFileSelected?(fileData, copiedURL.lastPathComponent)
                }
            }

            // Handle non-PDF images after storage
            if copiedURL.pathExtension.lowercased() != "pdf" {
                if let data = try? Data(contentsOf: copiedURL), let uiimg = UIImage(data: data) {
                    parent.image = uiimg
                    parent.fileURL = nil
                    return
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.fileURL = nil
        }
    }
}


// MARK: - PDF Viewer
struct PDFViewer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        // Load PDF document with better error handling for remote URLs
        loadPDFDocument(into: pdfView, from: url)
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil {
            loadPDFDocument(into: pdfView, from: url)
        }
    }
    
    private func loadPDFDocument(into pdfView: PDFView, from url: URL) {
        if url.scheme?.hasPrefix("http") == true {
            // Handle remote URLs (Firebase Storage) by downloading data first
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    print("PDFViewer: Error loading remote PDF: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data, let document = PDFDocument(data: data) else {
                    print("PDFViewer: Failed to create PDF document from downloaded data")
                    return
                }
                
                DispatchQueue.main.async {
                    pdfView.document = document
                }
            }.resume()
        } else {
            // Handle local file URLs directly
            if let document = PDFDocument(url: url) {
                pdfView.document = document
            } else {
                print("PDFViewer: Failed to load local PDF from: \(url)")
            }
        }
    }
}

// MARK: - QuickLook Preview Components

// QuickLook preview wrapper for documents
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // Reload data when download completes
        if context.coordinator.downloadCompleted && context.coordinator.localURL != nil {
            uiViewController.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let originalURL: URL
        var localURL: URL?
        var isDownloading = false
        var downloadCompleted = false
        var hasShownError = false
        
        init(url: URL) { 
            self.originalURL = url 
            super.init()
            print("QuickLookPreview: Initialized with URL: \(url)")
            
            // If it's a Firebase Storage URL (HTTPS), download it locally for QuickLook compatibility
            if url.scheme == "https" && url.host?.contains("firebasestorage.googleapis.com") == true {
                downloadForLocalPreview()
            } else {
                // For local files, mark as completed immediately
                downloadCompleted = true
            }
        }
        
        private func downloadForLocalPreview() {
            guard !isDownloading else { return }
            isDownloading = true
            
            print("QuickLookPreview: Downloading Firebase Storage file for local preview")
            
            // Use persistent cache directory instead of temporary directory
            guard let persistentCacheDir = getPersistentCacheDirectory() else {
                print("QuickLookPreview: Failed to create persistent cache directory")
                hasShownError = true
                isDownloading = false
                return
            }
            
            // Check if file already exists in cache
            let cachedFile = getCachedFilePath(for: originalURL, in: persistentCacheDir)
            if FileManager.default.fileExists(atPath: cachedFile.path) {
                print("QuickLookPreview: Using cached file: \(cachedFile)")
                localURL = cachedFile
                downloadCompleted = true
                isDownloading = false
                
                // Notify QuickLook to refresh
                if let controller = currentController {
                    controller.reloadData()
                }
                return
            }
            
            // Add timeout and better error handling
            var request = URLRequest(url: originalURL)
            request.timeoutInterval = 60.0 // Increased timeout for larger files
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isDownloading = false
                    
                    if let error = error {
                        print("QuickLookPreview: Error downloading file: \(error.localizedDescription)")
                        self.hasShownError = true
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("QuickLookPreview: Invalid response type")
                        self.hasShownError = true
                        return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        print("QuickLookPreview: HTTP error \(httpResponse.statusCode)")
                        self.hasShownError = true
                        return
                    }
                    
                    guard let data = data else {
                        print("QuickLookPreview: No data received")
                        self.hasShownError = true
                        return
                    }
                    
                    // Increased file size limit to 100MB for documents
                    if data.count > 100 * 1024 * 1024 {
                        print("QuickLookPreview: File too large (\(data.count) bytes, max 100MB)")
                        self.hasShownError = true
                        return
                    }
                    
                    // Save to persistent cache
                    let cacheFile = cachedFile
                    
                    do {
                        // Remove existing temp file if it exists
                        try? FileManager.default.removeItem(at: cacheFile)
                        try data.write(to: cacheFile)
                        self.localURL = cacheFile
                        self.downloadCompleted = true
                        print("QuickLookPreview: Successfully cached file: \(cacheFile)")
                        print("QuickLookPreview: File size: \(data.count) bytes, MIME: \(httpResponse.mimeType ?? "unknown")")
                        
                        // Clean up old cache files to manage storage
                        self.cleanupOldCacheFiles(in: persistentCacheDir)
                        
                        // Notify QuickLook to refresh
                        if let controller = self.currentController {
                            controller.reloadData()
                        }
                    } catch {
                        print("QuickLookPreview: Error writing cache file: \(error.localizedDescription)")
                        self.hasShownError = true
                    }
                }
            }.resume()
        }
        
        // Get persistent cache directory for document previews
        private func getPersistentCacheDirectory() -> URL? {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            
            let cacheDir = appSupport.appendingPathComponent("DocumentCache")
            
            do {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                return cacheDir
            } catch {
                print("QuickLookPreview: Failed to create cache directory: \(error)")
                return nil
            }
        }
        
        // Generate consistent cache file path for a URL
        private func getCachedFilePath(for url: URL, in cacheDir: URL) -> URL {
            // Create a hash of the URL to generate a unique filename
            let urlString = url.absoluteString
            let hash = urlString.data(using: .utf8)?.base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
                .prefix(32) ?? "unknown"
            
            // Extract file extension from original URL
            let pathExtension = getFileExtension(for: url)
            let fileName = "\(hash).\(pathExtension)"
            
            return cacheDir.appendingPathComponent(fileName)
        }
        
        // Extract file extension from Firebase Storage URL
        private func getFileExtension(for url: URL) -> String {
            let urlPath = url.path
            let urlComponents = urlPath.components(separatedBy: "/")
            
            // Look for filename with extension in the path components
            for component in urlComponents.reversed() {
                let decoded = component.removingPercentEncoding ?? component
                if decoded.contains(".") && !decoded.isEmpty {
                    let components = decoded.components(separatedBy: ".")
                    if let ext = components.last, !ext.isEmpty {
                        return ext.lowercased()
                    }
                }
            }
            
            // Default to pdf for unknown extensions
            return "pdf"
        }
        
        // Clean up old cache files to prevent unlimited storage growth
        private func cleanupOldCacheFiles(in cacheDir: URL) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey])
                let sortedFiles = files.sorted { file1, file2 in
                    let date1 = (try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let date2 = (try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return date1 > date2
                }
                
                // Keep only the 50 most recent files
                if sortedFiles.count > 50 {
                    let filesToDelete = Array(sortedFiles.dropFirst(50))
                    for file in filesToDelete {
                        try? FileManager.default.removeItem(at: file)
                        print("QuickLookPreview: Cleaned up old cache file: \(file.lastPathComponent)")
                    }
                }
            } catch {
                print("QuickLookPreview: Error during cache cleanup: \(error)")
            }
        }
        
        // Keep reference to controller for reloading
        weak var currentController: QLPreviewController?
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            currentController = controller
            print("QuickLookPreview: numberOfPreviewItems requested, downloadCompleted: \(downloadCompleted)")
            
            // For local files, always return 1
            if originalURL.isFileURL {
                return 1
            }
            
            // For remote files, only return 1 if download is complete and we have a local file
            if downloadCompleted && localURL != nil {
                return 1
            }
            
            // If there's an error or still downloading, return 0 to prevent QuickLook from trying to access
            return 0
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            print("QuickLookPreview: previewItemAt \(index) requested")
            
            // For local files, verify existence first
            if originalURL.isFileURL {
                let fileExists = FileManager.default.fileExists(atPath: originalURL.path)
                print("QuickLookPreview: Using local file URL: \(originalURL)")
                print("QuickLookPreview: File exists at path: \(fileExists)")
                
                if !fileExists {
                    print("QuickLookPreview: ERROR - File does not exist at: \(originalURL.path)")
                    // Try to find the file in the Documents directory by checking alternate paths
                    if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        print("QuickLookPreview: Documents directory: \(documentsDir.path)")
                        let expectedPath = documentsDir.appendingPathComponent("AppDocuments/Newsletters/\(originalURL.lastPathComponent)")
                        if FileManager.default.fileExists(atPath: expectedPath.path) {
                            print("QuickLookPreview: Found file at alternate path: \(expectedPath.path)")
                            return PreviewItem(url: expectedPath, title: expectedPath.lastPathComponent)
                        }
                    }
                }
                
                return PreviewItem(url: originalURL, title: originalURL.lastPathComponent)
            }
            
            // For remote files, only use local URL if download is complete
            if downloadCompleted, let localURL = localURL {
                print("QuickLookPreview: Using downloaded local file: \(localURL)")
                return PreviewItem(url: localURL, title: localURL.lastPathComponent)
            }
            
            // This shouldn't be reached if numberOfPreviewItems is working correctly
            print("QuickLookPreview: ERROR - previewItemAt called but download not complete")
            return PreviewItem(url: originalURL, title: "Loading...")
        }
        
        func previewControllerWillDismiss(_ controller: QLPreviewController) {
            print("QuickLookPreview: Will dismiss")
            // Don't clean up persistent cache files on dismiss - they should persist across app launches
            // Only clean up if this was a temporary file (not in persistent cache)
            if let localURL = localURL, localURL.path.contains("tmp") {
                try? FileManager.default.removeItem(at: localURL)
                print("QuickLookPreview: Cleaned up temporary file")
            } else {
                print("QuickLookPreview: Keeping persistent cache file for future use")
            }
        }
        
        func previewController(_ controller: QLPreviewController, shouldOpen url: URL, for item: QLPreviewItem) -> Bool {
            print("QuickLookPreview: Should open URL: \(url)")
            return true
        }
        
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            print("QuickLookPreview: Did dismiss")
        }
    }
    
    // Custom preview item class for better control
    private class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?
        
        init(url: URL, title: String) {
            self.previewItemURL = url
            self.previewItemTitle = title
            super.init()
        }
    }
}

// Enhanced preview specifically for Firebase Storage URLs
struct EnhancedFirebaseStoragePreview: View {
    let url: URL
    @State private var showingQuickLook = true
    @State private var showingWebView = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading document preview...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .lineLimit(1)
                }
                .padding()
                .onAppear {
                    // Test URL accessibility first
                    testURLAccessibility()
                }
            } else if showingQuickLook {
                QuickLookPreview(url: url)
            } else if showingWebView {
                VStack {
                    Text("Web Preview")
                        .font(.caption)
                        .padding(.top)
                    FirebaseStorageWebPreview(url: url)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    
                    Text("Document Preview")
                        .font(.headline)
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 12) {
                        Button("Try QuickLook Preview") {
                            showingQuickLook = true
                            showingWebView = false
                            isLoading = false
                        }
                        
                        Button("Try Web Preview") {
                            showingWebView = true
                            showingQuickLook = false
                            isLoading = false
                        }
                        
                        Button("Open in Safari") {
                            UIApplication.shared.open(url)
                        }
                        .foregroundColor(.accentColor)
                    }
                }
                .padding()
            }
        }
    }
    
    private func testURLAccessibility() {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    self.showingQuickLook = false
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        self.errorMessage = "HTTP \(httpResponse.statusCode): Unable to access document"
                        self.showingQuickLook = false
                    }
                    // If 200, QuickLook should work
                }
            }
        }.resume()
    }
}

struct FirebaseStorageWebPreview: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.backgroundColor = UIColor.systemBackground
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard uiView.url != url else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        uiView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("FirebaseStorageWebPreview: Starting to load document")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("FirebaseStorageWebPreview: Failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("FirebaseStorageWebPreview: Successfully loaded document")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("FirebaseStorageWebPreview: Navigation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Local Listing File Preview Component (matches Newsletter pattern)
struct LocalListingFilePreview: View {
    let listing: LocalListing
    @State private var downloadedFileURL: URL? = nil
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadError: String? = nil
    
    var body: some View {
        Group {
            if let fileURL = downloadedFileURL {
                QuickLookPreview(url: fileURL)
            } else if let error = downloadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Unable to Load Document")
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
                VStack(spacing: 16) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 40)
                    
                    if isDownloading {
                        Text("Downloading document...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Preparing document...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            print("📱 LocalListingFilePreview: View appeared for listing: \(listing.title)")
            print("   - Has fileName: \(listing.fileName != nil)")
            print("   - Has fileData: \(listing.fileData != nil)")
            prepareFile()
            
            // Listen for download completion notification
            NotificationCenter.default.addObserver(forName: NSNotification.Name("LocalListingFileDownloaded"), object: nil, queue: .main) { notification in
                if let listingId = notification.userInfo?["listingId"] as? String,
                   listingId == listing.id.uuidString {
                    print("📥 LocalListingFilePreview: Received download completion notification")
                    prepareFile()
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("LocalListingFileDownloaded"), object: nil)
        }
    }
    
    private func prepareFile() {
        print("🔍 LocalListingFilePreview: prepareFile() called")
        downloadError = nil
        
        // Check if we already have a fileURL (cached or from Firestore data)
        if let fileURL = listing.fileURL {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                self.downloadedFileURL = fileURL
                print("✅ LocalListingFilePreview: Using existing file at: \(fileURL.path)")
                return
            }
        }
        
        // If we have fileData, create temp file from it
        if let fileData = listing.fileData, let fileName = listing.fileName {
            createTempFileFromData(fileData, fileName: fileName)
            return
        }
        
        // If we have a fileName but no fileURL, file is downloading from Storage
        if let fileName = listing.fileName {
            print("⏳ LocalListingFilePreview: File is downloading from Storage, monitoring progress...")
            isDownloading = true
            monitorFileDownload(fileName: fileName)
        } else {
            downloadError = "No attachment available"
        }
    }
    
    private func createTempFileFromData(_ data: Data, fileName: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("locallisting_\(listing.id.uuidString)_\(fileName)")
        
        do {
            try data.write(to: tempFile)
            self.downloadedFileURL = tempFile
            print("✅ LocalListingFilePreview: Created temp file from data: \(tempFile.path)")
        } catch {
            self.downloadError = "Could not create temporary file: \(error.localizedDescription)"
            print("❌ LocalListingFilePreview: Error creating temp file: \(error)")
        }
    }
    
    private func monitorFileDownload(fileName: String) {
        // Calculate expected cache path
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let expectedPath = cacheDir.appendingPathComponent("localListings/\(listing.id.uuidString)/\(fileName)")
        
        print("📥 LocalListingFilePreview: Monitoring for file at: \(expectedPath.path)")
        
        // Poll for file existence (Firebase Storage download is async)
        var attempts = 0
        let maxAttempts = 60 // 30 seconds max wait
        
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            attempts += 1
            
            if FileManager.default.fileExists(atPath: expectedPath.path) {
                timer.invalidate()
                self.downloadedFileURL = expectedPath
                self.isDownloading = false
                print("✅ LocalListingFilePreview: File download completed: \(expectedPath.path)")
            } else if attempts >= maxAttempts {
                timer.invalidate()
                self.isDownloading = false
                self.downloadError = "Download timed out. Please check your internet connection and try again."
                print("❌ LocalListingFilePreview: Download timed out after \(maxAttempts/2) seconds")
            } else {
                self.downloadProgress = Double(attempts) / Double(maxAttempts)
            }
        }
    }
}
