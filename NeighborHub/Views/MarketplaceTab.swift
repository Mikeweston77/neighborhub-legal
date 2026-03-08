import Combine
// MARK: - MarketplaceTab (Main UI)
import SwiftUI
import UIKit

// MARK: - MarketplaceItem Model
struct MarketplaceItem: Identifiable, Equatable {
    let id: UUID
    let owner: String
    var title: String
    var description: String
    var price: Double
    var category: String
    var condition: ItemCondition
    // Consolidated image handling - use computed properties for access
    private var _primaryImageURL: String?
    private var _additionalImageURLs: [String]
    var date: Date
    var contact: String
    var isSold: Bool
    var soldDate: Date?  // when it was marked sold (for auto-delete)
    var isNegotiable: Bool
    var tags: [String]
    var location: String  // Neighborhood location
    var sustainabilityScore: Int
    var isEmergency: Bool
    var pickupOptions: [PickupOption]

    // MARK: - Image Management

    /// Primary image - loads from cache or memory
    var image: UIImage? {
        get {
            let cached = UIImage.cachedMarketplace(itemId: id, imageType: "primary")
            print("[MarketplaceItem] GET image for \(id): \(cached != nil ? "FOUND" : "NOT FOUND")")
            return cached
        }
        set {
            if let newImage = newValue {
                print("[MarketplaceItem] SET image for \(id): caching image")
                newImage.cacheForMarketplace(itemId: id, imageType: "primary")
            } else {
                print("[MarketplaceItem] REMOVE image for \(id)")
                ImageCacheManager.shared.removeCachedMarketplaceImages(itemId: id)
            }
        }
    }

    /// Additional images - loads from cache
    var additionalImages: [UIImage] {
        get {
            var images: [UIImage] = []
            for index in 0..<10 {  // Support up to 10 additional images
                if let cachedImage = UIImage.cachedMarketplace(
                    itemId: id, imageType: "additional_\(index)")
                {
                    images.append(cachedImage)
                } else {
                    break  // Stop at first missing image to maintain order
                }
            }
            return images
        }
        set {
            // Simply cache the new images - the getter will load them in correct order
            for (index, image) in newValue.enumerated() {
                image.cacheForMarketplace(itemId: id, imageType: "additional_\(index)")
            }
        }
    }

    /// Remote image URLs (for Firebase sync)
    var imageURL: String? {
        get { _primaryImageURL }
        set { _primaryImageURL = newValue }
    }

    var additionalImageURLs: [String] {
        get { _additionalImageURLs }
        set { _additionalImageURLs = newValue }
    }

    /// Check if item has any images (cached or remote)
    var hasImages: Bool {
        return image != nil || !additionalImages.isEmpty || imageURL != nil
            || !additionalImageURLs.isEmpty
    }

    /// Get all available images (primary + additional)
    var allImages: [UIImage] {
        var images: [UIImage] = []
        if let primaryImage = image {
            images.append(primaryImage)
        }
        images.append(contentsOf: additionalImages)
        return images
    }

    // MARK: - Initializers

    init(
        id: UUID = UUID(), owner: String, title: String, description: String, price: Double,
        category: String, condition: ItemCondition, date: Date = Date(), contact: String,
        isSold: Bool = false, soldDate: Date? = nil, isNegotiable: Bool = false,
        tags: [String] = [], location: String, sustainabilityScore: Int = 0,
        isEmergency: Bool = false, pickupOptions: [PickupOption] = [.pickup],
        imageURL: String? = nil, additionalImageURLs: [String] = []
    ) {
        self.id = id
        self.owner = owner
        self.title = title
        self.description = description
        self.price = price
        self.category = category
        self.condition = condition
        self._primaryImageURL = imageURL
        self._additionalImageURLs = additionalImageURLs
        self.date = date
        self.contact = contact
        self.isSold = isSold
        self.soldDate = soldDate
        self.isNegotiable = isNegotiable
        self.tags = tags
        self.location = location
        self.sustainabilityScore = sustainabilityScore
        self.isEmergency = isEmergency
        self.pickupOptions = pickupOptions
    }

    static func == (lhs: MarketplaceItem, rhs: MarketplaceItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.description == rhs.description
            && lhs.price == rhs.price && lhs.category == rhs.category
            && lhs.condition == rhs.condition && lhs.isSold == rhs.isSold
            && lhs.isNegotiable == rhs.isNegotiable && lhs.tags == rhs.tags
            && lhs.location == rhs.location && lhs.sustainabilityScore == rhs.sustainabilityScore
            && lhs.isEmergency == rhs.isEmergency && lhs.pickupOptions == rhs.pickupOptions
            && lhs.contact == rhs.contact && lhs.imageURL == rhs.imageURL
            && lhs.additionalImageURLs == rhs.additionalImageURLs
    }
}


// to avoid duplicate symbol definitions. See `NeighborHub/Models/Advert.swift` and `NeighborHub/Views/*`.

enum ItemCondition: String, CaseIterable, Codable {
    case brandNew = "Brand New"
    case likeNew = "Like New"
    case good = "Good"
    case fair = "Fair"
    case forParts = "For Parts"

    var icon: String {
        switch self {
        case .brandNew: return "sparkles"
        case .likeNew: return "star.fill"
        case .good: return "star"
        case .fair: return "star.leadinghalf.filled"
        case .forParts: return "wrench.and.screwdriver"
        }
    }

    var color: Color {
        switch self {
        case .brandNew: return .green
        case .likeNew: return .blue
        case .good: return .orange
        case .fair: return .yellow
        case .forParts: return .red
        }
    }
}

enum PickupOption: String, CaseIterable, Codable {
    case delivery = "Delivery Available"
    case pickup = "Pickup Only"
    case meetHalfway = "Meet Halfway"
    case flexible = "Flexible"

    var icon: String {
        switch self {
        case .delivery: return "truck.box"
        case .pickup: return "house"
        case .meetHalfway: return "location"
        case .flexible: return "arrow.triangle.swap"
        }
    }
}

