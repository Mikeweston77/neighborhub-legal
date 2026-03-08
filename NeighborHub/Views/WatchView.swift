import CryptoKit
import SwiftUI
import UIKit
import WebKit

#if canImport(FirebaseFirestore)
    import FirebaseFirestore
#endif

// MARK: - String Extension for MD5 Hashing
extension String {
    var md5: String {
        let digest = Insecure.MD5.hash(data: self.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - Color Extensions for Enhanced Dark Mode Support
extension Color {
    static var watchDarkBackground: Color {
        Color(red: 0.05, green: 0.05, blue: 0.1)
    }

    static var watchDarkSecondary: Color {
        Color(red: 0.1, green: 0.1, blue: 0.15)
    }

    static var watchGlassEffect: Color {
        Color.white.opacity(0.1)
    }
}

// Fullscreen image viewer with zoom support
struct FullscreenImageView: View {
    let imageURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGSize = .zero
    @State private var isDismissing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // background dim adjusts with drag to give a dismissal feel
            Color.black
                .opacity(Double(max(0.25, 1 - (abs(dragOffset.height) / 800))))
                .ignoresSafeArea()

            IncidentZoomableImageView(url: imageURL)
                .ignoresSafeArea()
                .offset(y: dragOffset.height)
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            // only track vertical drag to dismiss
                            dragOffset = CGSize(width: 0, height: v.translation.height)
                        }
                        .onEnded { v in
                            let threshold: CGFloat = 200
                            if abs(v.translation.height) > threshold {
                                // perform dismiss
                                withAnimation(.easeOut(duration: 0.25)) {
                                    isDismissing = true
                                    dragOffset = CGSize(
                                        width: 0, height: v.translation.height > 0 ? 1000 : -1000)
                                }
                                // small delay to allow animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                    dismiss()
                                }
                            } else {
                                // snap back
                                withAnimation(.spring()) {
                                    dragOffset = .zero
                                }
                            }
                        }
                )

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .padding()
            }
            .opacity(dragOffset == .zero ? 1.0 : 0.8)
        }
    }
}

// Fullscreen image viewer for UIImage (imageData) with zoom support
struct FullscreenImageDataView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGSize = .zero
    @State private var isDismissing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // background dim adjusts with drag to give a dismissal feel
            Color.black
                .opacity(Double(max(0.25, 1 - (abs(dragOffset.height) / 800))))
                .ignoresSafeArea()

            IncidentZoomableUIImageView(image: image)
                .ignoresSafeArea()
                .offset(y: dragOffset.height)
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            // only track vertical drag to dismiss
                            dragOffset = CGSize(width: 0, height: v.translation.height)
                        }
                        .onEnded { v in
                            let threshold: CGFloat = 200
                            if abs(v.translation.height) > threshold {
                                // perform dismiss
                                withAnimation(.easeOut(duration: 0.25)) {
                                    isDismissing = true
                                    dragOffset = CGSize(
                                        width: 0, height: v.translation.height > 0 ? 1000 : -1000)
                                }
                                // small delay to allow animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                    dismiss()
                                }
                            } else {
                                // snap back
                                withAnimation(.spring()) {
                                    dragOffset = .zero
                                }
                            }
                        }
                )

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .padding()
            }
            .opacity(dragOffset == .zero ? 1.0 : 0.8)
        }
    }
}

