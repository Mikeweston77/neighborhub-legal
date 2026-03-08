import PDFKit
import PhotosUI
import SwiftUI
import UIKit

struct AddAdvertSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    // If `existing` is non-nil we are editing an advert; otherwise creating a new one.
    var existing: Advert?

    @State private var title = ""
    @State private var summary = ""
    // price removed per request
    @State private var category = "General"
    @State private var locationName = ""
    @State private var imageData: Data? = nil
    @State private var imageDatas: [Data] = []
    @State private var imageLocalPath: String? = nil
    @State private var imageLocalPaths: [String] = []
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingDocumentPicker: Bool = false
    @State private var showingImageViewer: Bool = false
    @State private var selectedImageIndex: Int = 0
    @State private var showingFileTooLargeAlert: Bool = false
    @State private var fileTooLargeName: String = ""
    @State private var sellerContact: String = ""
    @State private var sellerReputationText: String = ""
    @State private var sellerName: String = ""
    @State private var useProfileDetails: Bool = true

    // read profile values
    @AppStorage("userName") private var profileUserName: String = ""
    @AppStorage("userSurname") private var profileUserSurname: String = ""
    @AppStorage("userCell") private var profileUserCell: String = ""
    @AppStorage("userEmail") private var profileUserEmail: String = ""

    var onCreate: (Advert) -> Void

    init(existing: Advert? = nil, onCreate: @escaping (Advert) -> Void) {
        self.existing = existing
        self.onCreate = onCreate
        // Initialize state from existing advert when editing
        _title = State(initialValue: existing?.title ?? "")
        _summary = State(initialValue: existing?.summary ?? "")
        _category = State(initialValue: existing?.category ?? "General")
        _locationName = State(initialValue: existing?.locationName ?? "")
        _imageData = State(initialValue: existing?.imageData)
        if let arr = existing?.imageDatas { _imageDatas = State(initialValue: arr) }
        _imageLocalPath = State(initialValue: existing?.imageLocalPath)
        _imageLocalPaths = State(initialValue: existing?.imageLocalPaths ?? [])
        _sellerContact = State(initialValue: existing?.sellerContact ?? "")
        if let r = existing?.sellerReputation {
            _sellerReputationText = State(initialValue: String(r))
        }
        _sellerName = State(initialValue: existing?.sellerName ?? "")
        // default to using profile if available
        _useProfileDetails = State(initialValue: existing == nil)
        // If editing and there are existing local paths, preload their Data for preview
        if imageDatas.isEmpty, let paths = existing?.imageLocalPaths {
            var loaded: [Data] = []
            for p in paths {
                if let d = try? Data(contentsOf: URL(fileURLWithPath: p)) {
                    loaded.append(d)
                }
            }
            if !loaded.isEmpty {
                _imageDatas = State(initialValue: loaded)
                _imageData = State(initialValue: loaded.first)
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Photos")) {
                    // allow more images (raised from 5 -> 12)
                    PhotosPicker(
                        selection: $selectedItems, maxSelectionCount: 12, matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "plus.circle.fill").font(.title2)
                            Text("Add Photos")
                        }
                        .foregroundColor(.accentColor)
                    }
                    .padding(.vertical, 6)
                    .onChange(of: selectedItems) { oldItems, newItems in
                        Task {
                            var loaded: [Data] = []
                            for item in newItems {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    if let ui = UIImage(data: data),
                                        let compressed = ui.jpegData(compressionQuality: 0.8)
                                    {
                                        loaded.append(compressed)
                                    } else {
                                        loaded.append(data)
                                    }
                                }
                            }
                            if !loaded.isEmpty {
                                imageDatas = loaded
                                imageData = loaded.first
                            }
                        }
                    }

                    // Allow attaching documents (PDFs, images) and convert them to images
                    Button(action: { showingDocumentPicker = true }) {
                        HStack {
                            Image(systemName: "doc.append.fill").font(.title2)
                            Text("Add File / PDF")
                        }
                        .foregroundColor(.accentColor)
                    }
                    .padding(.vertical, 6)
                    .sheet(isPresented: $showingDocumentPicker) {
                        DocumentPicker { url in
                            guard let url = url else { return }
                            // File size guard (50 MB)
                            if let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey]
                            ), let size = vals.fileSize {
                                let limit = 50 * 1024 * 1024
                                if size > limit {
                                    fileTooLargeName = vals.name ?? url.lastPathComponent
                                    showingFileTooLargeAlert = true
                                    return
                                }
                            }

                            // Use security-scoped access if available
                            var didStart = false
                            if url.startAccessingSecurityScopedResource() { didStart = true }
                            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

                            if let convertedArr = convertDocumentToImageDatas(from: url) {
                                // append converted images (PDF may yield multiple pages)
                                let spaceLeft = max(0, 12 - imageDatas.count)
                                if spaceLeft > 0 {
                                    let toAppend = Array(convertedArr.prefix(spaceLeft))
                                    imageDatas.append(contentsOf: toAppend)
                                    if imageData == nil, let first = toAppend.first {
                                        imageData = first
                                    }
                                }
                            }
                        }
                    }

                    // Thumbnail strip preview of selected images
                    if !imageDatas.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(imageDatas.enumerated()), id: \.offset) { idx, data in
                                    if let ui = UIImage(data: data) {
                                        Button {
                                            selectedImageIndex = idx
                                            showingImageViewer = true
                                        } label: {
                                            Image(uiImage: ui)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 90, height: 60)
                                                .clipped()
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(
                                                            Color.primary.opacity(
                                                                selectedImageIndex == idx
                                                                    ? 0.9 : 0.0), lineWidth: 2)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                // Fullscreen viewer sheet with paging and pinch-to-zoom
                .sheet(isPresented: $showingImageViewer) {
                    if !imageDatas.isEmpty {
                        ImageViewer(images: imageDatas, index: $selectedImageIndex)
                    }
                }

                // File-too-large alert
                .alert("File too large", isPresented: $showingFileTooLargeAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("\(fileTooLargeName) exceeds 50 MB and cannot be added.")
                }

                Section(header: Text("Details")) {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary)
                    // Category picker
                    Picker("Category", selection: $category) {
                        Text("General").tag("General")
                        Text("For Sale").tag("For Sale")
                        Text("Services").tag("Services")
                        Text("Wanted").tag("Wanted")
                        Text("Free").tag("Free")
                        Text("Jobs").tag("Jobs")
                        Text("Rent").tag("Rent")
                    }
                    .pickerStyle(.menu)
                    TextField("Location name", text: $locationName)
                    // Seller details: use profile or custom
                    Toggle("Use my profile details", isOn: $useProfileDetails)

                    if useProfileDetails {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(
                                    profileUserName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty
                                        ? "Using profile (unnamed)"
                                        : "Using profile: \(profileUserName)"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                if !profileUserCell.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                                {
                                    Text(profileUserCell)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else if !profileUserEmail.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty {
                                    Text(profileUserEmail)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                    } else {
                        TextField("Seller name", text: $sellerName)
                        TextField("Seller contact (phone or email)", text: $sellerContact)
                            .keyboardType(.emailAddress)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Advert" : "Edit Advert")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(existing == nil ? "Publish" : "Save") {
                        // Preserve id/createdAt when editing
                        let rep = Double(sellerReputationText)
                        var ad = Advert(
                            id: existing?.id ?? UUID(),
                            title: title.isEmpty ? "Untitled" : title,
                            summary: summary,
                            price: nil,
                            currency: existing?.currency ?? "USD",
                            imageData: imageData,
                            imageDatas: imageDatas.isEmpty ? nil : imageDatas,
                            imageLocalPath: imageLocalPath,
                            category: category,
                            locationName: locationName,
                            createdAt: existing?.createdAt ?? Date(),
                            expiresAt: existing?.expiresAt,
                            isPinned: existing?.isPinned ?? false,
                            sellerName: existing?.sellerName
                                ?? (useProfileDetails
                                    ? {
                                        let fullName = (profileUserName + " " + profileUserSurname)
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                                        return fullName.isEmpty ? "Anonymous" : fullName
                                    }() : (sellerName.isEmpty ? "You" : sellerName)),
                            sellerVerified: existing?.sellerVerified ?? true
                        )
                        if useProfileDetails {
                            // prefer profile contact if available
                            if !profileUserCell.isEmpty {
                                ad.sellerContact = profileUserCell
                            } else if !profileUserEmail.isEmpty {
                                ad.sellerContact = profileUserEmail
                            }
                        } else {
                            ad.sellerContact =
                                sellerContact.isEmpty ? existing?.sellerContact : sellerContact
                        }
                        ad.sellerReputation = rep ?? existing?.sellerReputation
                        // If images were selected, save all to disk and set imageLocalPaths (first becomes primary imageLocalPath for compatibility)
                        var localPaths: [String] = []
                        // If the user didn't pick new images but the advert already had local paths, preserve them
                        if imageDatas.isEmpty && !imageLocalPaths.isEmpty {
                            localPaths = imageLocalPaths
                        } else {
                            // Ensure we only save up to 12 images
                            let itemsToSave =
                                imageDatas.isEmpty
                                ? (imageData.map { [$0] } ?? []) : Array(imageDatas.prefix(12))
                            for (i, data) in itemsToSave.enumerated() {
                                do {
                                    let suggested =
                                        i == 0
                                        ? (title.isEmpty ? "advert" : title) : "\(title)-\(i)"
                                    let path = try ImageFileManager.saveImageData(
                                        data, suggestedName: suggested)
                                    localPaths.append(path)
                                } catch {
                                    print(
                                        "[AddAdvertSheet] Failed to save image \(i) locally: \(error)"
                                    )
                                }
                            }
                        }
                        if !localPaths.isEmpty {
                            ad.imageLocalPaths = localPaths
                            ad.imageLocalPath = localPaths.first
                        }

                        onCreate(ad)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// Simple fullscreen image viewer with paging and pinch-to-zoom
private struct ImageViewer: View {
    let images: [Data]
    @Binding var index: Int
    @Environment(\.presentationMode) private var presentationMode

    @State private var zoomScale: CGFloat = 1.0
    @State private var tempScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { idx, data in
                    if let ui = UIImage(data: data) {
                        GeometryReader { geo in
                            Image(uiImage: ui)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(zoomScale * tempScale)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { v in tempScale = v }
                                        .onEnded { v in
                                            zoomScale *= v
                                            tempScale = 1.0
                                            zoomScale = min(max(zoomScale, 1.0), 6.0)
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring()) {
                                        zoomScale = 1.0
                                        tempScale = 1.0
                                    }
                                }
                                .tag(idx)
                        }
                    } else {
                        Color(.systemBackground).tag(idx)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "xmark.circle.fill").font(.title)
                    .padding()
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
}

// MARK: - Document Picker and conversion helpers

private struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(
            forOpeningContentTypes: [.pdf, .image, .jpeg, .png], asCopy: true)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController, context: Context
    ) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(
            _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
        ) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

private func convertDocumentToImageDatas(from url: URL) -> [Data]? {
    let type =
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier
        ?? url.pathExtension.lowercased()

    if type.contains("pdf") {
        // Render all pages of PDF to UIImages
        guard let doc = PDFDocument(url: url) else { return nil }
        var out: [Data] = []
        let scale: CGFloat = 2.0
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            UIGraphicsBeginImageContextWithOptions(size, true, 0)
            guard let ctx = UIGraphicsGetCurrentContext() else { continue }
            ctx.saveGState()
            // White background
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            // Flip context and scale
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
            if let img = UIGraphicsGetImageFromCurrentImageContext(),
                let jpeg = img.jpegData(compressionQuality: 0.8)
            {
                out.append(jpeg)
            }
            UIGraphicsEndImageContext()
        }
        return out.isEmpty ? nil : out
    } else if ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) {
        if let data = try? Data(contentsOf: url) {
            // Normalize: convert to jpeg
            if let ui = UIImage(data: data), let jpeg = ui.jpegData(compressionQuality: 0.8) {
                return [jpeg]
            }
            return [data]
        }
    }
    return nil
}
