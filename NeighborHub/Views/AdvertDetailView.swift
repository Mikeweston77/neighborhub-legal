import MessageUI
import SwiftUI

struct AdvertDetailView: View {
    @State var ad: Advert
    @State private var showingShare = false
    @State private var pageIndex: Int = 0
    @State private var animateMessage = false
    @State private var animateSave = false
    @State private var animateShare = false
    @State private var showingMessageComposer = false
    @State private var showingContactActions = false
    @State private var contactForActions: String? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var tempScale: CGFloat = 1.0
    @State private var isSaved = false
    @State private var showingImageFullScreen: Bool = false
    @State private var selectedFullScreenIndex: Int = 0
    @Namespace private var imageNamespace
    @State private var tappedThumbnailIndex: Int? = nil

    @Environment(\.openURL) private var openURL

    private var priceText: String? { ad.priceDisplay }
    private var timeAgo: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: ad.createdAt, relativeTo: Date())
    }

    private var images: [UIImage] {
        var allImages: [UIImage] = []

        // Follow same priority as ad.uiImage but collect ALL images

        // 1. Multiple local paths (imageLocalPaths)
        if let paths = ad.imageLocalPaths, !paths.isEmpty {
            for path in paths {
                if FileManager.default.fileExists(atPath: path),
                    let img = UIImage(contentsOfFile: path)
                {
                    allImages.append(img)
                }
            }
        }

        // 2. Single local path (imageLocalPath) - only if no multiple paths found
        if allImages.isEmpty, let path = ad.imageLocalPath {
            if FileManager.default.fileExists(atPath: path), let img = UIImage(contentsOfFile: path)
            {
                allImages.append(img)
            }
        }

        // 3. Multiple embedded data (imageDatas) - only if no local paths found
        if allImages.isEmpty, let dataArray = ad.imageDatas, !dataArray.isEmpty {
            for data in dataArray {
                if let img = UIImage(data: data) {
                    allImages.append(img)
                }
            }
        }

        // 4. Single embedded data (imageData) - only if nothing else found
        if allImages.isEmpty, let data = ad.imageData, let img = UIImage(data: data) {
            allImages.append(img)
        }

        return allImages
    }

    private var remoteImageUrls: [URL] {
        // Only use remote URLs if no local images available
        guard images.isEmpty else { return [] }

        var urls: [URL] = []
        if let urlStrings = ad.imageStorageURLs, !urlStrings.isEmpty {
            urls = urlStrings.compactMap { URL(string: $0) }
        } else if let urlString = ad.imageStorageURL {
            if let url = URL(string: urlString) {
                urls = [url]
            }
        }
        return urls
    }

    private var hasImages: Bool {
        return !images.isEmpty || !remoteImageUrls.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero image with polished card look, page indicator and thumbnail strip
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 10) {
                        if hasImages {
                            ZStack(alignment: .bottom) {
                                // subtle rounded card background with material
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .shadow(
                                        color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8
                                    )
                                    .padding(.horizontal)
                                    .frame(height: 320)

                                if !images.isEmpty {
                                    // Local images
                                    TabView(selection: $pageIndex) {
                                        ForEach(Array(images.enumerated()), id: \.offset) {
                                            idx, ui in
                                            LocalImageView(
                                                image: ui, index: idx, ad: ad,
                                                pageIndex: $pageIndex, zoomScale: $zoomScale,
                                                tempScale: $tempScale,
                                                showingImageFullScreen: $showingImageFullScreen,
                                                selectedFullScreenIndex: $selectedFullScreenIndex,
                                                imageNamespace: imageNamespace)
                                        }
                                    }
                                    .tabViewStyle(.page(indexDisplayMode: .never))
                                    .frame(height: 320)
                                } else {
                                    // Remote images
                                    TabView(selection: $pageIndex) {
                                        ForEach(Array(remoteImageUrls.enumerated()), id: \.offset) {
                                            idx, url in
                                            RemoteImageView(url: url, index: idx, ad: ad)
                                        }
                                    }
                                    .tabViewStyle(.page(indexDisplayMode: .never))
                                    .frame(height: 320)
                                }

                                // Bottom page indicator with pill background
                                let totalImages =
                                    !images.isEmpty ? images.count : remoteImageUrls.count
                                if totalImages > 1 {
                                    HStack(spacing: 12) {
                                        Text("\(pageIndex + 1) / \(totalImages)")
                                            .font(.caption).bold()
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color(.systemBackground).opacity(0.6))
                                            .cornerRadius(10)

                                        Spacer()

                                        HStack(spacing: 6) {
                                            ForEach(0..<totalImages, id: \.self) { i in
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
                                    .background(.thinMaterial)
                                    .cornerRadius(12)
                                    .padding(.horizontal, 30)
                                    .padding(.bottom, 8)
                                }
                            }

                            // Thumbnail strip with tap animation, haptic and auto-centering
                            if !images.isEmpty {
                                LocalThumbnailStrip(
                                    images: images, pageIndex: $pageIndex,
                                    tappedThumbnailIndex: $tappedThumbnailIndex)
                            } else {
                                RemoteThumbnailStrip(
                                    urls: remoteImageUrls, pageIndex: $pageIndex,
                                    tappedThumbnailIndex: $tappedThumbnailIndex)
                            }
                        } else {
                            // No images available - show placeholder
                            Rectangle()
                                .fill(Color(.secondarySystemFill))
                                .frame(height: 300)
                                .cornerRadius(12)
                                .padding(.horizontal)
                                .overlay(
                                    VStack {
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundColor(.secondary)
                                        Text("No images")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                )
                        }
                    }

                    // Top-right floating action buttons (share / more)
                    HStack(spacing: 10) {
                        Button {
                            triggerAction($animateShare)
                            showingShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .scaleEffect(animateShare ? 0.92 : 1)
                        .animation(
                            .spring(response: 0.25, dampingFraction: 0.6), value: animateShare
                        )
                        .accessibilityLabel("Share advert")
                    }
                    .padding(12)
                }

                // Title, price and seller
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ad.title)
                                .font(.title2)
                                .bold()
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                if let p = priceText {
                                    Text(p)
                                        .font(.title3)
                                        .bold()
                                        .foregroundColor(.accentColor)
                                }

                                Text("•")
                                    .foregroundColor(.secondary)

                                Text(ad.category)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)

                                Spacer()
                            }
                        }

                        SellerView(
                            name: ad.sellerName, verified: ad.sellerVerified,
                            contact: ad.sellerContact, reputation: ad.sellerReputation
                        ) { contact in
                            // SellerView passes a non-optional String here, use it directly
                            contactForActions = contact
                            showingContactActions = true
                        }
                    }

                    HStack(spacing: 12) {
                        Button(action: { openLocation(ad.locationName) }) {
                            Label(ad.locationName ?? "Nearby", systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(timeAgo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Divider().padding(.horizontal)

                // Description
                VStack(alignment: .leading, spacing: 12) {
                    Text("Description")
                        .font(.headline)
                    Text(ad.summary)
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                }
                .padding(.horizontal)

                Spacer(minLength: 24)

                // Actions (Save button removed per request)
                HStack(spacing: 12) {
                    Button(action: {
                        triggerAction($animateMessage)
                        if let contact = ad.sellerContact, !contact.isEmpty {
                            // try WhatsApp first, fallback to message sheet
                            openWhatsApp(
                                contact, message: "Hi, I'm interested in your advert: \(ad.title)")
                        } else {
                            showingMessageComposer = true
                        }
                    }) {
                        Label("Message", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .sheet(isPresented: $showingMessageComposer) {
                        if let contact = ad.sellerContact, !contact.isEmpty {
                            MessageComposeView(
                                recipients: [contact],
                                body: "Hi, I'm interested in your advert: \(ad.title)")
                        } else {
                            MessageComposeView(
                                recipients: [],
                                body: "Hi, I'm interested in your advert: \(ad.title)")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShare) {
            ShareSheet(activityItems: [shareText])
        }
        .confirmationDialog(
            "Contact", isPresented: $showingContactActions, titleVisibility: .visible
        ) {
            if let c = contactForActions {
                Button("WhatsApp") {
                    openWhatsApp(c, message: "Hi, I'm interested in your advert: \(ad.title)")
                }
                Button("Phone") {
                    if let phoneURL = URL(string: "tel://\(c.filter { $0.isNumber })"),
                        UIApplication.shared.canOpenURL(phoneURL)
                    {
                        openURL(phoneURL)
                    }
                }
                Button("Copy") { UIPasteboard.general.string = c }
            }
            Button("Cancel", role: .cancel) {}
        }
        // In-view full-screen overlay using matched geometry for animated transition
        .overlay {
            if showingImageFullScreen {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.95).edgesIgnoringSafeArea(.all)

                    TabView(selection: $selectedFullScreenIndex) {
                        ForEach(Array(images.enumerated()), id: \.offset) { idx, ui in
                            GeometryReader { geo in
                                Image(uiImage: ui)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .matchedGeometryEffect(
                                        id: "image-\(ad.id.uuidString)-\(idx)", in: imageNamespace
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

    private var shareText: String {
        var parts: [String] = []
        parts.append(ad.title)
        if let p = priceText { parts.append(p) }
        if !ad.summary.isEmpty { parts.append(ad.summary) }
        if let loc = ad.locationName { parts.append(loc) }
        return parts.joined(separator: " — ")
    }

    // MARK: - Helpers
    private func triggerHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    private func openWhatsApp(_ contact: String, message: String) {
        // Use same method as Marketplace: normalize digits and assume South Africa (+27)
        var waNumber = contact.filter { $0.isNumber }
        if waNumber.hasPrefix("0") && waNumber.count == 10 {
            waNumber = "27" + waNumber.dropFirst()
        }
        if !waNumber.isEmpty, let url = URL(string: "https://wa.me/\(waNumber)") {
            UIApplication.shared.open(url)
            return
        }
        // fallback to message composer
        showingMessageComposer = true
    }

    private func openLocation(_ location: String?) {
        guard let l = location, !l.isEmpty else { return }
        // Use Apple Maps query
        if let q = l.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "http://maps.apple.com/?q=\(q)")
        {
            openURL(url)
        }
    }

    private func triggerAction(_ anim: Binding<Bool>) {
        anim.wrappedValue = true
        triggerHaptic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { anim.wrappedValue = false }
    }
}

struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(
        _ uiViewController: MFMessageComposeViewController, context: Context
    ) {}

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(
            _ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true, completion: nil)
        }
    }
}

private struct SellerView: View {
    let name: String
    let verified: Bool
    let contact: String?
    let reputation: Double?
    var onContactTapped: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.03),
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 52, height: 52)
                Text(initials).font(.headline).foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(firstName).font(.subheadline).bold()
                    if let rep = reputation {
                        Text(String(format: "%.1f", rep))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.systemYellow).opacity(0.22))
                            .cornerRadius(6)
                    }
                }

                if let c = contact, !c.isEmpty {
                    Button(action: { onContactTapped?(c) }) {
                        Text(c)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                } else {
                    Text("Seller").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private var initials: String {
        name.split(separator: " ").first.map { String($0.prefix(1)) } ?? "N"
    }

    private var firstName: String {
        return name.split(separator: " ").first.map { String($0) } ?? name
    }
}

// MARK: - Helper Views for Image Display

private struct LocalImageView: View {
    let image: UIImage
    let index: Int
    let ad: Advert
    @Binding var pageIndex: Int
    @Binding var zoomScale: CGFloat
    @Binding var tempScale: CGFloat
    @Binding var showingImageFullScreen: Bool
    @Binding var selectedFullScreenIndex: Int
    let imageNamespace: Namespace.ID

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: 280)
            .clipped()
            .scaleEffect(zoomScale * tempScale)
            .matchedGeometryEffect(id: "image-\(ad.id.uuidString)-\(index)", in: imageNamespace)
            .cornerRadius(12)
            .padding(.horizontal, 18)
            .tag(index)
            .gesture(
                MagnificationGesture()
                    .onChanged { v in tempScale = v }
                    .onEnded { v in
                        zoomScale *= v
                        tempScale = 1.0
                        zoomScale = min(max(zoomScale, 1.0), 4.0)
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    zoomScale = 1.0
                    tempScale = 1.0
                }
            }
            .onTapGesture {
                selectedFullScreenIndex = index
                withAnimation(.spring()) { showingImageFullScreen = true }
            }
    }
}

private struct RemoteImageView: View {
    let url: URL
    let index: Int
    let ad: Advert

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(ProgressView())
                        .padding(.horizontal, 18)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .cornerRadius(12)
                        .padding(.horizontal, 18)
                case .failure(_):
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title2)
                                Text("Failed to load")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        )
                        .padding(.horizontal, 18)
                @unknown default:
                    EmptyView()
                }
            }
            .tag(index)
        }
    }
}