// Simple zoomable image using UIImageView inside UIViewRepresentable
struct IncidentZoomableImageView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.imageView = imageView
        scrollView.addSubview(imageView)

        // load image async and compute initial zoom to fit
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    imageView.image = uiImage

                    // Set imageView frame to its image's size
                    let imageSize = uiImage.size
                    imageView.frame = CGRect(origin: .zero, size: imageSize)
                    scrollView.contentSize = imageSize

                    // Calculate min scale to fit image into scrollView bounds
                    let widthScale = scrollView.bounds.width / imageSize.width
                    let heightScale = scrollView.bounds.height / imageSize.height
                    let minScale = min(widthScale, heightScale, 1.0)

                    scrollView.minimumZoomScale = minScale
                    scrollView.maximumZoomScale = max(minScale * 4.0, 1.0)
                    scrollView.zoomScale = minScale

                    // Center image
                    context.coordinator.centerImage(in: scrollView)
                }
            }
        }.resume()

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // If bounds changed (e.g., rotation), re-center content
        context.coordinator.centerImage(in: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        func centerImage(in scrollView: UIScrollView) {
            guard let imageView = imageView else { return }
            let scrollBounds = scrollView.bounds
            var frameToCenter = imageView.frame

            // center horizontally
            if frameToCenter.size.width < scrollBounds.size.width {
                frameToCenter.origin.x = (scrollBounds.size.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }

            // center vertically
            if frameToCenter.size.height < scrollBounds.size.height {
                frameToCenter.origin.y = (scrollBounds.size.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }

            imageView.frame = frameToCenter
        }
    }
}

// Zoomable UIImage viewer (for imageData cases)
struct IncidentZoomableUIImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.image = image
        context.coordinator.imageView = imageView
        scrollView.addSubview(imageView)

        // Set imageView frame to its image's size
        let imageSize = image.size
        
        // Ensure image has valid dimensions
        guard imageSize.width > 0 && imageSize.height > 0 else {
            print("⚠️ Invalid image size: \(imageSize)")
            return scrollView
        }
        
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize

        // Setup zoom scales after layout (when bounds are available)
        DispatchQueue.main.async {
            context.coordinator.setupZoomScales(for: scrollView, imageSize: imageSize)
        }

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // If bounds changed (e.g., rotation), re-setup zoom and center
        guard let imageView = context.coordinator.imageView,
              let imageSize = imageView.image?.size,
              imageSize.width > 0 && imageSize.height > 0,
              uiView.bounds.width > 0 && uiView.bounds.height > 0 else {
            return
        }
        
        context.coordinator.setupZoomScales(for: uiView, imageSize: imageSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }
        
        func setupZoomScales(for scrollView: UIScrollView, imageSize: CGSize) {
            // Ensure both image and scrollView have valid dimensions
            guard imageSize.width > 0 && imageSize.height > 0,
                  scrollView.bounds.width > 0 && scrollView.bounds.height > 0 else {
                print("⚠️ Invalid dimensions - image: \(imageSize), scrollView: \(scrollView.bounds.size)")
                return
            }
            
            // Calculate min scale to fit image into scrollView bounds
            let widthScale = scrollView.bounds.width / imageSize.width
            let heightScale = scrollView.bounds.height / imageSize.height
            let minScale = min(widthScale, heightScale, 1.0)
            
            // Ensure minScale is not zero or negative
            guard minScale > 0 else {
                print("⚠️ Invalid minScale: \(minScale)")
                return
            }

            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = max(minScale * 4.0, 1.0)
            scrollView.zoomScale = minScale

            // Center image
            centerImage(in: scrollView)
        }

        func centerImage(in scrollView: UIScrollView) {
            guard let imageView = imageView else { return }
            let scrollBounds = scrollView.bounds
            var frameToCenter = imageView.frame

            // center horizontally
            if frameToCenter.size.width < scrollBounds.size.width {
                frameToCenter.origin.x = (scrollBounds.size.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }

            // center vertically
            if frameToCenter.size.height < scrollBounds.size.height {
                frameToCenter.origin.y = (scrollBounds.size.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }

            imageView.frame = frameToCenter
        }
    }
}

// MARK: - IncidentImagePicker (UIKit bridge for incidents)
struct IncidentImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        
        // Check availability and set source type
        let requestedType = sourceType
        let isAvailable = UIImagePickerController.isSourceTypeAvailable(requestedType)
        let finalType = isAvailable ? requestedType : .photoLibrary
        
        print("📷 IncidentImagePicker: Requested \(requestedType == .camera ? "CAMERA" : "PHOTO LIBRARY"), available: \(isAvailable), using: \(finalType == .camera ? "CAMERA" : "PHOTO LIBRARY")")
        
        picker.sourceType = finalType
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: IncidentImagePicker
        init(_ parent: IncidentImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - WatchView (Main Watch UI)
struct WatchView: View {
    @AppStorage("watchUsername") private var watchUsername: String = ""
    @AppStorage("watchPassword") private var watchPassword: String = ""

    private var isWatchUser: Bool {
        !watchUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !watchPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    // Registered users from AppStorage (includes cell numbers)
    @AppStorage("registeredUsers") private var registeredUsersString: String = ""

    // Core Data fetch for users (keeping for other potential uses)
    @FetchRequest(
        entity: User.entity(),
        sortDescriptors: [],
        animation: .default
    ) private var coreDataUsers: FetchedResults<User>
    @Environment(\.colorScheme) private var colorScheme
    @State private var showWebPortal = false
    @State private var showTelegramWeb = false
    @State private var showWatchSettings = false
    // Computed property for registered users with cell numbers
    var registeredUsers: [RegisteredUser] {
        registeredUsersString.split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map {
                String($0)
            }
            // support legacy 7-field and extended 10-field formats
            if parts.count == 7 {
                return RegisteredUser(
                    id: parts[0],
                    name: parts[1],
                    email: "",  // Legacy data doesn't have email
                    street: parts[2],
                    suburb: parts[3],
                    city: parts[4],
                    postalCode: parts[5],
                    cell: parts[6],
                    emergencyContactName: "",
                    emergencyContactPhone: "",
                    emergencyContactRelationship: "",
                    isVerified: true, // Legacy users are considered verified
                    joinedDate: nil,
                    profileImageURL: nil,
                    isAdmin: false,
                    isCommittee: false,
                    hasCameraAccess: false,
                    cameraAccessRequested: false,
                    watchCredential: nil
                )
            } else if parts.count == 10 {
                return RegisteredUser(
                    id: parts[0],
                    name: parts[1],
                    email: "",  // Legacy data doesn't have email
                    street: parts[2],
                    suburb: parts[3],
                    city: parts[4],
                    postalCode: parts[5],
                    cell: parts[6],
                    emergencyContactName: parts[7],
                    emergencyContactPhone: parts[8],
                    emergencyContactRelationship: parts[9],
                    isVerified: true, // Legacy users are considered verified
                    joinedDate: nil,
                    profileImageURL: nil,
                    isAdmin: false,
                    isCommittee: false,
                    hasCameraAccess: false,
                    cameraAccessRequested: false,
                    watchCredential: nil
                )
            } else {
                return nil
            }
        }
    }

    // Admin check: committee member logic (copied from WatchTabWithAdminSettings)
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

    @State private var showIncidentSheet = false
    @AppStorage("watchIncidents") private var watchIncidents: String = ""
    @AppStorage("archivedIncidents") private var archivedIncidents: String = ""

    // Firestore real-time incident data
    @State private var firestoreIncidents: [FirebaseManager.Incident] = []
    @State private var firestoreArchivedIncidents: [FirebaseManager.Incident] = []
    @State private var useFirestoreData = true  // Toggle to prefer Firestore over AppStorage
    // Registered users from Firestore
    @State private var firestoreRegisteredUsers: [RegisteredUser] = []
    private var registeredUsersList: [RegisteredUser] {
        // Prefer Firestore data if available, otherwise fall back to AppStorage string
        if !firestoreRegisteredUsers.isEmpty { return firestoreRegisteredUsers }
        return registeredUsers
    }

    // Edit incident state
    @State private var showEditIncidentSheet = false
    @State private var editingIncidentIndex: Int? = nil
    @State private var editingIncidentID: UUID? = nil
    @State private var editingIncidentTitle: String = ""
    @State private var editingIncidentDescription: String = ""
    @State private var editingIncidentDate: Date = Date()
    @State private var editingIncidentShowOnHome: Bool = false
    @State private var editingIncidentLocation: String = ""

    // Archive and delete state
    @State private var showArchived = false
    @State private var showDeleteConfirmation = false
    @State private var incidentToDelete: Int? = nil

    // Bulk management state for admin users
    @State private var isSelectingBulk: Bool = false
    @State private var selectedIncidentIDs: Set<UUID> = []
    @State private var showBulkActionSheet: Bool = false
    @State private var showBulkDeleteConfirmation: Bool = false
    @State private var showSuccessMessage: Bool = false
    @State private var successMessage: String = ""

    func deleteIncident(at index: Int) {
        // If we're using Firestore-backed incidents, delete the document server-side.
        if useFirestoreData {
            guard firestoreIncidents.indices.contains(index) else { return }
            let id = firestoreIncidents[index].id.uuidString
            FirebaseManager.shared.deleteIncident(id: id) { err in
                if let err = err {
                    print("WatchView: failed to delete incident on server: \(err)")
                } else {
                    print("WatchView: deleted incident \(id) on server")
                }
            }
            return
        }

        // Fallback: local AppStorage string removal
        var incidents = watchIncidents.split(separator: ";").map { String($0) }
        guard incidents.indices.contains(index) else { return }
        incidents.remove(at: index)
        watchIncidents = incidents.joined(separator: ";")
    }

    func archiveIncident(at index: Int) {
        // If using Firestore, call the server-side archive API which will mark archivedAt on the document.
        if useFirestoreData {
            guard firestoreIncidents.indices.contains(index) else { return }
            let id = firestoreIncidents[index].id.uuidString
            FirebaseManager.shared.archiveIncident(id: id) { err in
                if let err = err {
                    print("WatchView: failed to archive incident on server: \(err)")
                } else {
                    print("WatchView: archived incident \(id) on server")
                }
            }
            return
        }

        // Fallback: local AppStorage archiving
        var incidents = watchIncidents.split(separator: ";").map { String($0) }
        guard incidents.indices.contains(index) else { return }

        let incidentToArchive = incidents[index]
        incidents.remove(at: index)
        watchIncidents = incidents.joined(separator: ";")

        // Add timestamp to archived incident for tracking when it was archived
        let archiveTimestamp = Date().timeIntervalSince1970
        let archivedEntry = "\(incidentToArchive)|\(archiveTimestamp)"

        if archivedIncidents.isEmpty {
            archivedIncidents = archivedEntry
        } else {
            archivedIncidents = archivedEntry + ";" + archivedIncidents
        }
    }

    func deleteArchivedIncident(at index: Int) {
        // If using Firestore, delete the archived document server-side
        if useFirestoreData {
            guard firestoreArchivedIncidents.indices.contains(index) else { return }
            let id = firestoreArchivedIncidents[index].id.uuidString
            FirebaseManager.shared.deleteArchivedIncident(id: id) { err in
                if let err = err {
                    print("WatchView: failed to delete archived incident on server: \(err)")
                } else {
                    print("WatchView: deleted archived incident \(id) on server")
                }
            }
            return
        }

        var archived = archivedIncidents.split(separator: ";").map { String($0) }
        guard archived.indices.contains(index) else { return }
        archived.remove(at: index)
        archivedIncidents = archived.joined(separator: ";")
    }

    func restoreIncident(at index: Int) {
        if useFirestoreData {
            // Restore server-side archived document by matching its title and date
            guard firestoreArchivedIncidents.indices.contains(index) else {
                print(
                    "WatchView: Invalid index \(index) for restore, only have \(firestoreArchivedIncidents.count) archived incidents"
                )
                return
            }
            let inc = firestoreArchivedIncidents[index]
            print(
                "WatchView: Attempting to restore incident: title='\(inc.title)', incidentType='\(inc.incidentType ?? "nil")', date=\(inc.date)"
            )

            // Try ID-based restore first (more reliable), then fall back to title/date matching
            FirebaseManager.shared.restoreArchivedIncidentById(id: inc.id.uuidString) { err in
                if let err = err {
                    print("WatchView: ID-based restore failed, trying title/date matching: \(err)")
                    // Fallback to title/date matching
                    FirebaseManager.shared.restoreArchivedIncident(
                        matchingTitle: inc.title, date: inc.date, description: inc.description
                    ) { fallbackErr in
                        if let fallbackErr = fallbackErr {
                            print("WatchView: Both restore methods failed: \(fallbackErr)")
                        } else {
                            print(
                                "WatchView: restored archived incident \(inc.id) via fallback method"
                            )
                        }
                    }
                } else {
                    print("WatchView: restored archived incident \(inc.id) via ID-based method")
                }
            }
            return
        }

        // Fallback local AppStorage restore
        var archived = archivedIncidents.split(separator: ";").map { String($0) }
        guard archived.indices.contains(index) else { return }

        let archivedEntry = archived[index]
        let parts = archivedEntry.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0)
        }
        guard parts.count >= 5 else { return }

        // Parse the core fields: timestamp|title|description|showOnHome|archivedTs
        // legacy variables (title/description/date) were previously declared here but not used; skip them

        archived.remove(at: index)
        archivedIncidents = archived.joined(separator: ";")
        let restoredIncident = parts.dropLast().joined(separator: "|")
        if watchIncidents.isEmpty {
            watchIncidents = restoredIncident
        } else {
            watchIncidents = restoredIncident + ";" + watchIncidents
        }
    }

    func updateIncident() {
        guard let idx = editingIncidentIndex else { return }
        var incidents = watchIncidents.split(separator: ";").map { String($0) }
        guard incidents.indices.contains(idx) else { return }
        let updated =
            "\(editingIncidentDate.timeIntervalSince1970)|\(editingIncidentTitle)|\(editingIncidentDescription)|\(editingIncidentShowOnHome ? "1" : "0")"
        incidents[idx] = updated
        watchIncidents = incidents.joined(separator: ";")
    }

    // MARK: - Bulk Actions
    private func performBulkDelete() {
        let count = selectedIncidentIDs.count

        if useFirestoreData {
            // Delete selected incidents from Firestore
            let incidentsToDelete = firestoreIncidents.filter {
                selectedIncidentIDs.contains($0.id)
            }

            for incident in incidentsToDelete {
                FirebaseManager.shared.deleteIncident(id: incident.id.uuidString) { err in
                    if let err = err {
                        print(
                            "WatchView: Failed to delete incident \(incident.id) in Firebase: \(err)"
                        )
                    }
                }
            }
        } else {
            // Delete from local AppStorage - find indices by matching timestamps/titles
            var incidents = watchIncidents.split(separator: ";").map { String($0) }
            var indicesToRemove: [Int] = []

            for (index, incidentString) in incidents.enumerated() {
                let parts = incidentString.split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0) }
                if parts.count >= 4 {
                    // For AppStorage incidents, we'll use timestamp + title as a unique identifier
                    let timestamp = parts[0]
                    let title = parts[1]
                    let pseudoID = UUID(uuidString: "\(timestamp)-\(title)".md5) ?? UUID()
                    if selectedIncidentIDs.contains(pseudoID) {
                        indicesToRemove.append(index)
                    }
                }
            }

            // Remove in reverse order to maintain indices
            for index in indicesToRemove.sorted(by: >) {
                incidents.remove(at: index)
            }

            watchIncidents = incidents.joined(separator: ";")
        }

        // Clear selection and exit bulk mode
        selectedIncidentIDs.removeAll()
        isSelectingBulk = false

        // Show success message
        successMessage = "✅ Successfully deleted \(count) incident\(count == 1 ? "" : "s")"
        showSuccessMessage = true
    }

    private func performBulkArchive() {
        let count = selectedIncidentIDs.count

        if useFirestoreData {
            // Archive selected incidents in Firestore
            let incidentsToArchive = firestoreIncidents.filter {
                selectedIncidentIDs.contains($0.id)
            }

            for incident in incidentsToArchive {
                FirebaseManager.shared.archiveIncident(id: incident.id.uuidString) { err in
                    if let err = err {
                        print(
                            "WatchView: Failed to archive incident \(incident.id) in Firebase: \(err)"
                        )
                    }
                }
            }
        } else {
            // Archive from local AppStorage
            var incidents = watchIncidents.split(separator: ";").map { String($0) }
            var indicesToArchive: [Int] = []
            var incidentsToArchive: [String] = []

            for (index, incidentString) in incidents.enumerated() {
                let parts = incidentString.split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0) }
                if parts.count >= 4 {
                    let timestamp = parts[0]
                    let title = parts[1]
                    let pseudoID = UUID(uuidString: "\(timestamp)-\(title)".md5) ?? UUID()
                    if selectedIncidentIDs.contains(pseudoID) {
                        indicesToArchive.append(index)
                        incidentsToArchive.append(incidentString)
                    }
                }
            }

            // Remove from active incidents
            for index in indicesToArchive.sorted(by: >) {
                incidents.remove(at: index)
            }
            watchIncidents = incidents.joined(separator: ";")

            // Add to archived incidents with timestamps
            let archiveTimestamp = Date().timeIntervalSince1970
            for incident in incidentsToArchive {
                let archivedEntry = "\(incident)|\(archiveTimestamp)"
                if archivedIncidents.isEmpty {
                    archivedIncidents = archivedEntry
                } else {
                    archivedIncidents = archivedEntry + ";" + archivedIncidents
                }
            }
        }

        // Clear selection and exit bulk mode
        selectedIncidentIDs.removeAll()
        isSelectingBulk = false

        // Show success message
        successMessage = "🗂️ Successfully archived \(count) incident\(count == 1 ? "" : "s")"
        showSuccessMessage = true
    }

    // MARK: - Firestore Registered Users
    @State private var registeredUsersListener: ListenerRegistration? = nil

    private func startWatchingRegisteredUsers() {
        // avoid duplicate listeners
        stopWatchingRegisteredUsers()
        registeredUsersListener = FirebaseManager.shared.watchRegisteredUsers { docs in
            // Map Firestore docs into RegisteredUser models; gracefully handle missing fields
            let mapped: [RegisteredUser] = docs.compactMap { d in
                let uid = (d["uid"] as? String) ?? (d["email"] as? String) ?? ""
                let email = (d["email"] as? String) ?? ""
                let first = (d["firstName"] as? String) ?? ""
                let last = (d["lastName"] as? String) ?? ""
                let street = (d["street"] as? String) ?? ""
                let suburb = (d["suburb"] as? String) ?? ""
                let city = (d["city"] as? String) ?? ""
                let postal = (d["postalCode"] as? String) ?? ""
                let phone = (d["phone"] as? String) ?? ""
                let emName = (d["emergencyContactName"] as? String) ?? ""
                let emPhone = (d["emergencyContactPhone"] as? String) ?? ""
                let emRel = (d["emergencyContactRelationship"] as? String) ?? ""
                let name = [first, last].filter({ !$0.isEmpty }).joined(separator: " ")
                
                // Extract verification and profile data
                let isVerified = (d["verified"] as? Bool) ?? false
                let joinedTimestamp = d["createdAt"] as? Timestamp
                let joinedDate = joinedTimestamp?.dateValue()
                let profileImageURL = (d["profileImageURL"] as? String)
                
                // Extract role data
                let isAdmin = (d["isAdmin"] as? Bool) ?? false
                let isCommittee = (d["isCommittee"] as? Bool) ?? false
                let hasCameraAccess = (d["cameraAccess"] as? Bool) ?? false
                let cameraAccessRequested = (d["cameraAccessRequested"] as? Bool) ?? false
                let watchCredential = (d["watchCredential"] as? String)
                
                return RegisteredUser(
                    id: uid,
                    name: name,
                    email: email,
                    street: street,
                    suburb: suburb,
                    city: city,
                    postalCode: postal,
                    cell: phone,
                    emergencyContactName: emName,
                    emergencyContactPhone: emPhone,
                    emergencyContactRelationship: emRel,
                    isVerified: isVerified,
                    joinedDate: joinedDate,
                    profileImageURL: profileImageURL,
                    isAdmin: isAdmin,
                    isCommittee: isCommittee,
                    hasCameraAccess: hasCameraAccess,
                    cameraAccessRequested: cameraAccessRequested,
                    watchCredential: watchCredential
                )
            }
            DispatchQueue.main.async {
                self.firestoreRegisteredUsers = mapped
            }
        }
    }

    private func stopWatchingRegisteredUsers() {
        registeredUsersListener?.remove()
        registeredUsersListener = nil
    }
    @State private var selectedIncident:
        (idx: Int, title: String, description: String, date: Date)? = nil

    // Filtering and sorting state
    @State private var showFilters = false
    @State private var selectedDateFilter: DateFilter = .all
    @State private var selectedSortOption: SortOption = .newest

    enum DateFilter: String, CaseIterable {
        case all = "All Time"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
    }

    enum SortOption: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case alphabetical = "A-Z"
    }

    // Computed property for archived incidents
    private var archivedIncidentsList: [(index: Int, entry: String)] {
        if useFirestoreData && !firestoreArchivedIncidents.isEmpty {
            return firestoreArchivedIncidents.enumerated().map {
                (index: $0.offset, entry: firestoreArchivedIncidentToString($0.element))
            }
        } else {
            let archived = archivedIncidents.split(separator: ";").enumerated().map {
                (index: $0.offset, entry: String($0.element))
            }
            return archived
        }
    }

    // Helper to convert Firestore archived incident to AppStorage string format
    private func firestoreArchivedIncidentToString(_ incident: FirebaseManager.Incident) -> String {
        let timestamp = incident.date.timeIntervalSince1970
        let title = incident.title
        let description = incident.description ?? ""
        let showOnHome = incident.showOnHome ? "1" : "0"
        let archivedTimestamp =
            incident.archivedAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        return "\(timestamp)|\(title)|\(description)|\(showOnHome)|\(archivedTimestamp)"
    }

    // Computed property for filtered and sorted incidents
    private var filteredIncidents: [(index: Int, entry: String)] {
        // Use Firestore data if available and enabled, otherwise fall back to AppStorage
        if useFirestoreData && !firestoreIncidents.isEmpty {
            // Convert Firestore incidents to the string format for compatibility with existing UI
            let incidents = firestoreIncidents.enumerated().map {
                (index: $0.offset, entry: firestoreIncidentToString($0.element))
            }

            return
                incidents
                .filter { incident in
                    let parts = incident.entry.split(
                        separator: "|", omittingEmptySubsequences: false
                    ).map { String($0) }
                    guard parts.count >= 4 else { return false }

                    let date = Date(timeIntervalSince1970: Double(parts[0]) ?? 0)

                    // Date filter only
                    let passesDateFilter: Bool
                    switch selectedDateFilter {
                    case .all:
                        passesDateFilter = true
                    case .today:
                        passesDateFilter = Calendar.current.isDateInToday(date)
                    case .thisWeek:
                        passesDateFilter = Calendar.current.isDate(
                            date, equalTo: Date(), toGranularity: .weekOfYear)
                    case .thisMonth:
                        passesDateFilter = Calendar.current.isDate(
                            date, equalTo: Date(), toGranularity: .month)
                    }

                    return passesDateFilter
                }
                .sorted { incident1, incident2 in
                    let parts1 = incident1.entry.split(
                        separator: "|", omittingEmptySubsequences: false
                    ).map { String($0) }
                    let parts2 = incident2.entry.split(
                        separator: "|", omittingEmptySubsequences: false
                    ).map { String($0) }

                    guard parts1.count >= 4, parts2.count >= 4 else { return false }

                    switch selectedSortOption {
                    case .newest:
                        let date1 = Double(parts1[0]) ?? 0
                        let date2 = Double(parts2[0]) ?? 0
                        return date1 > date2
                    case .oldest:
                        let date1 = Double(parts1[0]) ?? 0
                        let date2 = Double(parts2[0]) ?? 0
                        return date1 < date2
                    case .alphabetical:
                        return parts1[1].localizedCaseInsensitiveCompare(parts2[1])
                            == .orderedAscending
                    }
                }
        } else {
            // Fall back to original AppStorage-based implementation
            let incidents = watchIncidents.split(separator: ";").enumerated().map {
                (index: $0.offset, entry: String($0.element))
            }

            return
                incidents
                .filter { incident in
                    let parts = incident.entry.split(
                        separator: "|", omittingEmptySubsequences: false
                    ).map { String($0) }
                    guard parts.count >= 4 else { return false }

                    let date = Date(timeIntervalSince1970: Double(parts[0]) ?? 0)

                    // Date filter only
                    let passesDateFilter: Bool
                    switch selectedDateFilter {
                    case .all:
                        passesDateFilter = true
                    case .today:
                        passesDateFilter = Calendar.current.isDateInToday(date)
                    case .thisWeek:
                        passesDateFilter = Calendar.current.isDate(
                            date, equalTo: Date(), toGranularity: .weekOfYear)
                    case .thisMonth:
                        passesDateFilter = Calendar.current.isDate(
                            date, equalTo: Date(), toGranularity: .month)
                    }

                    return passesDateFilter
                }
                .sorted { incident1, incident2 in
                    let parts1 = incident1.entry.split(
                        separator: "|", omittingEmptySubsequences: false
                    ).map { String($0) }
                    let parts2 = incident2.entry.split(
                        separator: "|", omittingEmptySubsequences: false
                    ).map { String($0) }

                    guard parts1.count >= 4, parts2.count >= 4 else { return false }

                    switch selectedSortOption {
                    case .newest:
                        let date1 = Double(parts1[0]) ?? 0
                        let date2 = Double(parts2[0]) ?? 0
                        return date1 > date2
                    case .oldest:
                        let date1 = Double(parts1[0]) ?? 0
                        let date2 = Double(parts2[0]) ?? 0
                        return date1 < date2
                    case .alphabetical:
                        return parts1[1].localizedCaseInsensitiveCompare(parts2[1])
                            == .orderedAscending
                    }
                }
        }
    }

    // Helper to convert Firestore Incident to AppStorage string format for UI compatibility
    private func firestoreIncidentToString(_ incident: FirebaseManager.Incident) -> String {
        let timestamp = incident.date.timeIntervalSince1970
        let title = incident.title
        let description = incident.description ?? ""
        let showOnHome = incident.showOnHome ? "1" : "0"
        return "\(timestamp)|\(title)|\(description)|\(showOnHome)"
    }

    // Computed properties for checking if incidents exist
    private var hasActiveIncidents: Bool {
        if useFirestoreData {
            return !firestoreIncidents.isEmpty
        } else {
            return !watchIncidents.isEmpty
        }
    }

    private var hasArchivedIncidents: Bool {
        if useFirestoreData {
            return !firestoreArchivedIncidents.isEmpty
        } else {
            return !archivedIncidents.isEmpty
        }
    }

    // Computed property to handle edit sheet binding
    private var editSheetBinding: Binding<Bool> {
        Binding<Bool>(
            get: { showEditIncidentSheet },
            set: { newValue in
                if newValue && editingIncidentIndex != nil {
                    // Already set by onEdit closure
                } else if newValue, let selected = selectedIncident {
                    editingIncidentIndex = selected.idx
                    editingIncidentTitle = selected.title
                    editingIncidentDescription = selected.description
                    editingIncidentDate = selected.date
                }
                showEditIncidentSheet = newValue
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background Image Implementation
                WatchBackgroundView()
                    .ignoresSafeArea(.all)  // This will extend behind navigation bars

                mainContent
                    .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 800 : .infinity)
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("NeighbourHUB Watch")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.clear, for: .navigationBar)  // Make navigation bar transparent
            .toolbarBackground(.clear, for: .tabBar)  // Make tab bar transparent if present
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EmptyView()
                }
            }
        }
        .navigationViewStyle(.stack)  // Force single-column on iPad
        .onAppear {
            // Start Firestore listeners when view appears
            startFirestoreListeners()
        }
        .onDisappear {
            // Stop Firestore listeners when view disappears
            stopFirestoreListeners()
        }
        .fullScreenCover(isPresented: $showWebPortal) {
            WatchWebPortalView(urlString: "http://wf3nhw.ddns.net")
        }
        .fullScreenCover(isPresented: $showIncidentSheet) {
            AddIncidentReportSheet(onSubmit: { title, description, date, showOnHome, imageData, location in
                // Build an Incident model and attempt Firestore write. Fall back to AppStorage if it fails.
                print("🖼️ Creating incident with imageData: \(imageData != nil ? "✅ YES (\(imageData!.count) bytes)" : "❌ NO")")
                print("📍 Location: \(location ?? "Not provided")")
                let incident = FirebaseManager.Incident(
                    id: UUID(), title: title, description: description, date: date,
                    showOnHome: showOnHome,
                    creatorName: UserDefaults.standard.string(forKey: "userName"),
                    creatorSurname: UserDefaults.standard.string(forKey: "userSurname"),
                    archivedAt: nil, incidentType: nil, location: location,
                    contactName: nil, contactPhone: nil, metadata: nil,
                    imageURL: nil, imageData: imageData, imageLocalPath: nil)
                FirebaseManager.shared.createOrUpdateIncident(incident) { error, _ in
                    if let error = error {
                        print("❌ Failed to create incident in Firestore: \(error.localizedDescription)")
                    } else {
                        print("✅ Incident created successfully in Firestore with imageData: \(imageData != nil)")
                    }
                    // Whether Firestore succeeded or failed we keep an optimistic local copy
                    // so the UI updates immediately; the snapshot listener will reconcile later.
                    let newIncident =
                        "\(date.timeIntervalSince1970)|\(title)|\(description)|\(showOnHome ? "1" : "0")"
                    if watchIncidents.isEmpty {
                        watchIncidents = newIncident
                    } else {
                        watchIncidents = newIncident + ";" + watchIncidents
                    }
                }
            })
        }
        .fullScreenCover(isPresented: $showTelegramWeb) {
            WatchWebPortalView(urlString: "https://web.t.me/+zHsCWuIUhoJhY2Jk/media")
        }
        .fullScreenCover(isPresented: $showWatchSettings) {
            WatchSettingsView()
        }
        .fullScreenCover(isPresented: editSheetBinding) {
            AddIncidentReportSheet(
                initialTitle: editingIncidentTitle,
                initialDescription: editingIncidentDescription,
                initialDate: editingIncidentDate,
                initialShowOnHome: editingIncidentShowOnHome,
                initialLocation: editingIncidentLocation,
                isEditing: true,
                onSubmit: { title, description, date, showOnHome, imageData, location in
                    // Attempt to update/create incident in Firestore; keep AppStorage updated optimistically
                    if editingIncidentIndex != nil {
                        editingIncidentTitle = title
                        editingIncidentDescription = description
                        editingIncidentDate = date
                        editingIncidentShowOnHome = showOnHome
                        editingIncidentLocation = location ?? ""

                        // Use the existing incident ID if available (from Firestore), otherwise create new
                        let incidentID = editingIncidentID ?? UUID()
                        
                        let incident = FirebaseManager.Incident(
                            id: incidentID, title: title, description: description, date: date,
                            showOnHome: showOnHome,
                            creatorName: UserDefaults.standard.string(forKey: "userName"),
                            creatorSurname: UserDefaults.standard.string(forKey: "userSurname"),
                            archivedAt: nil, incidentType: nil, location: location,
                            contactName: nil, contactPhone: nil, metadata: nil,
                            imageURL: nil, imageData: imageData,
                            imageLocalPath: nil)
                        FirebaseManager.shared.createOrUpdateIncident(incident) { _, _ in
                            // Update local cache optimistically; the Firestore watcher will reconcile any differences.
                            updateIncident()
                        }
                    }
                }
            )
            .id(editingIncidentIndex ?? -1)
        }
        .alert("Delete Incident", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let index = incidentToDelete {
                    if showArchived {
                        // When viewing archived reports, Delete should permanently remove the archived doc
                        deleteArchivedIncident(at: index)
                    } else {
                        // When viewing active reports, Delete should remove the incident (permanent)
                        deleteIncident(at: index)
                    }
                    incidentToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                incidentToDelete = nil
            }
        } message: {
            if showArchived {
                Text(
                    "This will permanently delete the incident report. This action cannot be undone."
                )
            } else {
                Text(
                    "This will permanently delete the incident report. Use Archive from the menu to archive instead."
                )
            }
        }
        // Enhanced bulk action dialog
        .confirmationDialog(
            "Bulk Actions",
            isPresented: $showBulkActionSheet,
            titleVisibility: .visible
        ) {
            Button("🗂️ Archive Selected (\(selectedIncidentIDs.count))") {
                performBulkArchive()
            }

            Button("🗑️ Delete Selected (\(selectedIncidentIDs.count))", role: .destructive) {
                showBulkDeleteConfirmation = true
            }

            Button("Cancel", role: .cancel) {
                // Keep selection for further actions
            }
        } message: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Choose an action for \(selectedIncidentIDs.count) selected incident report\(selectedIncidentIDs.count == 1 ? "" : "s"):"
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
                "Delete \(selectedIncidentIDs.count) Report\(selectedIncidentIDs.count == 1 ? "" : "s")",
                role: .destructive
            ) {
                performBulkDelete()
            }
        } message: {
            Text(
                "This will permanently delete \(selectedIncidentIDs.count) incident report\(selectedIncidentIDs.count == 1 ? "" : "s"). This action cannot be undone.\n\nConsider using Archive instead to preserve the reports for future reference."
            )
        }
        // Success feedback alert
        .alert(successMessage, isPresented: $showSuccessMessage) {
            Button("OK") {}
        }
    }

    // MARK: - Firestore Listeners
    private func startFirestoreListeners() {
        // Watch active incidents
        FirebaseManager.shared.watchIncidents { incidents in
            DispatchQueue.main.async {
                self.firestoreIncidents = incidents.filter { $0.archivedAt == nil }
                print(
                    "WatchView: Received \(self.firestoreIncidents.count) active incidents from Firestore"
                )
            }
        }

        // Watch archived incidents
        FirebaseManager.shared.watchArchivedIncidents { archivedIncidents in
            DispatchQueue.main.async {
                self.firestoreArchivedIncidents = archivedIncidents
                print(
                    "WatchView: Received \(self.firestoreArchivedIncidents.count) archived incidents from Firestore"
                )
            }
        }
    }

    private func stopFirestoreListeners() {
        FirebaseManager.shared.stopWatchingIncidents()
        FirebaseManager.shared.stopWatchingArchivedIncidents()
    }

    // MARK: - Main Content View
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 16) {
            // Quick Actions Row - positioned below navigation title
            if isAdmin {
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        WatchGlassCard(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.18), Color.red.opacity(0.10),
                            ]),
                            borderGradient: Gradient(colors: [
                                Color.white.opacity(0.7), Color.orange.opacity(0.2),
                            ]),
                            shadowColor1: Color.orange.opacity(0.18),
                            shadowColor2: Color.red.opacity(0.10),
                            text: "Add Incident",
                            textColor: .primary,
                            action: { showIncidentSheet = true },
                            height: 48
                        )
                        WatchGlassCard(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.18), Color.cyan.opacity(0.10),
                            ]),
                            borderGradient: Gradient(colors: [
                                Color.white.opacity(0.7), Color.blue.opacity(0.2),
                            ]),
                            shadowColor1: Color.blue.opacity(0.18),
                            shadowColor2: Color.cyan.opacity(0.10),
                            text: "Telegram Alerts",
                            textColor: .primary,
                            action: { showTelegramWeb = true },
                            height: 48
                        )
                    }

                    WatchGlassCard(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.18), Color.blue.opacity(0.10),
                        ]),
                        borderGradient: Gradient(colors: [
                            Color.white.opacity(0.7), Color.purple.opacity(0.2),
                        ]),
                        shadowColor1: Color.purple.opacity(0.18),
                        shadowColor2: Color.blue.opacity(0.10),
                        text: "Camera Portal",
                        textColor: .primary,
                        action: { showWebPortal = true },
                        height: 48
                    )
                }
                .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 16)
                .padding(.top, 16)  // Add top padding to position below nav title
            } else if isWatchUser {
                VStack(spacing: 14) {
                    WatchGlassCard(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.18), Color.cyan.opacity(0.10),
                        ]),
                        borderGradient: Gradient(colors: [
                            Color.white.opacity(0.7), Color.blue.opacity(0.2),
                        ]),
                        shadowColor1: Color.blue.opacity(0.18),
                        shadowColor2: Color.cyan.opacity(0.10),
                        text: "Telegram Alerts",
                        textColor: .primary,
                        action: { showTelegramWeb = true },
                        height: 48
                    )

                    WatchGlassCard(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.18), Color.blue.opacity(0.10),
                        ]),
                        borderGradient: Gradient(colors: [
                            Color.white.opacity(0.7), Color.purple.opacity(0.2),
                        ]),
                        shadowColor1: Color.purple.opacity(0.18),
                        shadowColor2: Color.blue.opacity(0.10),
                        text: "Camera Portal",
                        textColor: .primary,
                        action: { showWebPortal = true },
                        height: 48
                    )
                }
                .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 16)
                .padding(.top, 16)  // Add top padding to position below nav title
            } else {
                // User has camera access permission but needs to set credentials
                VStack(spacing: 16) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        .padding(.top, 24)
                    
                    Text("Camera Access Granted")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Set your camera credentials to access the camera portal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(action: { showWatchSettings = true }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                            Text("Open Settings")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: 200)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.blue)
                            Text("Tap 'Open Settings' above")
                                .font(.caption)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(.blue)
                            Text("Enter your camera username and password")
                                .font(.caption)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "3.circle.fill")
                                .foregroundColor(.blue)
                            Text("Return here to access camera portal")
                                .font(.caption)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
                .padding(.top, 16)
            }

            // Archive Toggle (always visible for watch users and admins)
            if isAdmin || isWatchUser {
                HStack {
                    Text("Reports")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(colorScheme == .dark ? .primary : .black)
                        .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)  // White shadow for better contrast in light mode

                    Spacer()

                    // Bulk manage button for admin users
                    if isAdmin && !showArchived && hasActiveIncidents {
                        Button(action: {
                            if isSelectingBulk {
                                isSelectingBulk = false
                                selectedIncidentIDs.removeAll()
                            } else {
                                isSelectingBulk = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(
                                    systemName: isSelectingBulk ? "checkmark.circle" : "checklist"
                                )
                                .foregroundColor(isSelectingBulk ? .orange : .blue)
                                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                                Text(isSelectingBulk ? "Done" : "Manage")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(isSelectingBulk ? .orange : .blue)
                                    .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    if colorScheme == .dark {
                                        Color.blue.opacity(0.1)
                                    } else {
                                        Color.white.opacity(0.9)
                                    }
                                }
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        (isSelectingBulk ? Color.orange : Color.blue).opacity(0.3),
                                        lineWidth: 1)
                            )
                        }
                    }

                    // Bulk actions button (only show when selecting)
                    if isSelectingBulk && !selectedIncidentIDs.isEmpty {
                        Button(action: {
                            showBulkActionSheet = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "ellipsis.circle.fill")
                                    .foregroundColor(.orange)
                                    .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                                Text("(\(selectedIncidentIDs.count))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                    .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    if colorScheme == .dark {
                                        Color.orange.opacity(0.1)
                                    } else {
                                        Color.white.opacity(0.9)
                                    }
                                }
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    // Archive toggle (for all users)
                    Button(action: { showArchived.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showArchived ? "tray.full" : "archivebox")
                                .foregroundColor(colorScheme == .dark ? .gray : .black)
                                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                            Text(showArchived ? "Active" : "Archive")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(colorScheme == .dark ? .gray : .black)
                                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                if colorScheme == .dark {
                                    Color.gray.opacity(0.1)
                                } else {
                                    Color.white.opacity(0.9)
                                }
                            }
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.gray.opacity(0.3) : Color.black.opacity(0.2),
                                    lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            // Scrollable Incident Notices Section
            if (isAdmin || isWatchUser)
                && ((hasActiveIncidents && !showArchived) || (hasArchivedIncidents && showArchived))
            {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Filter and Sort Header
                        HStack {
                            Text(showArchived ? "Archived Reports" : "Incident Reports")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(colorScheme == .dark ? .secondary : .black)
                                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)

                            Spacer()

                            // Filter button (only for active reports)
                            if !showArchived {
                                Button(action: { showFilters.toggle() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "line.3.horizontal.decrease.circle")
                                            .foregroundColor(.blue)
                                            .shadow(
                                                color: .white.opacity(0.6), radius: 1, x: 0, y: 1)
                                        Text("Filter")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                            .shadow(
                                                color: .white.opacity(0.6), radius: 1, x: 0, y: 1)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        ZStack {
                                            if colorScheme == .dark {
                                                Color.blue.opacity(0.1)
                                            } else {
                                                Color.white.opacity(0.9)
                                            }
                                        }
                                    )
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 4)

                        // Filter Controls (when expanded)
                        if showFilters && !showArchived {
                            VStack(spacing: 12) {
                                // Date Filter
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Date Range")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(colorScheme == .dark ? .secondary : .black)
                                        .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)

                                    HStack(spacing: 8) {
                                        ForEach(DateFilter.allCases, id: \.self) { filter in
                                            Button(action: { selectedDateFilter = filter }) {
                                                Text(filter.rawValue)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        selectedDateFilter == filter
                                                            ? Color.blue
                                                            : (colorScheme == .dark
                                                                ? Color.gray.opacity(0.2)
                                                                : Color.white.opacity(0.9))
                                                    )
                                                    .foregroundColor(
                                                        selectedDateFilter == filter
                                                            ? .white
                                                            : (colorScheme == .dark
                                                                ? .primary : .black)
                                                    )
                                                    .cornerRadius(6)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(
                                                                selectedDateFilter == filter
                                                                    ? Color.blue.opacity(0.5)
                                                                    : Color.gray.opacity(0.3),
                                                                lineWidth: 1)
                                                    )
                                            }
                                        }
                                    }
                                }

                                // Sort Options
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Sort By")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(colorScheme == .dark ? .secondary : .black)
                                        .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)

                                    HStack(spacing: 8) {
                                        ForEach(SortOption.allCases, id: \.self) { option in
                                            Button(action: { selectedSortOption = option }) {
                                                Text(option.rawValue)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        selectedSortOption == option
                                                            ? Color.purple
                                                            : (colorScheme == .dark
                                                                ? Color.gray.opacity(0.2)
                                                                : Color.white.opacity(0.9))
                                                    )
                                                    .foregroundColor(
                                                        selectedSortOption == option
                                                            ? .white
                                                            : (colorScheme == .dark
                                                                ? .primary : .black)
                                                    )
                                                    .cornerRadius(6)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(
                                                                selectedSortOption == option
                                                                    ? Color.purple.opacity(0.5)
                                                                    : Color.gray.opacity(0.3),
                                                                lineWidth: 1)
                                                    )
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(.systemGray6).opacity(0.8))
                            .cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Results count
                        HStack {
                            if showArchived {
                                Text(
                                    "\(archivedIncidentsList.count) archived report\(archivedIncidentsList.count == 1 ? "" : "s")"
                                )
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(colorScheme == .dark ? .secondary : .black)
                                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                            } else {
                                Text(
                                    "\(filteredIncidents.count) report\(filteredIncidents.count == 1 ? "" : "s")"
                                )
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(colorScheme == .dark ? .secondary : .black)
                                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        // Incident Lists
                        if showArchived {
                            // Archived Incidents List
                            ForEach(archivedIncidentsList, id: \.index) { archived in
                                // If using Firestore data, construct detail params from the firestoreArchivedIncidents array.
                                if useFirestoreData
                                    && archived.index < firestoreArchivedIncidents.count
                                {
                                    let inc = firestoreArchivedIncidents[archived.index]
                                    let title = inc.title
                                    let description = inc.description ?? ""
                                    let date = inc.date
                                    let archivedDate = inc.archivedAt ?? Date()
                                    let showOnHome = inc.showOnHome

                                    NavigationLink(
                                        destination: IncidentDetailView(
                                            idx: archived.index,
                                            title: title,
                                            description: description,
                                            date: date,
                                            imageURL: inc.imageURL,
                                            imageData: inc.imageData,
                                            uploaderName: inc.creatorName,
                                            uploaderSurname: inc.creatorSurname,
                                            incidentType: inc.incidentType,
                                            location: inc.location,
                                            contactName: inc.contactName,
                                            contactPhone: inc.contactPhone,
                                            metadata: inc.metadata,
                                            isAdmin: isAdmin,
                                            onEdit: nil,
                                            onArchive: nil,
                                            onDelete: isAdmin
                                                ? {
                                                    incidentToDelete = archived.index
                                                    showDeleteConfirmation = true
                                                } : nil
                                        )
                                    ) {
                                        ArchivedIncidentNotice(
                                            title: title,
                                            description: description,
                                            date: date,
                                            archivedDate: archivedDate,
                                            showOnHome: showOnHome,
                                            onRestore: {
                                                restoreIncident(at: archived.index)
                                            },
                                            onDelete: {
                                                incidentToDelete = archived.index
                                                showDeleteConfirmation = true
                                            },
                                            isAdmin: isAdmin
                                        )
                                    }
                                } else {
                                    let parts = archived.entry.split(
                                        separator: "|", omittingEmptySubsequences: false
                                    ).map { String($0) }
                                    if parts.count >= 5 {  // Original 4 parts + archive timestamp
                                        let title = parts[1]
                                        let description = parts[2]
                                        let date = Date(
                                            timeIntervalSince1970: Double(parts[0]) ?? 0)
                                        let archivedDate = Date(
                                            timeIntervalSince1970: Double(parts[4]) ?? 0)
                                        let showOnHome = parts[3] == "1"

                                        NavigationLink(
                                            destination: IncidentDetailView(
                                                idx: archived.index,
                                                title: title,
                                                description: description,
                                                date: date,
                                                imageURL: nil,
                                                imageData: nil,
                                                uploaderName: nil,
                                                uploaderSurname: nil,
                                                incidentType: nil,
                                                location: nil,
                                                contactName: nil,
                                                contactPhone: nil,
                                                metadata: nil,
                                                isAdmin: isAdmin,
                                                onEdit: nil,
                                                onArchive: nil,
                                                onDelete: isAdmin
                                                    ? {
                                                        incidentToDelete = archived.index
                                                        showDeleteConfirmation = true
                                                    } : nil
                                            )
                                        ) {
                                            ArchivedIncidentNotice(
                                                title: title,
                                                description: description,
                                                date: date,
                                                archivedDate: archivedDate,
                                                showOnHome: showOnHome,
                                                onRestore: {
                                                    restoreIncident(at: archived.index)
                                                },
                                                onDelete: {
                                                    incidentToDelete = archived.index
                                                    showDeleteConfirmation = true
                                                },
                                                isAdmin: isAdmin
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            // Active Filtered Incident List
                            ForEach(filteredIncidents, id: \.index) { incident in
                                let parts = incident.entry.split(
                                    separator: "|", omittingEmptySubsequences: false
                                ).map { String($0) }
                                if parts.count >= 4 {
                                    let title = parts[1]
                                    let description = parts[2]
                                    let date = Date(timeIntervalSince1970: Double(parts[0]) ?? 0)
                                    let showOnHome = parts[3] == "1"
                                    // Get the incident ID for bulk selection
                                    let incidentID: UUID =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].id : UUID()

                                    // Determine optional imageURL when using Firestore-backed data
                                    let optionalImageURL: URL? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].imageURL : nil
                                    let optionalImageData: Data? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].imageData : nil
                                    let optionalCreatorName: String? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].creatorName : nil
                                    let optionalCreatorSurname: String? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].creatorSurname : nil
                                    let optionalIncidentType: String? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].incidentType : nil
                                    let optionalLocation: String? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].location : nil
                                    let optionalContactName: String? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].contactName : nil
                                    let optionalContactPhone: String? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].contactPhone : nil
                                    let optionalMetadata: [String: String]? =
                                        (useFirestoreData
                                            && incident.index < firestoreIncidents.count)
                                        ? firestoreIncidents[incident.index].metadata : nil

                                    if isSelectingBulk && isAdmin {
                                        // Bulk selection mode - show checkbox and incident card
                                        HStack(spacing: 12) {
                                            Button(action: {
                                                if selectedIncidentIDs.contains(incidentID) {
                                                    selectedIncidentIDs.remove(incidentID)
                                                } else {
                                                    selectedIncidentIDs.insert(incidentID)
                                                }
                                            }) {
                                                Image(
                                                    systemName: selectedIncidentIDs.contains(
                                                        incidentID)
                                                        ? "checkmark.circle.fill" : "circle"
                                                )
                                                .font(.title2)
                                                .foregroundColor(
                                                    selectedIncidentIDs.contains(incidentID)
                                                        ? .orange : .secondary)
                                            }
                                            .buttonStyle(PlainButtonStyle())

                                            WatchIncidentNotice(
                                                title: title,
                                                description: description,
                                                date: date,
                                                showOnHome: showOnHome,
                                                onArchive: nil,  // Disable individual actions in bulk mode
                                                onDelete: nil
                                            )
                                            .background(
                                                selectedIncidentIDs.contains(incidentID)
                                                    ? Color.orange.opacity(0.1)
                                                    : Color.clear
                                            )
                                            .cornerRadius(12)
                                        }
                                    } else {
                                        // Normal mode - show navigation link
                                        NavigationLink(
                                            destination: IncidentDetailView(
                                                idx: incident.index,
                                                title: title,
                                                description: description,
                                                date: date,
                                                imageURL: optionalImageURL,
                                                imageData: optionalImageData,
                                                uploaderName: optionalCreatorName,
                                                uploaderSurname: optionalCreatorSurname,
                                                incidentType: optionalIncidentType,
                                                location: optionalLocation,
                                                contactName: optionalContactName,
                                                contactPhone: optionalContactPhone,
                                                metadata: optionalMetadata,
                                                isAdmin: isAdmin,
                                                onEdit: {
                                                    editingIncidentIndex = incident.index
                                                    editingIncidentID = incidentID  // Capture the incident ID
                                                    editingIncidentTitle = title
                                                    editingIncidentDescription = description
                                                    editingIncidentDate = date
                                                    editingIncidentShowOnHome = showOnHome
                                                    editingIncidentLocation = optionalLocation ?? ""
                                                    showEditIncidentSheet = true
                                                },
                                                onArchive: isAdmin
                                                    ? {
                                                        archiveIncident(at: incident.index)
                                                    } : nil,
                                                onDelete: isAdmin
                                                    ? {
                                                        incidentToDelete = incident.index
                                                        showDeleteConfirmation = true
                                                    } : nil
                                            ),
                                            label: {
                                                WatchIncidentNotice(
                                                    title: title,
                                                    description: description,
                                                    date: date,
                                                    showOnHome: showOnHome,
                                                    onArchive: isAdmin
                                                        ? {
                                                            archiveIncident(at: incident.index)
                                                        } : nil,
                                                    onDelete: isAdmin
                                                        ? {
                                                            incidentToDelete = incident.index
                                                            showDeleteConfirmation = true
                                                        } : nil
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                    .animation(.easeInOut(duration: 0.3), value: showFilters)
                }
            } else if isAdmin || isWatchUser {
                // Show message when no reports are available
                VStack(spacing: 12) {
                    Image(systemName: showArchived ? "archivebox" : "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(
                            colorScheme == .dark ? .gray.opacity(0.6) : .black.opacity(0.7)
                        )
                        .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 2)

                    Text(showArchived ? "No Archived Reports" : "No Incident Reports")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .dark ? .secondary : .black)
                        .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)

                    Text(
                        showArchived
                            ? "Archived reports will appear here when incidents are archived."
                            : "Incident reports will appear here when they are submitted."
                    )
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .gray : .black.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 18)
    }
}