// Codable version for persistence (with images)
struct CodableMarketplaceItem: Codable, Identifiable, Equatable {
    let id: UUID
    let owner: String
    var title: String
    var description: String
    var price: Double
    var category: String
    var condition: ItemCondition
    var date: Date
    var contact: String
    var isSold: Bool
    var isNegotiable: Bool
    var tags: [String]
    var location: String
    var pickupOptions: [PickupOption]
    var soldDate: Date?

    // Consolidated image handling - store only URLs for remote sync
    var imageURL: String?
    var additionalImageURLs: [String]

    init(from item: MarketplaceItem) {
        self.id = item.id
        self.owner = item.owner
        self.title = item.title
        self.description = item.description
        self.price = item.price
        self.category = item.category
        self.condition = item.condition
        self.date = item.date
        self.contact = item.contact
        self.isSold = item.isSold
        self.isNegotiable = item.isNegotiable
        self.tags = item.tags
        self.location = item.location
        self.pickupOptions = item.pickupOptions
        self.soldDate = item.soldDate

        // Use URLs for remote sync, images are cached locally
        self.imageURL = item.imageURL
        self.additionalImageURLs = item.additionalImageURLs
    }

    func toMarketplaceItem() -> MarketplaceItem {
        return MarketplaceItem(
            id: id,
            owner: owner,
            title: title,
            description: description,
            price: price,
            category: category,
            condition: condition,
            date: date,
            contact: contact,
            isSold: isSold,
            soldDate: soldDate,
            isNegotiable: isNegotiable,
            tags: tags,
            location: location,
            sustainabilityScore: 0,
            isEmergency: false,
            pickupOptions: pickupOptions,
            imageURL: imageURL,
            additionalImageURLs: additionalImageURLs
        )
    }
}

// Persistence helpers are defined below (MarketplaceItemData struct further in file)

// MARK: - MarketplaceItemData (for persistence)
struct MarketplaceItemData: Codable {
    let id: UUID
    let owner: String
    var title: String
    var description: String
    var price: Double
    var category: String
    var condition: String
    var date: Date
    var contact: String
    var isSold: Bool
    var soldDate: Date?
    var isNegotiable: Bool
    var tags: [String]
    var location: String
    var sustainabilityScore: Int
    var isEmergency: Bool
    var pickupOptions: [String]
    // Consolidated image handling - only store URLs for persistence
    var imageURL: String?
    var additionalImageURLs: [String]

    init(from item: MarketplaceItem) {
        self.id = item.id
        self.owner = item.owner
        self.title = item.title
        self.description = item.description
        self.price = item.price
        self.category = item.category
        self.condition = item.condition.rawValue
        self.date = item.date
        self.contact = item.contact
        self.isSold = item.isSold
        self.soldDate = item.soldDate
        self.isNegotiable = item.isNegotiable
        self.tags = item.tags
        self.location = item.location
        self.sustainabilityScore = item.sustainabilityScore
        self.isEmergency = item.isEmergency
        self.pickupOptions = item.pickupOptions.map { $0.rawValue }
        self.imageURL = item.imageURL
        self.additionalImageURLs = item.additionalImageURLs
    }

    func toMarketplaceItem() -> MarketplaceItem {
        return MarketplaceItem(
            id: id,
            owner: owner,
            title: title,
            description: description,
            price: price,
            category: category,
            condition: ItemCondition(rawValue: condition) ?? .good,
            date: date,
            contact: contact,
            isSold: isSold,
            soldDate: soldDate,
            isNegotiable: isNegotiable,
            tags: tags,
            location: location,
            sustainabilityScore: sustainabilityScore,
            isEmergency: isEmergency,
            pickupOptions: pickupOptions.compactMap { PickupOption(rawValue: $0) },
            imageURL: imageURL,
            additionalImageURLs: additionalImageURLs
        )
    }
}

