import SwiftUI

struct MarketplaceDetailView: View {
    @State private var showShareSheet = false
    @State private var showContactActionSheet = false
    @State private var contactToUse: String = ""
    let item: MarketplaceItem
    // Keep backward-compatible params but compute rules locally like EventsView
    let isOwner: Bool
    let isAdmin: Bool
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("committeeMembers") private var committeeMembers: String = ""

    private func isOwnerComputed(_ item: MarketplaceItem) -> Bool {
        let comps = item.owner.split(separator: " ").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }
        let userFirst = userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let userSurnameVal = userSurname.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        if comps.count >= 2 {
            let ownerFirst = comps[0]
            let ownerSurname = comps[1]
            return ownerFirst == userFirst && ownerSurname == userSurnameVal
        } else {
            return comps.first == userFirst
        }
    }

    private var isAdminComputed: Bool {
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
    // Optional callbacks for external actions
    let onMarkSold: (() -> Void)?
    let onUnmarkSold: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAlert = false
    // Image viewer state (matched-geometry + zoom)
    @State private var pageIndex: Int = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var tempScale: CGFloat = 1.0
    @State private var showingImageFullScreen: Bool = false
    @State private var selectedFullScreenIndex: Int = 0
    @Namespace private var imageNamespace
    @State private var tappedThumbnailIndex: Int? = nil

    // MARK: - Helpers
    private func triggerHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Multi-image hero: use image + additionalImages like AdvertDetailView
                    let images: [UIImage] = {
                        var arr: [UIImage] = []
                        if let img = item.image { arr.append(img) }
                        arr.append(contentsOf: item.additionalImages)
                        return arr
                    }()

                    if !images.isEmpty {
                        VStack(spacing: 10) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .shadow(
                                        color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8
                                    )
                                    .padding(.horizontal)
                                    .frame(height: 320)

                                TabView(selection: $pageIndex) {
                                    ForEach(Array(images.enumerated()), id: \.offset) { idx, ui in
                                        GeometryReader { geo in
                                            Image(uiImage: ui)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(
                                                    width: geo.size.width, height: geo.size.height
                                                )
                                                .clipped()
                                                .scaleEffect(zoomScale * tempScale)
                                                .matchedGeometryEffect(
                                                    id: "image-\(item.id.uuidString)-\(idx)",
                                                    in: imageNamespace
                                                )
                                                .cornerRadius(12)
                                                .padding(.horizontal, 18)
                                                .tag(idx)
                                                .gesture(
                                                    MagnificationGesture()
                                                        .onChanged { v in tempScale = v }
                                                        .onEnded { v in
                                                            zoomScale *= v
                                                            tempScale = 1.0
                                                            zoomScale = min(
                                                                max(zoomScale, 1.0), 6.0)
                                                        }
                                                )
                                                .onTapGesture(count: 2) {
                                                    withAnimation(.spring()) {
                                                        zoomScale = 1.0
                                                        tempScale = 1.0
                                                    }
                                                }
                                                .onTapGesture {
                                                    selectedFullScreenIndex = idx
                                                    withAnimation(.spring()) {
                                                        showingImageFullScreen = true
                                                    }
                                                }
                                        }
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .never))
                                .frame(height: 320)

                                // Bottom page indicator
                                if images.count > 1 {
                                    HStack(spacing: 12) {
                                        Text("\(pageIndex + 1) / \(images.count)")
                                            .font(.caption).bold()
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color(.systemBackground).opacity(0.6))
                                            .cornerRadius(10)

                                        Spacer()

                                        HStack(spacing: 6) {
                                            ForEach(0..<images.count, id: \.self) { i in
                                                Circle()
                                                    .fill(
                                                        i == pageIndex
                                                            ? Color.accentColor
                                                            : Color.primary.opacity(0.18)
                                                    )
                                                    .frame(
                                                        width: i == pageIndex ? 10 : 6,
                                                        height: i == pageIndex ? 10 : 6
                                                    )
                                                    .onTapGesture {
                                                        withAnimation { pageIndex = i }
                                                    }
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(BlurView(style: .systemThinMaterial))
                                    .cornerRadius(12)
                                    .padding(.horizontal, 30)
                                    .padding(.bottom, 8)
                                }
                            }

                            // Thumbnail strip with tap animation and haptic
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(images.enumerated()), id: \.offset) {
                                            idx, ui in
                                            Image(uiImage: ui)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 72, height: 64)
                                                .clipped()
                                                .cornerRadius(8)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(
                                                            idx == pageIndex
                                                                ? Color.accentColor : Color.clear,
                                                            lineWidth: 2)
                                                )
                                                .scaleEffect(
                                                    tappedThumbnailIndex == idx ? 0.94 : 1.0
                                                )
                                                .animation(
                                                    .spring(response: 0.28, dampingFraction: 0.6),
                                                    value: tappedThumbnailIndex
                                                )
                                                .id(idx)
                                                .padding(.leading, idx == 0 ? 16 : 0)
                                                .onTapGesture {
                                                    // tactile + tiny tap animation
                                                    triggerHaptic()
                                                    tappedThumbnailIndex = idx
                                                    withAnimation(.easeInOut) { pageIndex = idx }
                                                    withAnimation(.easeInOut) {
                                                        proxy.scrollTo(idx, anchor: .center)
                                                    }
                                                    DispatchQueue.main.asyncAfter(
                                                        deadline: .now() + 0.14
                                                    ) { tappedThumbnailIndex = nil }
                                                }
                                        }
                                    }
                                }
                                .frame(height: 78)
                                .onChange(of: pageIndex) { newIndex, _ in
                                    withAnimation(.easeInOut) {
                                        proxy.scrollTo(newIndex, anchor: .center)
                                    }
                                }
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        proxy.scrollTo(pageIndex, anchor: .center)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    Text(item.title)
                        .font(.title2).bold()
                    Text(item.category)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("R\(String(format: "%.2f", item.price))")
                        .font(.title3.bold())
                        .foregroundColor(.accentColor)
                    Divider()
                    Text(item.description)
                        .font(.body)
                    Divider()
                    HStack(alignment: .top) {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            // Show only the owner's first name (remove surname)
                            let ownerFirst =
                                item.owner.split(separator: " ").first.map {
                                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                                        .capitalized
                                } ?? item.owner
                            Text("Listed by: \(ownerFirst)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            // Show cellphone number with phone icon if present
                            let fullPhone = item.contact.filter { $0.isNumber }
                            if !fullPhone.isEmpty {
                                Button(action: {
                                    contactToUse = fullPhone
                                    showContactActionSheet = true
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "phone.fill")
                                            .foregroundColor(.accentColor)
                                        Text(fullPhone)
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                            .underline()
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityLabel("Contact number: \(fullPhone)")
                            }
                            // Show sold information if applicable
                            if item.isSold, let soldOn = item.soldDate {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.red)
                                    Text("Sold on \(soldOn, style: .date)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Text(item.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .sheet(isPresented: .constant(false)) { EmptyView() }
                .padding()
            }
            .navigationTitle("Listing Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Use Events-style rules (computed) to decide whether to show owner/admin controls
                        if isOwnerComputed(item) || isAdminComputed {
                            if item.isSold {
                                Button(action: {
                                    // runtime guard
                                    guard isOwnerComputed(item) || isAdminComputed else { return }
                                    onUnmarkSold?()
                                }) {
                                    Text("Mark Available")
                                }
                            } else {
                                Button(action: {
                                    guard isOwnerComputed(item) || isAdminComputed else { return }
                                    onMarkSold?()
                                }) {
                                    Text("Mark Sold")
                                }
                            }

                            Button(
                                role: .destructive,
                                action: {
                                    showDeleteAlert = true
                                }
                            ) {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            // Share sheet removed
            .actionSheet(isPresented: $showContactActionSheet) {
                ActionSheet(
                    title: Text("Contact Options"), message: Text("What would you like to do?"),
                    buttons: [
                        .default(Text("Call \(contactToUse)")) {
                            if let url = URL(string: "tel://\(contactToUse)") {
                                UIApplication.shared.open(url)
                            }
                        },
                        .default(Text("WhatsApp Chat")) {
                            // WhatsApp requires country code, assume South Africa (+27) if number is 10 digits and starts with 0
                            var waNumber = contactToUse.filter { $0.isNumber }
                            if waNumber.hasPrefix("0") && waNumber.count == 10 {
                                waNumber = "27" + waNumber.dropFirst()
                            }
                            if let url = URL(string: "https://wa.me/\(waNumber)") {
                                UIApplication.shared.open(url)
                            }
                        },
                        .default(Text("Copy Number")) {
                            UIPasteboard.general.string = contactToUse
                        },
                        .cancel(),
                    ])
            }
        }
        // Delete alert removed
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Delete Listing?"),
                message: Text("Are you sure you want to delete this listing?"),
                primaryButton: .destructive(Text("Delete")) {
                    // runtime guard
                    if isOwnerComputed(item) || isAdminComputed {
                        onDelete?()
                    }
                    dismiss()
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = item.image {
                ShareSheet(activityItems: [
                    item.title,
                    "R\(String(format: "%.2f", item.price))",
                    item.description,
                    img,
                ])
            } else {
                ShareSheet(activityItems: [
                    item.title,
                    "R\(String(format: "%.2f", item.price))",
                    item.description,
                ])
            }
        }
        .actionSheet(isPresented: $showContactActionSheet) {
            ActionSheet(
                title: Text("Contact Options"), message: Text(""),
                buttons: [
                    .default(Text("Call \(contactToUse)")) {
                        if let url = URL(string: "tel://\(contactToUse)") {
                            UIApplication.shared.open(url)
                        }
                    },
                    .default(Text("WhatsApp Chat")) {
                        // WhatsApp requires country code, assume South Africa (+27) if number is 10 digits and starts with 0
                        var waNumber = contactToUse.filter { $0.isNumber }
                        if waNumber.hasPrefix("0") && waNumber.count == 10 {
                            waNumber = "27" + waNumber.dropFirst()
                        }
                        if let url = URL(string: "https://wa.me/\(waNumber)") {
                            UIApplication.shared.open(url)
                        }
                    },
                    .default(Text("Copy Number")) {
                        UIPasteboard.general.string = contactToUse
                    },
                    .cancel(),
                ])
        }
        // Delete alert removed

        // Full-screen matched-geometry overlay
        .overlay {
            if showingImageFullScreen {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.95).edgesIgnoringSafeArea(.all)

                    TabView(selection: $selectedFullScreenIndex) {
                        ForEach(
                            Array(
                                (item.image != nil
                                    ? [item.image!] + item.additionalImages : item.additionalImages)
                                    .enumerated()), id: \.offset
                        ) { idx, ui in
                            GeometryReader { geo in
                                Image(uiImage: ui)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .matchedGeometryEffect(
                                        id: "image-\(item.id.uuidString)-\(idx)", in: imageNamespace
                                    )
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                                    .tag(idx)
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
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))

                    Button(action: {
                        withAnimation(.spring()) {
                            showingImageFullScreen = false
                            zoomScale = 1.0
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill").font(.title)
                            .padding()
                    }
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(50)
            }
        }
    }
}