// MARK: - WatchGlassCard
struct WatchGlassCard: View {
    var gradient: Gradient
    var borderGradient: Gradient
    var shadowColor1: Color
    var shadowColor2: Color
    var icon: Image? = nil
    var text: String
    var textColor: Color
    var action: () -> Void
    var height: CGFloat = 48
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        LinearGradient(
                            gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .blur(radius: 0.5)

                // Enhanced text readability overlay
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1)
                    )

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            gradient: borderGradient, startPoint: .topLeading,
                            endPoint: .bottomTrailing), lineWidth: 1.5
                    )
                    .shadow(color: shadowColor1, radius: 16, x: 0, y: 8)
                    .shadow(color: shadowColor2, radius: 8, x: 0, y: 2)

                HStack {
                    if let icon = icon {
                        icon
                            .font(.title2)
                            .foregroundColor(.blue)
                            .padding(.trailing, 8)
                    }
                    Text(text)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)  // Text shadow for better visibility
                }
                .padding(.vertical, 4)
            }
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.2 : 0.12), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - WatchIncidentNotice
struct WatchIncidentNotice: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let description: String
    let date: Date
    let showOnHome: Bool
    let onArchive: (() -> Void)?
    let onDelete: (() -> Void)?

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(showOnHome ? Color.orange : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(
                                showOnHome ? Color.orange.opacity(0.3) : Color.gray.opacity(0.5),
                                lineWidth: 8
                            )
                            .frame(width: 16, height: 16)
                    )
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(colorScheme == .dark ? .primary : .black)
                        .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                        .lineLimit(1)

                    Spacer()

                    if showOnHome {
                        Image(systemName: "house.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                    }
                }

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .secondary : .gray)
                    .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text(timeAgo)
                        .font(.caption)
                        .foregroundColor(colorScheme == .dark ? .gray : .secondary)
                        .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)

                    Spacer()

                    // Archive/Delete buttons for admins
                    if let onArchive = onArchive {
                        Button(action: onArchive) {
                            Image(systemName: "archivebox")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                                .padding(8)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }

                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 1)
                                .padding(8)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
        }
        .padding()
        .background(
            ZStack {
                Color(UIColor.secondarySystemGroupedBackground)
                // Enhanced background for better text visibility
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(colorScheme == .dark ? 0.3 : 0.2)

                // Subtle color overlay to maintain app theme
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - ArchivedIncidentNotice
struct ArchivedIncidentNotice: View {
    let title: String
    let description: String
    let date: Date
    let archivedDate: Date
    let showOnHome: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    let isAdmin: Bool

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var archivedTimeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Archived " + formatter.localizedString(for: archivedDate, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            // Archived status indicator
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.5), lineWidth: 8)
                            .frame(width: 16, height: 16)
                    )
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .strikethrough()

                    Spacer()

                    Image(systemName: "archivebox.fill")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Original: \(timeAgo)")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(archivedTimeAgo)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                if isAdmin {
                    HStack(spacing: 8) {
                        Button(action: onRestore) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Restore")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Spacer()

                        Button(action: onDelete) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(
            ZStack {
                Color(UIColor.tertiarySystemGroupedBackground)
                // Enhanced background for better text visibility
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
            }
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 0.5)
        )
        .opacity(0.7)
    }
}  // MARK: - AddIncidentReportSheet
struct AddIncidentReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialTitle: String = ""
    var initialDescription: String = ""
    var initialDate: Date = Date()
    var initialShowOnHome: Bool = false
    var initialLocation: String = ""
    var isEditing: Bool = false
    var onSubmit: ((String, String, Date, Bool, Data?, String?) -> Void)? = nil

    @State private var title: String
    @State private var description: String
    @State private var showOnHome: Bool
    @State private var date: Date
    @State private var location: String
    @State private var evidenceImage: UIImage?
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera

    init(
        initialTitle: String = "", initialDescription: String = "", initialDate: Date = Date(),
        initialShowOnHome: Bool = false, initialLocation: String = "", isEditing: Bool = false,
        onSubmit: ((String, String, Date, Bool, Data?, String?) -> Void)? = nil
    ) {
        self.initialTitle = initialTitle
        self.initialDescription = initialDescription
        self.initialDate = initialDate
        self.initialShowOnHome = initialShowOnHome
        self.initialLocation = initialLocation
        self.isEditing = isEditing
        self.onSubmit = onSubmit
        _title = State(initialValue: initialTitle)
        _description = State(initialValue: initialDescription)
        _date = State(initialValue: initialDate)
        _showOnHome = State(initialValue: initialShowOnHome)
        _location = State(initialValue: initialLocation)
    }

    @FocusState private var focusedField: Field?
    enum Field: Hashable { case title, description, location }
    var body: some View {
        ZStack(alignment: .top) {
            // Enhanced background for better contrast
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemGroupedBackground),
                    Color(.systemBackground).opacity(0.9),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 48, height: 6)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                NavigationView {
                    Form {
                        Section(header: Text("Incident Title")) {
                            SmartTextField(
                                "Title",
                                text: $title,
                                keyboardType: .default,
                                autocapitalization: .words,
                                autocorrection: false,
                                submitLabel: .next,
                                onFocusChange: { focused in
                                    if !focused {
                                        focusedField = .description
                                    }
                                }
                            )
                            .focused($focusedField, equals: .title)
                        }
                        Section(header: Text("Description")) {
                            ScrollView {
                                SmartTextEditor(
                                    text: $description,
                                    placeholder: "Describe the incident...",
                                    minHeight: 120,
                                    autocapitalization: .sentences,
                                    autocorrection: false,
                                    onFocusChange: { focused in
                                        if focused {
                                            focusedField = .description
                                        }
                                    }
                                )
                                .focused($focusedField, equals: .description)
                            }
                            .scrollDismissesKeyboard(.interactively)
                        }

                        Section(header: Text("Location")) {
                            SmartTextField(
                                "Location (e.g., 123 Main St, or Gate 5)",
                                text: $location,
                                keyboardType: .default,
                                autocapitalization: .words,
                                autocorrection: false,
                                submitLabel: .done,
                                onFocusChange: { focused in
                                    if focused {
                                        focusedField = .location
                                    }
                                }
                            )
                            .focused($focusedField, equals: .location)
                        }

                        Section(header: Text("Evidence Photo")) {
                            VStack(spacing: 12) {
                                if let image = evidenceImage {
                                    VStack(spacing: 8) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 200)
                                            .clipped()
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color(.systemGray4), lineWidth: 1)
                                            )

                                        Button("Remove Photo") {
                                            evidenceImage = nil
                                        }
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    }
                                }

                                HStack(spacing: 12) {
                                    Button(action: {
                                        imagePickerSource = .camera
                                        // Small delay to ensure state updates before sheet presentation
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            showImagePicker = true
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "camera")
                                            Text("Camera")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }

                                    Button(action: {
                                        imagePickerSource = .photoLibrary
                                        // Small delay to ensure state updates before sheet presentation
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            showImagePicker = true
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "photo.on.rectangle")
                                            Text("Gallery")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }

                        Section(header: Text("Date & Time")) {
                            VStack(spacing: 12) {
                                // Date picker with enhanced visibility
                                DatePicker(
                                    "Select Date & Time", selection: $date,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(.systemGray5), lineWidth: 1)
                                        )
                                )

                                // Alternative compact picker for comparison
                                HStack {
                                    Text("Quick Select:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    DatePicker(
                                        "", selection: $date,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .datePickerStyle(.compact)
                                    .accentColor(.blue)
                                    .scaleEffect(1.1)  // Make it slightly larger
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                )
                            }
                        }
                        Section {
                            Button(isEditing ? "Save Changes" : "Submit") {
                                // Compress image for Firestore storage (instant loading)
                                let imageData = evidenceImage?.compressedForFirestore()
                                if let onSubmit = onSubmit {
                                    let locationToSubmit = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location
                                    onSubmit(title, description, date, showOnHome, imageData, locationToSubmit)
                                }
                                dismiss()
                            }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .scrollContentBackground(.hidden)  // Hide default form background
                    .navigationTitle(isEditing ? "Edit Incident" : "Add Incident Report")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { focusedField = nil }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showImagePicker) {
            IncidentImagePicker(image: $evidenceImage, sourceType: imagePickerSource)
        }
    }
}