struct MarketplaceTab: View {
    // MARK: - Animation Constants
    private enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let spring = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
        static let loading = SwiftUI.Animation.easeInOut(duration: 0.8).repeatForever(
            autoreverses: true)
    }

    // MARK: - State Properties
    @AppStorage("notifyMarketplace") private var notifyMarketplace: Bool = true
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("committeeMembers") private var committeeMembers: String = ""
    @AppStorage("marketplaceData") private var marketplaceData: String = ""
    @AppStorage("userCell") private var userCell: String = ""
    @AppStorage("wishlistItems") private var wishlistData: String = ""
    @AppStorage("userNeighborhood") private var userNeighborhood: String = "Your Neighborhood"

    @State private var items: [MarketplaceItem] = []
    @State private var wishlistItemIDs: Set<UUID> = []
    @State private var showAddSheet = false

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    private let searchSubject = PassthroughSubject<String, Never>()
    @State private var searchCancellable: AnyCancellable?
    @State private var selectedCategory: String = "All"
    @State private var selectedCondition: ItemCondition? = nil
    @State private var selectedItem: MarketplaceItem? = nil
    @State private var editingItem: MarketplaceItem? = nil
    @State private var showFilters = false
    @State private var priceRange: ClosedRange<Double> = 0...Double.greatestFiniteMagnitude
    @State private var showWishlist = false
    @State private var sortBy: SortOption = .newest
    // Upload progress & errors keyed by item id -> attachment key
    // Example attachment keys: "image", "additional_0", "additional_1"
    @State private var uploadProgress: [String: [String: Double]] = [:]
    @State private var uploadErrors: [String: [String: String]] = [:]

    // Pagination state
    @State private var currentPage = 0
    @State private var pageSize = 20
    @State private var isLoadingMore = false
    @State private var hasMoreItems = true
    @State private var isAnimating = false  // For loading state animations
    @State private var filterAnimationTrigger = false  // Trigger filter animation

    private let categories = [
        "All", "Electronics", "Home & Garden", "Clothing & Accessories", "Toys & Games",
        "Sports & Recreation", "Books & Media", "Tools & Hardware", "Furniture",
        "Kitchen & Appliances", "Beauty & Health", "Services", "Other",
    ]

    enum SortOption: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case priceLowToHigh = "Price: Low to High"
        case priceHighToLow = "Price: High to Low"
    }

    // Adaptive grid columns for responsive layout
    private var adaptiveColumns: [GridItem] {
        let screenWidth = UIScreen.main.bounds.width
        if screenWidth < 600 {
            return [GridItem(.flexible()), GridItem(.flexible())] // Two cards side by side for small screens
        } else {
            return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())] // Three cards side by side for larger screens
        }
    }

    // Helper: is current user the creator/owner of a marketplace item?
    private func isOwner(_ item: MarketplaceItem) -> Bool {
        // Try to split the stored owner string into first and surname like EventsView does.
        let comps = item.owner.split(separator: " ").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }
        let userFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let userSurnameVal = userSurname.trimmingCharacters(in: .whitespacesAndNewlines).capitalized

        if comps.count >= 2 {
            // If owner contains both first and surname, require both to match (strict match like EventsView)
            let ownerFirst = comps[0]
            let ownerSurname = comps[1]
            return ownerFirst == userFirst && ownerSurname == userSurnameVal
        } else {
            // Fallback: compare single-name owner to the stored user first name
            return comps.first == userFirst
        }
    }

    private func canManageItem(_ item: MarketplaceItem) -> Bool {
        return isOwner(item) || isAdmin
    }
    
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

    private var filteredAndSortedItems: [MarketplaceItem] {
        var filtered = items.filter { item in
            let categoryMatch = selectedCategory == "All" || item.category == selectedCategory
            let conditionMatch = selectedCondition == nil || item.condition == selectedCondition
            let priceMatch =
                item.price >= priceRange.lowerBound && item.price <= priceRange.upperBound
            let searchMatch =
                debouncedSearchText.isEmpty
                || item.title.localizedCaseInsensitiveContains(debouncedSearchText)
                || item.description.localizedCaseInsensitiveContains(debouncedSearchText)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(debouncedSearchText) }

            return categoryMatch && conditionMatch && priceMatch && searchMatch
        }

        // Sort the filtered items
        switch sortBy {
        case .newest:
            filtered.sort { $0.date > $1.date }
        case .oldest:
            filtered.sort { $0.date < $1.date }
        case .priceLowToHigh:
            filtered.sort { $0.price < $1.price }
        case .priceHighToLow:
            filtered.sort { $0.price > $1.price }
        }

        return filtered
    }

    private var paginatedItems: [MarketplaceItem] {
        let endIndex = min((currentPage + 1) * pageSize, filteredAndSortedItems.count)
        return Array(filteredAndSortedItems.prefix(endIndex))
    }

    private var shouldShowLoadMore: Bool {
        let endIndex = min((currentPage + 1) * pageSize, filteredAndSortedItems.count)
        return endIndex < filteredAndSortedItems.count
    }

    private var wishlistItems: [MarketplaceItem] {
        items.filter { wishlistItemIDs.contains($0.id) }
    }

    @Environment(\.colorScheme) private var colorScheme
    private var marketplaceBackground: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }

    // MARK: - Persistence Helpers
    private func saveItems() {
        // Avoid storing binary image data in UserDefaults/AppStorage (this can exceed platform limits).
        // Store metadata only by stripping image bytes before encoding.
        let codableItems = items.map { CodableMarketplaceItem(from: $0) }
        // Remove image bytes to keep the stored payload small and cache images on disk
        // Cache images to disk for better memory management
        for item in items {
            if let image = item.image {
                image.cacheForMarketplace(itemId: item.id, imageType: "primary")
            }

            for (index, additionalImage) in item.additionalImages.enumerated() {
                additionalImage.cacheForMarketplace(
                    itemId: item.id, imageType: "additional_\(index)")
            }
        }
        if let data = try? JSONEncoder().encode(codableItems),
            let str = String(data: data, encoding: .utf8)
        {
            marketplaceData = str
        }
    }

    private func loadItems() {
        guard let data = marketplaceData.data(using: .utf8),
            let codableItems = try? JSONDecoder().decode([CodableMarketplaceItem].self, from: data)
        else {
            items = []
            return
        }

        // Convert to MarketplaceItems without triggering computed property setters
        items = codableItems.map { codableItem in
            return codableItem.toMarketplaceItem()
        }

        // Remove sold items older than retention period
        autoCleanupSoldItems()
    }

    private func setupSearchDebouncing() {
        searchCancellable?.cancel()
        searchCancellable =
            searchSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { value in
                debouncedSearchText = value
            }
    }

    private func refreshMarketplace() async {
        await withCheckedContinuation { continuation in
            // Simulate network refresh - in a real app, this would fetch from server
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                loadItems()
                continuation.resume()
            }
        }
    }

    private func loadMoreItems() {
        guard shouldShowLoadMore && !isLoadingMore else { return }

        withAnimation(Animation.standard) {
            isLoadingMore = true
        }

        // Simulate network delay for loading more items
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(Animation.spring) {
                currentPage += 1
                isLoadingMore = false

                // Update hasMoreItems based on new page
                let endIndex = min((currentPage + 1) * pageSize, filteredAndSortedItems.count)
                hasMoreItems = endIndex < filteredAndSortedItems.count
            }
        }
    }

    private func resetPagination() {
        currentPage = 0
        hasMoreItems = true
    }

    // Remove sold items older than `soldRetentionDays` (default 2 days)
    private func autoCleanupSoldItems(soldRetentionDays: Int = 2) {
        let now = Date()
        let cutoff =
            Calendar.current.date(byAdding: .day, value: -soldRetentionDays, to: now) ?? now
        let beforeCount = items.count

        // Collect items to be removed for cache cleanup
        let itemsToRemove = items.filter { item in
            if let s = item.soldDate {
                return s < cutoff
            }
            return false
        }

        // Clean up cached images for removed items
        for item in itemsToRemove {
            ImageCacheManager.shared.removeCachedMarketplaceImages(itemId: item.id)
        }

        items.removeAll { item in
            if let s = item.soldDate {
                return s < cutoff
            }
            return false
        }
        if items.count != beforeCount {
            saveItems()
        }
    }

    private func saveWishlist() {
        if let data = try? JSONEncoder().encode(Array(wishlistItemIDs)),
            let str = String(data: data, encoding: .utf8)
        {
            wishlistData = str
        }
    }

    private func loadWishlist() {
        guard let data = wishlistData.data(using: .utf8),
            let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else {
            wishlistItemIDs = []
            return
        }
        wishlistItemIDs = Set(ids)
    }

    private func toggleWishlist(for item: MarketplaceItem) {
        if wishlistItemIDs.contains(item.id) {
            wishlistItemIDs.remove(item.id)
        } else {
            wishlistItemIDs.insert(item.id)
        }
        saveWishlist()
    }

    var body: some View {
        content
    }

    private var content: some View {
        NavigationStack {
            innerContent
                .background(marketplaceBackground)
                // Move the section label into the navigation bar's trailing area and rename it
                .toolbar {
                    // Add button in the navigation bar
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showAddSheet = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.accentColor, Color.accentColor.opacity(0.8),
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Add Item")
                    }
                }
                .task {
                    // Track screen view
                    AnalyticsService.shared.trackScreenView("Marketplace")
                    await startWatchingMarketplace()
                }
                .onDisappear {
                    FirebaseManager.shared.stopWatchingMarketplaceItems()
                }
                // Observe upload progress and completion notifications (per-attachment)
                .onReceive(NotificationCenter.default.publisher(for: .marketplaceUploadProgress)) {
                    note in
                    guard let info = note.userInfo, let id = info["id"] as? String,
                        let type = info["type"] as? String
                    else { return }
                    if let prog = info["progress"] as? Double {
                        var byAttachment = uploadProgress[id] ?? [:]
                        byAttachment[type] = prog
                        uploadProgress[id] = byAttachment
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .marketplaceUploadCompleted)) {
                    note in
                    guard let info = note.userInfo, let id = info["id"] as? String,
                        let type = info["type"] as? String
                    else { return }
                    // mark attachment complete
                    var byAttachment = uploadProgress[id] ?? [:]
                    byAttachment[type] = 1.0
                    uploadProgress[id] = byAttachment

                    // store/clear error for this attachment
                    var errs = uploadErrors[id] ?? [:]
                    if let errObj = info["error"] as? NSError {
                        errs[type] = errObj.localizedDescription
                    } else if let errStr = info["error"] as? String {
                        errs[type] = errStr
                    } else {
                        errs.removeValue(forKey: type)
                    }
                    uploadErrors[id] = errs.isEmpty ? nil : errs
                }
                .sheet(isPresented: $showAddSheet) {
                    MarketplaceAddSheet(
                        categories: categories.filter { $0 != "All" },
                        defaultContact: userName,
                        defaultCell: userCell,
                        onAdd: { newItem in
                            var itemWithDefaults = newItem
                            itemWithDefaults.isSold = false
                            items.insert(itemWithDefaults, at: 0)
                            saveItems()
                            // Send notification if enabled
                            if notifyMarketplace {
                                let content = UNMutableNotificationContent()
                                content.title = "Marketplace: New Item Added"
                                content.body = "A new item was listed: \(itemWithDefaults.title)"
                                content.sound = .default
                                let request = UNNotificationRequest(
                                    identifier: "marketplace-\(itemWithDefaults.id)", content: content,
                                    trigger: nil)
                                UNUserNotificationCenter.current().add(
                                    request, withCompletionHandler: nil)
                            }

                            // Persist remotely (optimistic local already updated)
                            // Build DTO directly from item (no need to encode/decode here)
                            let dto = FirebaseManager.MarketplaceDTO(
                                id: itemWithDefaults.id, owner: itemWithDefaults.owner,
                                title: itemWithDefaults.title, description: itemWithDefaults.description, price: itemWithDefaults.price,
                                category: itemWithDefaults.category,
                                condition: itemWithDefaults.condition, date: itemWithDefaults.date,
                                contact: itemWithDefaults.contact, isSold: itemWithDefaults.isSold, soldDate: itemWithDefaults.soldDate,
                                isNegotiable: itemWithDefaults.isNegotiable,
                                tags: itemWithDefaults.tags, location: itemWithDefaults.location,
                                imageURL: nil, additionalImageURLs: [])
                            let primaryData = itemWithDefaults.image?.jpegData(compressionQuality: 0.8)
                            let additionalData = itemWithDefaults.additionalImages.compactMap {
                                $0.jpegData(compressionQuality: 0.7)
                            }
                            FirebaseManager.shared.createOrUpdateMarketplaceItem(
                                dto, primaryImageData: primaryData, additionalImageData: additionalData
                            ) { err in
                                if let err = err { print("Marketplace upload error: \(err)") }
                            }

                            // Dismiss the sheet after successful creation
                            showAddSheet = false
                        }
                    )
                }
                .sheet(item: $selectedItem) { item in
                    EnhancedMarketplaceDetailView(
                        item: item,
                        isOwner: isOwner(item),
                        isAdmin: isAdmin,
                        isInWishlist: wishlistItemIDs.contains(item.id),
                        onWishlistToggle: { toggleWishlist(for: item) },
                        onDelete: {
                            // runtime guard: only owner or admin may delete
                            if !canManageItem(item) { return }
                            if let idx = items.firstIndex(of: item) {
                                let itemToDelete = items[idx]
                                items.remove(at: idx)
                                saveItems()

                                // Clean up cached images
                                ImageCacheManager.shared.removeCachedMarketplaceImages(
                                    itemId: itemToDelete.id)

                                FirebaseManager.shared.deleteMarketplaceItem(id: item.id.uuidString) {
                                    err in
                                    if let err = err {
                                        print("Remote marketplace delete error: \(err)")
                                    }
                                }
                            }
                        },
                        onMarkSold: {
                            // runtime guard: only owner or admin may mark sold
                            if !canManageItem(item) { return }
                            if let idx = items.firstIndex(of: item) {
                                items[idx].isSold = true
                                items[idx].soldDate = Date()
                                saveItems()
                                autoCleanupSoldItems()
                                saveItems()
                                // Persist sold state to Firebase (targeted update)
                                let updated = items[idx]
                                FirebaseManager.shared.updateIsSold(
                                    itemId: updated.id.uuidString, isSold: updated.isSold,
                                    soldDate: updated.soldDate
                                ) { err in
                                    if let err = err {
                                        print("Marketplace mark-sold remote error: \(err)")
                                    } else {
                                        print("Marketplace item marked sold synced: \(updated.id)")
                                    }
                                }
                            }
                        },
                        onUnmarkSold: {
                            // runtime guard: only owner or admin may unmark sold
                            if !canManageItem(item) { return }
                            if let idx = items.firstIndex(of: item) {
                                items[idx].isSold = false
                                items[idx].soldDate = nil
                                saveItems()
                                // Persist unmark to Firebase (targeted update)
                                let updated = items[idx]
                                FirebaseManager.shared.updateIsSold(
                                    itemId: updated.id.uuidString, isSold: updated.isSold,
                                    soldDate: updated.soldDate
                                ) { err in
                                    if let err = err {
                                        print("Marketplace unmark-sold remote error: \(err)")
                                    } else {
                                        print("Marketplace item unmarked sold synced: \(updated.id)")
                                    }
                                }
                            }
                        }
                    )
                }
                .sheet(isPresented: $showFilters) {
                    filtersView
                }
        }
    }

    // MARK: - Helper Methods for View Construction
    
    private func startWatchingMarketplace() async {
        await MainActor.run {
            loadItems()
            loadWishlist()
        }
        // Start watching remote marketplace and merge updates
        FirebaseManager.shared.watchMarketplaceItems { dtos in
            self.processMarketplaceUpdates(dtos)
        }
    }

    private func processMarketplaceUpdates(_ dtos: [FirebaseManager.MarketplaceDTO]) {
        DispatchQueue.main.async {
            // Map DTOs to local MarketplaceItem, checking cache before downloading
            var newItems: [MarketplaceItem] = []
            let group = DispatchGroup()
            for dto in dtos {
                print("[MarketplaceTab] 📥 Loading item \(dto.id.uuidString.prefix(8)): imageURL=\(dto.imageURL?.absoluteString.prefix(50) ?? "nil"), additionalURLs=\(dto.additionalImageURLs.count)")
                group.enter()
                
                // Check cache first before downloading
                var primaryImage: UIImage? = UIImage.cachedMarketplace(itemId: dto.id, imageType: "primary")
                var additional: [UIImage] = []
                
                // Load cached additional images
                for index in 0..<10 {
                    if let cachedImage = UIImage.cachedMarketplace(itemId: dto.id, imageType: "additional_\(index)") {
                        additional.append(cachedImage)
                    } else {
                        break
                    }
                }
                
                // Only download primary image if not cached
                if primaryImage == nil, let url = dto.imageURL {
                    URLSession.shared.dataTask(with: url) { data, _, _ in
                        if let data = data, let img = UIImage(data: data) {
                            primaryImage = img
                            // Cache immediately
                            img.cacheForMarketplace(itemId: dto.id, imageType: "primary")
                        }
                        
                        // Download additional images only if needed
                        let addGroup = DispatchGroup()
                        if additional.isEmpty && !dto.additionalImageURLs.isEmpty {
                            for (index, aurl) in dto.additionalImageURLs.enumerated() {
                                addGroup.enter()
                                URLSession.shared.dataTask(with: aurl) { d, _, _ in
                                    if let d = d, let img = UIImage(data: d) {
                                        additional.append(img)
                                        // Cache immediately
                                        img.cacheForMarketplace(itemId: dto.id, imageType: "additional_\(index)")
                                    }
                                    addGroup.leave()
                                }.resume()
                            }
                        }
                        
                        addGroup.notify(queue: .main) {
                            var item = MarketplaceItem(
                                id: dto.id,
                                owner: dto.owner,
                                title: dto.title,
                                description: dto.description,
                                price: dto.price,
                                category: dto.category,
                                condition: dto.condition,
                                date: dto.date,
                                contact: dto.contact,
                                isSold: dto.isSold,
                                soldDate: dto.soldDate,
                                isNegotiable: dto.isNegotiable,
                                tags: dto.tags,
                                location: dto.location,
                                sustainabilityScore: 0,
                                isEmergency: false,
                                pickupOptions: [],
                                imageURL: dto.imageURL?.absoluteString,
                                additionalImageURLs: dto.additionalImageURLs.map {
                                    $0.absoluteString
                                }
                            )

                            // Set images via computed properties (already cached above)
                            if let primaryImage = primaryImage {
                                item.image = primaryImage
                            }
                            item.additionalImages = additional

                            newItems.append(item)
                            group.leave()
                        }
                    }.resume()
                } else {
                    // Images already cached or no URL - create item immediately
                    var item = MarketplaceItem(
                        id: dto.id,
                        owner: dto.owner,
                        title: dto.title,
                        description: dto.description,
                        price: dto.price,
                        category: dto.category,
                        condition: dto.condition,
                        date: dto.date,
                        contact: dto.contact,
                        isSold: dto.isSold,
                        soldDate: dto.soldDate,
                        isNegotiable: dto.isNegotiable,
                        tags: dto.tags,
                        location: dto.location,
                        sustainabilityScore: 0,
                        isEmergency: false,
                        pickupOptions: [],
                        imageURL: dto.imageURL?.absoluteString,
                        additionalImageURLs: dto.additionalImageURLs.map {
                            $0.absoluteString
                        }
                    )

                    // Set images from cache
                    if let primaryImage = primaryImage {
                        item.image = primaryImage
                    }
                    item.additionalImages = additional

                    newItems.append(item)
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                // Firebase is the source of truth - replace local items with remote
                // Sort by date (newest first)
                print("[MarketplaceTab] 🔄 Updating items array with \(newItems.count) items from Firebase")
                self.items = newItems.sorted { $0.date > $1.date }
                print("[MarketplaceTab] ✅ Items array updated, triggering UI refresh")
                self.saveItems()
            }
        }
    }

    private var innerContent: some View {
        VStack(spacing: 0) {
            // Enhanced Search & Filter Header
            VStack(spacing: 12) {
                    // Search Bar with improved styling
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search items, tags, or descriptions...", text: $searchText)
                            .textFieldStyle(.plain)
                            .onChange(of: searchText) { _, newValue in
                                searchSubject.send(newValue)
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Filter and Sort Controls
                    HStack {
                        // Category Filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.self) { category in
                                    Button(action: {
                                        withAnimation(Animation.spring) {
                                            selectedCategory = category
                                            filterAnimationTrigger.toggle()
                                        }
                                    }) {
                                        Text(category)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                selectedCategory == category
                                                    ? Color.accentColor.opacity(0.2)
                                                    : Color(.systemGray5)
                                            )
                                            .foregroundColor(
                                                selectedCategory == category
                                                    ? .accentColor
                                                    : .primary
                                            )
                                            .cornerRadius(20)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        Spacer()

                        // Filter & Sort Buttons
                        HStack(spacing: 8) {
                            Button(action: { showFilters.toggle() }) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }

                            Button(action: { showWishlist.toggle() }) {
                                Image(
                                    systemName: wishlistItems.isEmpty ? "heart" : "heart.fill"
                                )
                                .font(.title2)
                                .foregroundColor(wishlistItems.isEmpty ? .secondary : .red)
                            }
                        }
                        .padding(.trailing)
                    }
            }
            .padding(.top, 4)
            .background(Color(.systemBackground))

            // Content Area
            if showWishlist {
                // Wishlist View
                wishlistView
            } else {
                // Main Marketplace View
                marketplaceView
            }
        }
    }
    
    private func deleteItem(_ item: MarketplaceItem) {
        if !canManageItem(item) { return }
        if let idx = items.firstIndex(of: item) {
            let itemToDelete = items[idx]
            items.remove(at: idx)
            saveItems()

            // Clean up cached images
            ImageCacheManager.shared.removeCachedMarketplaceImages(itemId: itemToDelete.id)

            FirebaseManager.shared.deleteMarketplaceItem(id: item.id.uuidString) { err in
                if let err = err {
                    print("Remote marketplace delete error: \(err)")
                }
            }
        }
    }

    private func markAsSold(_ item: MarketplaceItem) {
        if !canManageItem(item) { return }
        if let idx = items.firstIndex(of: item) {
            items[idx].isSold = true
            items[idx].soldDate = Date()
            saveItems()
            autoCleanupSoldItems()
            saveItems()
            // Persist sold state to Firebase (targeted update)
            let updated = items[idx]
            FirebaseManager.shared.updateIsSold(
                itemId: updated.id.uuidString, isSold: updated.isSold,
                soldDate: updated.soldDate
            ) { err in
                if let err = err {
                    print("Marketplace mark-sold remote error: \(err)")
                } else {
                    print("Marketplace item marked sold synced: \(updated.id)")
                }
            }
        }
    }

    private func unmarkAsSold(_ item: MarketplaceItem) {
        if !canManageItem(item) { return }
        if let idx = items.firstIndex(of: item) {
            items[idx].isSold = false
            items[idx].soldDate = nil
            saveItems()
            // Persist unmark to Firebase (targeted update)
            let updated = items[idx]
            FirebaseManager.shared.updateIsSold(
                itemId: updated.id.uuidString, isSold: updated.isSold,
                soldDate: updated.soldDate
            ) { err in
                if let err = err {
                    print("Marketplace unmark-sold remote error: \(err)")
                } else {
                    print("Marketplace item unmarked sold synced: \(updated.id)")
                }
            }
        }
    }
    
    private var marketplaceView: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                let filteredItems = items.filter { item in
                    let matchesSearch = searchText.isEmpty || 
                        item.title.localizedCaseInsensitiveContains(searchText) ||
                        item.description.localizedCaseInsensitiveContains(searchText) ||
                        item.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
                    
                    let matchesCategory = selectedCategory == "All" || item.category == selectedCategory
                    
                    let matchesCondition = selectedCondition == nil || item.condition == selectedCondition
                    
                    let matchesPrice = item.price >= priceRange.lowerBound && item.price <= priceRange.upperBound
                    
                    return matchesSearch && matchesCategory && matchesCondition && matchesPrice
                }
                .sorted {
                    switch sortBy {
                    case .newest: return $0.date > $1.date
                    case .oldest: return $0.date < $1.date
                    case .priceLowToHigh: return $0.price < $1.price
                    case .priceHighToLow: return $0.price > $1.price
                    }
                }
                
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Items Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try adjusting your filters or search terms.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(filteredItems) { item in
                        EnhancedMarketplaceItemCard(
                            item: item,
                            isInWishlist: wishlistItemIDs.contains(item.id),
                            uploadProgress: uploadProgress[item.id.uuidString],
                            uploadErrors: uploadErrors[item.id.uuidString],
                            onRetryUpload: {
                                AttachmentRecoveryManager.shared.recoverSpecificMarketplaceItem(item.id)
                            },
                            onRetryAttachment: { key, idx in
                                AttachmentRecoveryManager.shared.recoverSpecificMarketplaceItem(item.id)
                            },
                            onTap: { selectedItem = item },
                            onWishlistToggle: { toggleWishlist(for: item) },
                            onQuickBuy: { markAsSold(item) },
                            onUnmarkSold: { unmarkAsSold(item) },
                            isOwner: isOwner(item),
                            isAdmin: isAdmin,
                            onEdit: { editingItem = item },
                            onDelete: { deleteItem(item) }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var wishlistView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                let wishlist = items.filter { wishlistItemIDs.contains($0.id) }
                if wishlist.isEmpty {
                    ContentUnavailableView(
                        "Your Wishlist is Empty",
                        systemImage: "heart",
                        description: Text("Items you add to your wishlist will appear here.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(wishlist) { item in
                        EnhancedMarketplaceItemCard(
                            item: item,
                            isInWishlist: true,
                            uploadProgress: uploadProgress[item.id.uuidString],
                            uploadErrors: uploadErrors[item.id.uuidString],
                            onRetryUpload: {
                                AttachmentRecoveryManager.shared.recoverSpecificMarketplaceItem(item.id)
                            },
                            onRetryAttachment: { key, idx in
                                AttachmentRecoveryManager.shared.recoverSpecificMarketplaceItem(item.id)
                            },
                            onTap: { selectedItem = item },
                            onWishlistToggle: { toggleWishlist(for: item) },
                            onQuickBuy: { markAsSold(item) },
                            onUnmarkSold: { unmarkAsSold(item) },
                            isOwner: isOwner(item),
                            isAdmin: isAdmin,
                            onEdit: { editingItem = item },
                            onDelete: { deleteItem(item) }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var filtersView: some View {
        NavigationView {
            Form {
                Section(header: Text("Category")) {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                }
                
                Section(header: Text("Condition")) {
                    Picker("Condition", selection: $selectedCondition) {
                        Text("Any").tag(nil as ItemCondition?)
                        ForEach(ItemCondition.allCases, id: \.self) { condition in
                            Text(condition.rawValue).tag(condition as ItemCondition?)
                        }
                    }
                }
                
                Section(header: Text("Price Range")) {
                    Text("R\(Int(priceRange.lowerBound)) - R\(Int(priceRange.upperBound))")
                    Slider(value: Binding(
                        get: { priceRange.upperBound },
                        set: { priceRange = priceRange.lowerBound...$0 }
                    ), in: 0...50000, step: 100)
                }
                
                Section(header: Text("Sort By")) {
                    Picker("Sort By", selection: $sortBy) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showFilters = false
                    }
                }
            }
        }
    }
    
    // MARK: - Persistence for marketplace items is implemented earlier using @AppStorage("marketplaceData").
    // The saveItems()/loadItems() helpers near the top of this file handle encoding/decoding
    // via the `marketplaceData` AppStorage String to avoid storing binary blobs directly in UserDefaults.
}

// MARK: - Enhanced MarketplaceItemCard
struct EnhancedMarketplaceItemCard: View {
    let item: MarketplaceItem
    let isInWishlist: Bool
    // Per-attachment progress/errors keyed by attachment key (e.g. "image", "additional_0")
    var uploadProgress: [String: Double]? = nil
    var uploadErrors: [String: String]? = nil
    // General retry fallback (re-upload all attachments)
    var onRetryUpload: (() -> Void)? = nil
    // Retry a single attachment identified by key (e.g. "image" or "additional_<index>")
    var onRetryAttachment: ((_ attachmentKey: String, _ index: Int?) -> Void)? = nil
    let onTap: () -> Void
    let onWishlistToggle: () -> Void
    let onQuickBuy: () -> Void
    let onUnmarkSold: () -> Void
    let isOwner: Bool
    let isAdmin: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    private var cardGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(.tertiarySystemBackground),
                Color(.secondarySystemBackground),
                Color(.systemBackground),
                Color(.secondarySystemBackground),
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var borderGradient: LinearGradient {
        let isDark = colorScheme == .dark
        return LinearGradient(
            colors: isDark ? 
                [Color.white.opacity(0.1), Color.clear, Color.black.opacity(0.2)] :
                [Color.white.opacity(0.8), Color.clear, Color.black.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var primaryShadowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.25)
    }
    
    private var secondaryShadowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.15)
    }
    
    private var tertiaryShadowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.08)
    }
    
    private var quaternaryShadowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.01) : Color.black.opacity(0.04)
    }
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Image Section
                ZStack(alignment: .topTrailing) {
                    // Show primary image consistently, fallback to URL if not cached
                    if let primaryImage = item.image {
                        let _ = print("[MarketplaceCard] ✅ Rendering image for item \(item.id.uuidString.prefix(8))")
                        GeometryReader { geometry in
                            Image(uiImage: primaryImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.width * 0.75)
                                .clipped()
                        }
                        .aspectRatio(4/3, contentMode: .fit)
                        .overlay(
                            Group {
                                if let p = uploadProgress?["image"], p < 1.0 {
                                    ProgressView(value: p).progressViewStyle(
                                        CircularProgressViewStyle()
                                    ).scaleEffect(0.6).padding(8)
                                } else if uploadErrors?["image"] != nil {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow).padding(8)
                                }
                            }, alignment: .bottomLeading
                        )
                    } else if let urlStr = item.imageURL ?? item.additionalImageURLs.first,
                        !urlStr.isEmpty,
                        let url = URL(string: urlStr)
                    {
                        let _ = print("[MarketplaceCard] ⚠️ No cached image for item \(item.id.uuidString.prefix(8)), loading from URL: \(url.absoluteString.prefix(50))...")
                        let _ = print("[MarketplaceCard]    imageURL: \(item.imageURL ?? "nil"), additionalURLs: \(item.additionalImageURLs.count) items")
                        // Load remote image asynchronously
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .aspectRatio(4/3, contentMode: .fit)
                                    .overlay(ProgressView())
                            case .success(let image):
                                GeometryReader { geometry in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geometry.size.width, height: geometry.size.width * 0.75)
                                        .clipped()
                                }
                                .aspectRatio(4/3, contentMode: .fit)
                                .onAppear {
                                    // Cache the downloaded image for future use
                                    Task {
                                        if let data = try? await URLSession.shared.data(from: url).0,
                                           let uiImage = UIImage(data: data) {
                                            uiImage.cacheForMarketplace(itemId: item.id, imageType: "primary")
                                        }
                                    }
                                }
                            default:
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .aspectRatio(4/3, contentMode: .fit)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundColor(.gray.opacity(0.4))
                                    )
                            }
                        }
                    } else {
                        let _ = print("[MarketplaceCard] ❌ No image available for item \(item.id.uuidString.prefix(8)) - showing placeholder")
                        let _ = print("[MarketplaceCard]    imageURL: \(item.imageURL ?? "nil"), additionalURLs: \(item.additionalImageURLs.count) items, allURLs: \(item.additionalImageURLs)")
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .aspectRatio(4/3, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(.gray.opacity(0.4))
                            )
                    }

                    // Wishlist Button
                    Button(action: onWishlistToggle) {
                        Image(systemName: isInWishlist ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isInWishlist ? .red : .white)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.28))
                            .cornerRadius(14)
                    }
                    .padding(8)

                    // Sold Overlay
                    if item.isSold {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("SOLD")
                                    .font(.headline.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red)
                                    .cornerRadius(8)
                                Spacer()
                            }
                            Spacer()
                        }
                        .background(Color.black.opacity(0.4))
                    }
                }

                // Optional additional images preview (thumbnails)
                if !item.additionalImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(
                                Array(item.additionalImages.prefix(5).enumerated()), id: \.offset
                            ) { idx, img in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 36)
                                        .clipped()
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
                                        )

                                    // show per-additional image progress/error
                                    let key = "additional_\(idx)"
                                    if let p = uploadProgress?[key], p < 1.0 {
                                        ProgressView(value: p).progressViewStyle(
                                            CircularProgressViewStyle()
                                        ).frame(width: 20, height: 20).background(
                                            Color.black.opacity(0.4)
                                        ).cornerRadius(10).padding(4)
                                    } else if uploadErrors?[key] != nil {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.yellow)
                                            if let onRetryAtt = onRetryAttachment {
                                                Button(action: { onRetryAtt(key, idx) }) {
                                                    Image(systemName: "arrow.clockwise.circle")
                                                }
                                                .buttonStyle(BorderlessButtonStyle())
                                            }
                                        }
                                        .padding(6)
                                    }
                                }
                            }
                        }
                        .padding([.leading, .trailing], 8)
                        .padding(.top, 6)
                    }
                }

                // Content Section
                VStack(alignment: .leading, spacing: 8) {
                    // Title & Condition
                    HStack {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundColor(item.isSold ? .secondary : .primary)
                            .strikethrough(item.isSold, color: .red)

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: item.condition.icon)
                                .font(.caption)
                                .foregroundColor(item.condition.color)
                            Text(item.condition.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Category
                    HStack {
                        Text(item.category)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    // Price & Negotiable
                    HStack {
                        HStack(spacing: 4) {
                            Text("R\(String(format: "%.2f", item.price))")
                                .font(.title3.bold())
                                .foregroundColor(.accentColor)
                                .strikethrough(item.isSold, color: .red)

                            if item.isNegotiable && !item.isSold {
                                Text("OBO")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }

                        Spacer()
                    }

                    // Location & Quick Actions
                    HStack {
                        if item.location != "Your Neighborhood" {
                            HStack(spacing: 4) {
                                Image(systemName: "location")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(item.location)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        // Only allow owners or admins to mark as sold (quick action)
                        if !item.isSold && (isOwner || isAdmin) {
                            Button(action: onQuickBuy) {
                                Image(systemName: "cart.badge.plus")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    // Sold date badge (if sold)
                    if item.isSold {
                        if let soldOn = item.soldDate {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                Text("Sold on \(soldOn, style: .date)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderGradient, lineWidth: 1)
                )
        )
        // Deep 3D shadow system
        .shadow(color: primaryShadowColor, radius: 20, x: 0, y: 10)
        .shadow(color: secondaryShadowColor, radius: 10, x: 0, y: 5)
        .shadow(color: tertiaryShadowColor, radius: 4, x: 0, y: 2)
        .shadow(color: quaternaryShadowColor, radius: 1, x: 0, y: 1)
        .contextMenu {
            if isOwner || isAdmin {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                if !item.isSold {
                    Button {
                        onQuickBuy()
                    } label: {
                        Label("Mark as Sold", systemImage: "checkmark.seal")
                    }
                } else {
                    Button {
                        onUnmarkSold()
                    } label: {
                        Label("Unmark Sold", systemImage: "arrow.uturn.left")
                    }
                }
            }

            // Show per-attachment progress lines
            if let byAttachment = uploadProgress, !byAttachment.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(byAttachment.keys.sorted(), id: \.self) { key in
                        HStack(spacing: 8) {
                            Text(key).font(.caption2).foregroundColor(.secondary)
                            ProgressView(value: byAttachment[key] ?? 0.0)
                                .progressViewStyle(LinearProgressViewStyle())
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            // Show per-attachment errors with inline retry for each
            if let errs = uploadErrors, !errs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(errs.keys.sorted(), id: \.self) { key in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(
                                .yellow)
                            Text(errs[key] ?? "Upload failed").font(.caption).foregroundColor(
                                .secondary
                            ).lineLimit(1)
                            Spacer()
                            if let onRetry = onRetryUpload {
                                Button("Retry") { onRetry() }.buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }

                    // Add manual recovery button for persistent failures
                    Button("Force Recovery") {
                        AttachmentRecoveryManager.shared.recoverSpecificMarketplaceItem(item.id)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            Button {
                onWishlistToggle()
            } label: {
                Label(
                    isInWishlist ? "Remove from Wishlist" : "Add to Wishlist",
                    systemImage: isInWishlist ? "heart.slash" : "heart")
            }
        }
    }
}

// MARK: - Placeholder Enhanced Views (to be implemented)

struct EnhancedMarketplaceDetailView: View {
    let item: MarketplaceItem
    let isOwner: Bool
    let isAdmin: Bool
    let isInWishlist: Bool
    let onWishlistToggle: () -> Void
    let onDelete: () -> Void
    let onMarkSold: () -> Void
    let onUnmarkSold: () -> Void

    var body: some View {
        // For now, use the existing MarketplaceDetailView with converted item
        MarketplaceDetailView(
            item: convertToOldMarketplaceItem(item),
            isOwner: isOwner,
            isAdmin: isAdmin,
            onMarkSold: onMarkSold,
            onUnmarkSold: onUnmarkSold,
            onDelete: onDelete
        )
    }

    private func convertToOldMarketplaceItem(_ newItem: MarketplaceItem) -> MarketplaceItem {
        // With the new unified data model, no conversion is needed
        return newItem
    }
}

// Increase the advert attachment limit to 100MB
// Ensure that the total size of all attachments does not exceed 100MB
let maxAttachmentSizeMB = 100

// Update the logic where attachments are handled to enforce the new limit
// Example: Check total size before uploading
func validateAttachmentSize(_ attachments: [Data]) -> Bool {
    let totalSizeMB = attachments.reduce(0) { $0 + Double($1.count) / (1024 * 1024) }
    return totalSizeMB <= Double(maxAttachmentSizeMB)
}