private struct LocalThumbnailStrip: View {
    let images: [UIImage]
    @Binding var pageIndex: Int
    @Binding var tappedThumbnailIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, ui in
                        Image(uiImage: ui)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 64)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        idx == pageIndex ? Color.accentColor : Color.clear,
                                        lineWidth: 2)
                            )
                            .scaleEffect(tappedThumbnailIndex == idx ? 0.94 : 1.0)
                            .animation(
                                .spring(response: 0.28, dampingFraction: 0.6),
                                value: tappedThumbnailIndex
                            )
                            .id(idx)
                            .padding(.leading, idx == 0 ? 16 : 0)
                            .onTapGesture {
                                triggerHaptic()
                                tappedThumbnailIndex = idx
                                withAnimation(.easeInOut) {
                                    pageIndex = idx
                                }
                                withAnimation(.easeInOut) { proxy.scrollTo(idx, anchor: .center) }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                                    tappedThumbnailIndex = nil
                                }
                            }
                    }
                }
            }
            .frame(height: 78)
            .onChange(of: pageIndex) { newIndex, _ in
                withAnimation(.easeInOut) { proxy.scrollTo(newIndex, anchor: .center) }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(pageIndex, anchor: .center)
                }
            }
        }
    }

    private func triggerHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }
}

private struct RemoteThumbnailStrip: View {
    let urls: [URL]
    @Binding var pageIndex: Int
    @Binding var tappedThumbnailIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 72, height: 64)
                                    .clipped()
                                    .cornerRadius(8)
                            default:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemFill))
                                    .frame(width: 72, height: 64)
                                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    idx == pageIndex ? Color.accentColor : Color.clear, lineWidth: 2
                                )
                        )
                        .scaleEffect(tappedThumbnailIndex == idx ? 0.94 : 1.0)
                        .animation(
                            .spring(response: 0.28, dampingFraction: 0.6),
                            value: tappedThumbnailIndex
                        )
                        .id(idx)
                        .padding(.leading, idx == 0 ? 16 : 0)
                        .onTapGesture {
                            triggerHaptic()
                            tappedThumbnailIndex = idx
                            withAnimation(.easeInOut) {
                                pageIndex = idx
                            }
                            withAnimation(.easeInOut) { proxy.scrollTo(idx, anchor: .center) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                                tappedThumbnailIndex = nil
                            }
                        }
                    }
                }
            }
            .frame(height: 78)
            .onChange(of: pageIndex) { newIndex, _ in
                withAnimation(.easeInOut) { proxy.scrollTo(newIndex, anchor: .center) }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(pageIndex, anchor: .center)
                }
            }
        }
    }

    private func triggerHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }
}