// MARK: - WatchWebPortalView (Wrapper for WebView)
struct WatchWebPortalView: View {
    let urlString: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var webViewModel = WebViewModel()
    @AppStorage("watchUsername") private var watchUsername: String = ""
    @AppStorage("watchPassword") private var watchPassword: String = ""
    var body: some View {
        NavigationView {
            ZStack {
                WebViewContainer(
                    url: URL(string: urlString)!,
                    viewModel: webViewModel,
                    injectedUsername: watchUsername,
                    injectedPassword: watchPassword
                )
                if webViewModel.isLoading {
                    Color.black.opacity(0.05).ignoresSafeArea()
                    ProgressView("Loading...")
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground))
                        )
                        .shadow(radius: 8)
                }
                if let error = webViewModel.error {
                    Color.black.opacity(0.05).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Failed to load page")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            webViewModel.reload()
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
                    .shadow(radius: 8)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

}// MARK: - WebViewModel & WebViewContainer (for WatchWebPortalView)
class WebViewModel: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var error: String? = nil
    fileprivate var webView: WKWebView?
    private var url: URL?
    func setWebView(_ webView: WKWebView, url: URL) {
        self.webView = webView
        self.url = url
    }
    func reload() {
        guard let webView = webView, let url = url else { return }
        error = nil
        isLoading = true
        webView.load(URLRequest(url: url))
    }
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    @ObservedObject var viewModel: WebViewModel
    var injectedUsername: String? = nil
    var injectedPassword: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel, injectedUsername: injectedUsername,
            injectedPassword: injectedPassword)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        viewModel.setWebView(webView, url: url)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let viewModel: WebViewModel
        let injectedUsername: String?
        let injectedPassword: String?
        init(viewModel: WebViewModel, injectedUsername: String?, injectedPassword: String?) {
            self.viewModel = viewModel
            self.injectedUsername = injectedUsername
            self.injectedPassword = injectedPassword
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)
        {
            DispatchQueue.main.async {
                self.viewModel.isLoading = true
                self.viewModel.error = nil
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
            }
            // Inject credentials if available
            if let username = injectedUsername, let password = injectedPassword, !username.isEmpty,
                !password.isEmpty
            {
                let safeUsername = username.replacingOccurrences(of: "'", with: "\\'")
                let safePassword = password.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                    (function() {
                        var userField = document.querySelector('input[type="text"], input[name*="user"], input[name*="login"]');
                        var passField = document.querySelector('input[type="password"]');
                        if (userField && passField) {
                            userField.value = '\(safeUsername)';
                            passField.value = '\(safePassword)';
                            // Toggle 'log in automatically' if present and persist in localStorage
                            var autoLogin = document.querySelector('input[type="checkbox"][name*="auto"], input[type="checkbox"][id*="auto"], input[type="checkbox"][value*="auto"]');
                            if (autoLogin) {
                                if (!autoLogin.checked) {
                                    autoLogin.checked = true;
                                    var evt = document.createEvent('HTMLEvents');
                                    evt.initEvent('change', true, true);
                                    autoLogin.dispatchEvent(evt);
                                }
                                // Remember this setting for future visits
                                try {
                                    if (autoLogin.name) {
                                        localStorage.setItem('autoLogin_' + autoLogin.name, 'yes');
                                    } else if (autoLogin.id) {
                                        localStorage.setItem('autoLogin_' + autoLogin.id, 'yes');
                                    } else {
                                        localStorage.setItem('autoLogin', 'yes');
                                    }
                                } catch (e) {}
                            }
                            // Optionally submit the form automatically:
                            var form = userField.form || passField.form;
                            if (form) { form.dispatchEvent(new Event('submit', {bubbles:true, cancelable:true})); }
                        }
                    })();
                    """
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
        ) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                self.viewModel.error = error.localizedDescription
            }
        }
        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                self.viewModel.error = error.localizedDescription
            }
        }
    }
}

// MARK: - WatchBackgroundView
struct WatchBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Fallback color background
            Color.appBackground

            // Original background image with enhanced readability overlays
            Image("watch-background")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .opacity(colorScheme == .dark ? 0.2 : 0.25)
                .overlay(
                    // Multi-layer gradient overlay for maximum text readability
                    ZStack {
                        // Primary contrast overlay
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(colorScheme == .dark ? 0.6 : 0.4),
                                Color.black.opacity(colorScheme == .dark ? 0.4 : 0.25),
                                Color.black.opacity(colorScheme == .dark ? 0.6 : 0.4),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        // Additional blur overlay for content areas
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(colorScheme == .dark ? 0.3 : 0.2)

                        // Subtle color overlay to maintain app theme
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.blue.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                )
        }
    }
}

// MARK: - IncidentDetailView
struct IncidentDetailView: View {
    let idx: Int
    let title: String
    let description: String
    let date: Date
    let imageURL: URL?
    let imageData: Data?  // Add imageData parameter
    let uploaderName: String?
    let uploaderSurname: String?
    // New detailed fields
    let incidentType: String?
    let location: String?
    let contactName: String?
    let contactPhone: String?
    let metadata: [String: String]?
    let isAdmin: Bool
    let onEdit: (() -> Void)?
    let onArchive: (() -> Void)?
    let onDelete: (() -> Void)?

    @State private var showFullScreenImage = false
    @State private var showMapChoice: Bool = false
    @State private var pendingAddress: String? = nil
    @State private var showContactChoice: Bool = false
    @State private var pendingContact: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundColor(.orange.opacity(0.7))
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(date, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onAppear {
                    print("📸 IncidentDetailView for '\(title)':")
                    print("   incidentType: \(incidentType ?? "nil")")
                    print("   imageURL: \(imageURL?.absoluteString ?? "nil")")
                    print("   imageData: \(imageData != nil ? "✅ YES (\(imageData!.count) bytes)" : "❌ NO")")
                }
                Divider()

            // Show evidence image if provided (tappable to open fullscreen)
            // Do not show images for Medical or Emergency request types (which contain sensitive personal info)
            // If incidentType is nil, assume it's a generic incident and show the image
            // Handle both imageURL and imageData
            let shouldShowImage: Bool = {
                // If there's no image data/URL, don't show
                guard imageURL != nil || imageData != nil else { return false }
                
                // If type is medical/emergency, don't show (privacy)
                if let type = incidentType?.lowercased(),
                   type == "medical" || type == "emergency" {
                    return false
                }
                
                // Otherwise show the image (includes nil incidentType)
                return true
            }()
            
            if shouldShowImage {
                Button(action: { 
                    print("✅ Showing image fullscreen (incidentType: \(incidentType ?? "generic"), has imageURL: \(imageURL != nil), has imageData: \(imageData != nil))")
                    showFullScreenImage = true 
                }) {
                    Group {
                        // Priority 1: Use imageData if available (instant display)
                        if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipped()
                                .cornerRadius(12)
                        }
                        // Priority 2: Fall back to imageURL (async load)
                        else if let imageURL = imageURL {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                case .success(let img):
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                        .clipped()
                                        .cornerRadius(12)
                                case .failure(_):
                                    ZStack {
                                        Color(.secondarySystemBackground)
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundColor(.gray)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                                    .cornerRadius(12)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 8)
            }

            // Uploader info
            if (uploaderName ?? uploaderSurname) != nil {
                HStack(spacing: 8) {
                    Text("Reported by:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text([uploaderName, uploaderSurname].compactMap { $0 }.joined(separator: " "))
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 6)
            }

            // Incident type and location (if present)
            if let type = incidentType {
                HStack {
                    Text("Type:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(type)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                }
            }

            if let loc = location {
                HStack {
                    Text("Location:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: {
                        pendingAddress = loc
                        showMapChoice = true
                    }) {
                        Text(loc)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
            }

            Text(description)
                .font(.body)
                .foregroundColor(.primary)

            // Contact info
            if (contactName ?? contactPhone) != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Contact details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack {
                        if let cName = contactName { Text(cName).font(.caption) }
                        if let cPhone = contactPhone {
                            Button(action: {
                                pendingContact = cPhone
                                showContactChoice = true
                            }) {
                                Text(cPhone)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.top, 8)
            }

            // Metadata (key: value)
            if let md = metadata, !md.isEmpty {
                let pairs = md.sorted { $0.key < $1.key }
                let named = pairs.map { (key: $0.key, value: $0.value) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(named, id: \.key) { pair in
                        HStack {
                            Text(pair.key + ":")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(pair.value)
                                .font(.caption)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 8)
            }
            }
            .padding()
        }
        .confirmationDialog("Open in…", isPresented: $showMapChoice, titleVisibility: .visible) {
            Button("Google Maps") {
                if let addr = pendingAddress {
                    let encoded =
                        addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let g = URL(string: "comgooglemaps://?q=\(encoded)"),
                        UIApplication.shared.canOpenURL(g)
                    {
                        UIApplication.shared.open(g)
                    } else if let web = URL(string: "https://maps.google.com/?q=\(encoded)") {
                        UIApplication.shared.open(web)
                    }
                }
            }
            Button("Apple Maps") {
                if let addr = pendingAddress {
                    let encoded =
                        addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingAddress = nil }
        }
        .confirmationDialog(
            "Contact via…", isPresented: $showContactChoice, titleVisibility: .visible
        ) {
            Button("Call") {
                if let c = pendingContact {
                    let cleaned = c.filter { $0.isNumber }
                    if let tel = URL(string: "tel://\(cleaned)"),
                        UIApplication.shared.canOpenURL(tel)
                    {
                        UIApplication.shared.open(tel)
                    }
                }
            }
            Button("WhatsApp — Pre-filled Message") {
                if let c = pendingContact {
                    var digits = c.filter { $0.isNumber }
                    if digits.hasPrefix("0") && digits.count == 10 {
                        digits = "27" + digits.dropFirst()
                    }
                    let mgr = EmergencyRequestManager()
                    let df = DateFormatter()
                    df.dateStyle = .medium
                    df.timeStyle = .short
                    let dateStr = df.string(from: date)
                    let locPart = (location ?? "").isEmpty ? "" : " at \(location!)"
                    let body =
                        "Hello — I saw your incident titled \"\(title)\" reported on \(dateStr)\(locPart). I'm contacting you to see if you are okay?"
                    mgr.openWhatsAppFallback(body: body, toPhone: digits)
                }
            }

            Button("Cancel", role: .cancel) { pendingContact = nil }
        }
        .navigationTitle("Incident Report")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showFullScreenImage) {
            Group {
                if let imageURL = imageURL {
                    FullscreenImageView(imageURL: imageURL)
                } else if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                    FullscreenImageDataView(image: uiImage)
                } else {
                    EmptyView()
                }
            }
        }
        .toolbar {
            if isAdmin {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button(action: { onEdit?() }) {
                            Label("Edit", systemImage: "pencil")
                        }

                        if let onArchive = onArchive {
                            Button(action: onArchive) {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }

                        if let onDelete = onDelete {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // (moved image viewer / picker types into IncidentImageViews.swift)

}

// MARK: - Watch Settings View
struct WatchSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firestoreIsAdmin: Bool = false

    // User Profile Settings
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("userCell") private var userCell: String = ""

    // Watch Credentials
    @AppStorage("watchUsername") private var watchUsername: String = ""
    @AppStorage("watchPassword") private var watchPassword: String = ""

    // App Theme
    @AppStorage("appTheme") private var appTheme: String = "auto"

    // Committee member check for admin settings
    @AppStorage("committeeMembers") private var committeeMembers: String = ""
    
    // Cached admin/committee status from Firestore
    @AppStorage("userIsAdmin") private var userIsAdmin: Bool = false
    @AppStorage("userIsCommittee") private var userIsCommittee: Bool = false

    // Onboarding control
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = true

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
            Form {
                // User Profile Section
                Section("User Profile") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("First Name", text: $userName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                        TextField("Surname", text: $userSurname)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                    }

                    HStack {
                        Text("Cell Phone")
                        Spacer()
                        TextField("Cell Phone", text: $userCell)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)
                    }
                }

                // Watch Access Section
                Section("NeighbourHUB Watch Access") {
                    TextField("Watch Username", text: $watchUsername)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)

                    SecureField("Watch Password", text: $watchPassword)
                        .textFieldStyle(.roundedBorder)
                }

                // App Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $appTheme) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                // Admin Section
                if isAdmin || firestoreIsAdmin {
                    Section("Admin Actions") {
                        Button(action: {
                            // Reset onboarding to trigger it for the user
                            hasCompletedOnboarding = false
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle")
                                    .foregroundColor(.blue)
                                Text("Restart User Setup")
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("NeighbourHUB Watch v1.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("2024.1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Watch Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: fetchAdminStatus)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func fetchAdminStatus() {
        guard let uid = FirebaseManager.shared.getCurrentUserUID() else { return }
        Firestore.firestore().collection("users").document(uid).getDocument { snap, _ in
            guard let data = snap?.data() else { return }
            let admin = data["isAdmin"] as? Bool ?? false
            let committee = data["isCommittee"] as? Bool ?? false
            DispatchQueue.main.async {
                self.firestoreIsAdmin = admin || committee
            }
        }
    }
}
