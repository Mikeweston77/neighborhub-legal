import PhotosUI
import SwiftUI

struct MarketplaceAddSheet: View {
    let categories: [String]
    let defaultContact: String
    let defaultCell: String
    var initialItem: MarketplaceItem? = nil
    var onAdd: (MarketplaceItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("userCell") private var userCell: String = ""
    @State private var title = ""
    @State private var description = ""
    @State private var price = ""
    @State private var category: String
    @State private var condition: ItemCondition = .good
    @State private var image: UIImage? = nil
    @State private var additionalImages: [UIImage] = []
    @State private var showImagePicker = false

    // Photo and picker state
    @State private var showPhotoSourceSheet: Bool = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var photoLimitMessage: String = ""
    @State private var showPhotoLimitAlert: Bool = false
    @State private var photoPickerSelectionLimit: Int = 5
    @State private var showPhotoPicker: Bool = false

    // Contact customization
    @State private var useCustomContact: Bool = false
    @State private var customContact: String = ""
    @State private var useCustomCell: Bool = false
    @State private var customCell: String = ""

    // Alerts
    @State private var showAlert: Bool = false
    @State private var isCreating: Bool = false

    // Explicit initializer to control how the @State-backed `category` is initialized
    public init(
        categories: [String], defaultContact: String, defaultCell: String,
        initialItem: MarketplaceItem? = nil, onAdd: @escaping (MarketplaceItem) -> Void,
        category: String? = nil
    ) {
        self.categories = categories
        self.defaultContact = defaultContact
        self.defaultCell = defaultCell
        self.initialItem = initialItem
        self.onAdd = onAdd

        // Determine initial category: use explicit category param, otherwise initialItem, otherwise first category or empty
        let initialCategory: String
        if let c = category, !c.isEmpty {
            initialCategory = c
        } else if let item = initialItem {
            initialCategory = item.category
        } else if let first = categories.first {
            initialCategory = first
        } else {
            initialCategory = ""
        }
        _category = State(initialValue: initialCategory)

        // Pre-fill fields if editing an existing item
        if let item = initialItem {
            _title = State(initialValue: item.title)
            _description = State(initialValue: item.description)
            _price = State(initialValue: String(format: "%.2f", item.price))
            _condition = State(initialValue: item.condition)
            _image = State(initialValue: item.image)
            _additionalImages = State(initialValue: item.additionalImages)
        }
    }

    // Convenience initializer used by call sites that don't pass an initialItem or category explicitly
    public init(
        categories: [String], defaultContact: String, defaultCell: String,
        onAdd: @escaping (MarketplaceItem) -> Void
    ) {
        self.init(
            categories: categories, defaultContact: defaultContact, defaultCell: defaultCell,
            initialItem: nil, onAdd: onAdd, category: nil)
    }
    var body: some View {
        NavigationView {
            formContent
        }
    }

    // Split the form into smaller computed section views to reduce expression complexity
    private var formContent: some View {
        Form {
            photoSection
            titleSection
            descriptionSection
            priceSection
            categorySection
            conditionSection
            contactSection
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
        .navigationTitle("Add Listing")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: { dismiss() })
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    guard !isCreating else { return }
                    guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
                        !category.trimmingCharacters(in: .whitespaces).isEmpty,
                        let priceVal = Double(price), priceVal > 0
                    else {
                        showAlert = true
                        return
                    }

                    isCreating = true

                    let contactName =
                        useCustomContact
                        ? customContact : (defaultContact.isEmpty ? "You" : defaultContact)
                    let contactCell = useCustomCell ? customCell : defaultCell
                    var contactString = contactName
                    if !contactCell.isEmpty { contactString += " (" + contactCell + ")" }

                    let ownerFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ownerLast = userSurname.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ownerName: String
                    if ownerFirst.isEmpty {
                        ownerName = "You"
                    } else {
                        ownerName =
                            (ownerLast.isEmpty ? ownerFirst : "\(ownerFirst) \(ownerLast)")
                            .capitalized
                    }

                    var item = MarketplaceItem(
                        id: UUID(),
                        owner: ownerName,
                        title: title,
                        description: description,
                        price: priceVal,
                        category: category,
                        condition: condition,
                        date: Date(),
                        contact: contactString,
                        isSold: false,
                        soldDate: nil,
                        isNegotiable: false,
                        tags: [],
                        location: userCell.isEmpty ? "Your Neighborhood" : userCell,
                        sustainabilityScore: 0,
                        isEmergency: false,
                        pickupOptions: [.pickup]
                    )

                    // Set images via computed properties to trigger caching
                    if let primaryImage = image {
                        item.image = primaryImage
                    }
                    item.additionalImages = additionalImages

                    onAdd(item)
                    // Note: dismiss() should be called by parent after successful creation
                }) {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isCreating ? "Adding..." : "Add")
                    }
                }
                .disabled(
                    title.trimmingCharacters(in: .whitespaces).isEmpty
                        || price.trimmingCharacters(in: .whitespaces).isEmpty
                        || category.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .alert("Please fill all fields and enter a valid price.", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $image, sourceType: imagePickerSource)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(limit: photoPickerSelectionLimit) { images in
                let currentCount = (image != nil ? 1 : 0) + additionalImages.count
                let space = max(0, 5 - currentCount)
                let toAdd = images.prefix(space)
                additionalImages.append(contentsOf: toAdd)
            }
        }
        .alert(photoLimitMessage, isPresented: $showPhotoLimitAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Sections
    private var photoSection: some View {
        Section(header: Text("Photo")) {
            Button(action: { showPhotoSourceSheet = true }) {
                ZStack {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipped()
                            .cornerRadius(12)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(height: 120)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray.opacity(0.3))
                            )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 140)
                .padding(.vertical, 4)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .actionSheet(isPresented: $showPhotoSourceSheet) {
                ActionSheet(
                    title: Text("Select Photo Source"),
                    buttons: [
                        .default(Text("Take Photo")) {
                            imagePickerSource = .camera
                            showImagePicker = true
                        },
                        .default(Text("Choose from Gallery")) {
                            let currentCount = (image != nil ? 1 : 0) + additionalImages.count
                            let remaining = max(0, 5 - currentCount)
                            if remaining <= 0 {
                                photoLimitMessage =
                                    "You can add up to 5 photos per listing. Remove one before adding more."
                                showPhotoLimitAlert = true
                            } else {
                                photoPickerSelectionLimit = remaining
                                showPhotoPicker = true
                            }
                        },
                        .cancel(),
                    ])
            }

            if !additionalImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(additionalImages.enumerated()), id: \.offset) { idx, ui in
                            Image(uiImage: ui)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 64)
                                .clipped()
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var titleSection: some View {
        Section(header: Text("Title")) {
            SmartTextField(
                "Item title", text: $title, keyboardType: .default, autocapitalization: .words,
                autocorrection: true, submitLabel: .next)
        }
    }

    private var descriptionSection: some View {
        Section(header: Text("Description")) {
            SmartTextEditor(
                text: $description, placeholder: "Describe your item...", minHeight: 80,
                autocapitalization: .sentences, autocorrection: true)
        }
    }

    private var priceSection: some View {
        Section(header: Text("Price")) {
            SmartTextField(
                "0.00", text: $price, keyboardType: .decimalPad, autocapitalization: .none,
                autocorrection: false, submitLabel: .done)
        }
    }

    private var categorySection: some View {
        Section(header: Text("Category")) {
            Picker("Category", selection: $category) {
                ForEach(categories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var conditionSection: some View {
        Section(header: Text("Condition")) {
            Picker("Item Condition", selection: $condition) {
                ForEach(ItemCondition.allCases, id: \.self) { itemCondition in
                    Text(itemCondition.rawValue).tag(itemCondition)
                }
            }
            .pickerStyle(.menu)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: condition.icon).foregroundColor(condition.color).frame(
                        width: 20)
                    Text(condition.rawValue).font(.subheadline.weight(.medium)).foregroundColor(
                        .primary)
                    Spacer()
                }
                Text(conditionDescription(for: condition)).font(.caption).foregroundColor(
                    .secondary
                ).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var contactSection: some View {
        Section(header: Text("Contact Details")) {
            Toggle("Use custom contact name", isOn: $useCustomContact)
            if useCustomContact {
                SmartTextField(
                    "Contact name", text: $customContact, keyboardType: .default,
                    autocapitalization: .words, autocorrection: true)
            } else {
                Text(defaultContact).foregroundColor(.secondary)
            }
            Toggle("Use custom cellphone", isOn: $useCustomCell)
            if useCustomCell {
                SmartTextField(
                    "Cellphone", text: $customCell, keyboardType: .phonePad,
                    autocapitalization: .none, autocorrection: false)
            } else {
                Text(defaultCell.isEmpty ? "No cellphone set" : defaultCell).foregroundColor(
                    .secondary)
            }
        }
    }

    // MARK: - Helper Functions
    private func conditionDescription(for condition: ItemCondition) -> String {
        switch condition {
        case .brandNew:
            return "Never used, still in original packaging"
        case .likeNew:
            return "Gently used, excellent condition with minimal wear"
        case .good:
            return "Used but well-maintained, some signs of wear"
        case .fair:
            return "Shows normal wear, fully functional"
        case .forParts:
            return "Not working or heavily damaged, suitable for parts only"
        }
    }
}

// MARK: - ImagePicker (UIKit bridge)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        picker.sourceType =
            UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.image = img
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - PhotoPicker (PHPicker wrapper)
struct PhotoPicker: UIViewControllerRepresentable {
    let limit: Int
    var completion: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration(photoLibrary: .shared())
        cfg.selectionLimit = limit
        cfg.filter = .images
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                parent.completion([])
                return
            }

            var images: [UIImage] = []
            let group = DispatchGroup()

            for r in results {
                if r.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    r.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                        defer { group.leave() }
                        if let img = object as? UIImage {
                            DispatchQueue.main.async { images.append(img) }
                        }
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                self?.parent.completion(images)
            }
        }
    }
}
