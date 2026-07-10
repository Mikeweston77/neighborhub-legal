import SwiftUI
import AVKit
import QuickLook
#if canImport(UIKit)
import UIKit
#endif

/// Native list view for Telegram messages received via the `telegramWebhook`
/// Cloud Function and stored in Firestore's `telegramMessages` collection.
struct TelegramAlertsListView: View {
    let messages: [TelegramMessage]
    var canLoadOlder: Bool = false
    var isLoadingOlder: Bool = false
    var onLoadOlder: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var activeMedia: TelegramMediaDestination?
    @State private var selectedFilter: TelegramFeedFilter = .all
    @State private var isSelectingAlertImages: Bool = false
    @State private var selectedImageMessageIDs: Set<String> = []
    @State private var isPreparingShareItems: Bool = false
    @State private var isCopyingImages: Bool = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet: Bool = false
    @State private var copyFeedbackMessage: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if filteredMessages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                loadOlderBar
            }
            .navigationTitle("Camera Alerts / Logs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedFilter == .alerts {
                        Button(isSelectingAlertImages ? "Done" : "Select") {
                            if isSelectingAlertImages {
                                isSelectingAlertImages = false
                                selectedImageMessageIDs.removeAll()
                            } else {
                                isSelectingAlertImages = true
                            }
                        }
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isSelectingAlertImages && selectedFilter == .alerts {
                        if isCopyingImages || isPreparingShareItems {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button("Copy") {
                            copySelectedImages()
                        }
                        .disabled(selectedImageMessageIDs.isEmpty || isCopyingImages || isPreparingShareItems)

                        Button("Send") {
                            shareSelectedImages()
                        }
                        .disabled(selectedImageMessageIDs.isEmpty || isCopyingImages || isPreparingShareItems)
                    }

                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(items: shareItems)
        }
        .alert("Images", isPresented: .constant(copyFeedbackMessage != nil)) {
            Button("OK") {
                copyFeedbackMessage = nil
            }
        } message: {
            Text(copyFeedbackMessage ?? "")
        }
        .fullScreenCover(item: $activeMedia) { media in
            switch media {
            case .image(let url):
                InteractiveTelegramImageView(imageURL: url) {
                    activeMedia = nil
                }
            case .video(let url):
                InAppMediaPlayerView(url: url, title: "Video") {
                    activeMedia = nil
                }
            case .audio(let url):
                InAppMediaPlayerView(url: url, title: "Audio") {
                    activeMedia = nil
                }
            case .document(let url):
                InAppDocumentPreview(url: url) {
                    activeMedia = nil
                }
            }
        }
    }

    private var filteredMessages: [TelegramMessage] {
        switch selectedFilter {
        case .all:
            return messages
        case .alerts:
            return messages.filter { message in
                // Alerts tab focuses on camera/photo/media content.
                message.hasMedia
            }
        case .logs:
            return messages.filter { message in
                // Logs tab focuses on written updates and excludes media-heavy posts.
                !message.hasMedia && !cleanedMessageText(message.text).isEmpty
            }
        }
    }

    private func cleanedMessageText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            Picker("Filter", selection: $selectedFilter) {
                ForEach(TelegramFeedFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("\(filteredMessages.count) shown")
                Spacer()
                Text("\(messages.count) total")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.title3.weight(.semibold))
            Text(emptyStateSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        List(filteredMessages) { message in
            TelegramMessageRow(
                message: message,
                dateFormatter: dateFormatter,
                isImageSelectionMode: isSelectingAlertImages && selectedFilter == .alerts,
                isImageSelected: selectedImageMessageIDs.contains(message.id),
                onToggleImageSelection: {
                    toggleImageSelection(for: message)
                },
                onOpenMedia: { destination in
                    activeMedia = destination
                }
            )
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        }
        .listStyle(.plain)
    }

    private func toggleImageSelection(for message: TelegramMessage) {
        guard message.mediaType == "photo", message.mediaProxyURL() != nil else {
            return
        }

        if selectedImageMessageIDs.contains(message.id) {
            selectedImageMessageIDs.remove(message.id)
        } else {
            selectedImageMessageIDs.insert(message.id)
        }
    }

    private var selectedImageURLs: [URL] {
        messages
            .filter { selectedImageMessageIDs.contains($0.id) && $0.mediaType == "photo" }
            .compactMap { $0.mediaProxyURL() }
    }

    private func shareSelectedImages() {
        let urls = selectedImageURLs
        guard !urls.isEmpty else { return }

        isPreparingShareItems = true
        Task {
            let downloaded = await downloadImages(from: urls)
            await MainActor.run {
                isPreparingShareItems = false
                shareItems = downloaded.isEmpty ? urls : downloaded
                showShareSheet = true
            }
        }
    }

    private func copySelectedImages() {
        #if canImport(UIKit)
        let urls = selectedImageURLs
        guard !urls.isEmpty else { return }

        isCopyingImages = true
        Task {
            let downloaded = await downloadImages(from: urls)
            await MainActor.run {
                isCopyingImages = false
                if downloaded.isEmpty {
                    UIPasteboard.general.string = urls.map(\ .absoluteString).joined(separator: "\n")
                    copyFeedbackMessage = "Could not fetch image bytes. Copied \(urls.count) image link(s) instead."
                    return
                }

                UIPasteboard.general.images = downloaded
                copyFeedbackMessage = "Copied \(downloaded.count) image(s)."
            }
        }
        #endif
    }

    private func downloadImages(from urls: [URL]) async -> [UIImage] {
        #if canImport(UIKit)
        var images: [UIImage] = []
        images.reserveCapacity(urls.count)

        for url in urls {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    images.append(image)
                }
            } catch {
                continue
            }
        }

        return images
        #else
        return []
        #endif
    }

    private var emptyStateTitle: String {
        switch selectedFilter {
        case .all: return "No Camera Alerts / Logs"
        case .alerts: return "No Alerts"
        case .logs: return "No Logs"
        }
    }

    private var emptyStateSubtitle: String {
        switch selectedFilter {
        case .all:
            return "Messages forwarded from your Telegram channel will appear here."
        case .alerts:
            return "Photos and media posts from Telegram will appear here."
        case .logs:
            return "Written Telegram messages will appear here."
        }
    }

    private var loadOlderBar: some View {
        Group {
            if canLoadOlder || isLoadingOlder {
                HStack {
                    Spacer()
                    if isLoadingOlder {
                        ProgressView("Loading older messages...")
                            .font(.footnote)
                    } else {
                        Button("Load Older") {
                            onLoadOlder?()
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }
}

private enum TelegramFeedFilter: String, CaseIterable, Identifiable {
    case all
    case alerts
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .alerts: return "Alerts"
        case .logs: return "Logs"
        }
    }
}

private enum TelegramMediaDestination: Identifiable {
    case image(URL)
    case video(URL)
    case audio(URL)
    case document(URL)

    var id: String {
        switch self {
        case .image(let url):
            return "image-\(url.absoluteString)"
        case .video(let url):
            return "video-\(url.absoluteString)"
        case .audio(let url):
            return "audio-\(url.absoluteString)"
        case .document(let url):
            return "document-\(url.absoluteString)"
        }
    }
}

private struct TelegramMessageRow: View {
    let message: TelegramMessage
    let dateFormatter: DateFormatter
    var isImageSelectionMode: Bool = false
    var isImageSelected: Bool = false
    var onToggleImageSelection: (() -> Void)? = nil
    let onOpenMedia: (TelegramMediaDestination) -> Void

    @State private var isExpanded = false

    private var displayTitle: String {
        switch message.category.lowercased() {
        case "logs":
            return "Camera Log"
        case "alerts":
            return "Camera Alert"
        default:
            return "Camera Message"
        }
    }

    private var displayText: String {
        sanitizedText(message.text)
    }

    private func sanitizedText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let prefixes = [message.senderName, message.chatTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for prefix in prefixes {
            let candidates = ["\(prefix): ", "\(prefix):", "\(prefix) - ", "\(prefix)\n"]
            if let candidate = candidates.first(where: { trimmed.hasPrefix($0) }) {
                let stripped = String(trimmed.dropFirst(candidate.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty {
                    return stripped
                }
            }
        }

        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(dateFormatter.string(from: message.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !displayText.isEmpty {
                Text(displayText)
                    .font(.body)
                    .lineLimit(isExpanded ? .max : 6)
            }

            if message.hasMedia {
                TelegramMediaView(
                    message: message,
                    isImageSelectionMode: isImageSelectionMode,
                    isImageSelected: isImageSelected,
                    onToggleImageSelection: onToggleImageSelection,
                    onOpenMedia: onOpenMedia
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !displayText.isEmpty && displayText.split(separator: "\n").count > 6 {
                Button(action: { isExpanded.toggle() }) {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TelegramMediaView: View {
    let message: TelegramMessage
    var isImageSelectionMode: Bool = false
    var isImageSelected: Bool = false
    var onToggleImageSelection: (() -> Void)? = nil
    let onOpenMedia: (TelegramMediaDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch message.mediaType {
            case "photo":
                photoView
            case "video":
                videoView
            case "audio":
                audioView
            case "document":
                documentView
            default:
                EmptyView()
            }
        }
        .padding(.top, 4)
    }

    private var photoView: some View {
        Group {
            if let url = message.mediaProxyURL() {
                Button {
                    if isImageSelectionMode {
                        onToggleImageSelection?()
                    } else {
                        onOpenMedia(.image(url))
                    }
                } label: {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            ZStack(alignment: .bottomTrailing) {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(10)
                                    .frame(maxHeight: 300)

                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.semibold))
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .padding(10)

                                if isImageSelectionMode {
                                    Image(systemName: isImageSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(isImageSelected ? .green : .white)
                                        .shadow(radius: 4)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                }
                            }
                        case .failure:
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                Text("Failed to load photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(height: 60)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        case .empty:
                            HStack(spacing: 8) {
                                ProgressView().tint(.accentColor)
                                Text("Loading photo...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(height: 60)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                fallbackRow(icon: "photo", text: "Photo (no file ID)")
            }
        }
    }

    private var videoView: some View {
        Group {
            if let url = message.mediaProxyURL() {
                Button {
                    onOpenMedia(.video(url))
                } label: {
                    mediaActionRow(
                        icon: "play.circle.fill",
                        title: "Video",
                        subtitle: "Tap to open"
                    )
                }
                .buttonStyle(.plain)
            } else {
                fallbackRow(icon: "video", text: "Video (no file ID)")
            }
        }
    }

    private var audioView: some View {
        Group {
            if let url = message.mediaProxyURL() {
                Button {
                    onOpenMedia(.audio(url))
                } label: {
                    mediaActionRow(
                        icon: "waveform.circle.fill",
                        title: "Audio",
                        subtitle: "Tap to open"
                    )
                }
                .buttonStyle(.plain)
            } else {
                fallbackRow(icon: "waveform", text: "Audio (no file ID)")
            }
        }
    }

    private var documentView: some View {
        Group {
            if let url = message.mediaProxyURL() {
                Button {
                    onOpenMedia(.document(url))
                } label: {
                    mediaActionRow(
                        icon: "doc.text.fill",
                        title: "Document",
                        subtitle: "Tap to open"
                    )
                }
                .buttonStyle(.plain)
            } else {
                fallbackRow(icon: "doc", text: "Document (no file ID)")
            }
        }
    }

    private func mediaActionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func fallbackRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct InteractiveTelegramImageView: View {
    let imageURL: URL
    let onClose: () -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var lastDragOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoomScale)
                            .offset(dragOffset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoomScale = min(max(lastZoomScale * value, 1.0), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastZoomScale = zoomScale
                                        if zoomScale <= 1.01 {
                                            zoomScale = 1.0
                                            lastZoomScale = 1.0
                                            dragOffset = .zero
                                            lastDragOffset = .zero
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard zoomScale > 1.0 else { return }
                                        dragOffset = CGSize(
                                            width: lastDragOffset.width + value.translation.width,
                                            height: lastDragOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastDragOffset = dragOffset
                                    }
                            )
                            .onTapGesture(count: 2) {
                                if zoomScale > 1.0 {
                                    zoomScale = 1.0
                                    lastZoomScale = 1.0
                                    dragOffset = .zero
                                    lastDragOffset = .zero
                                } else {
                                    zoomScale = 2.0
                                    lastZoomScale = 2.0
                                }
                            }
                    case .failure:
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text("Failed to load image")
                                .foregroundStyle(.white)
                        }
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose() }
                }
            }
        }
    }
}

private struct InAppMediaPlayerView: View {
    let url: URL
    let title: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            AVPlayerContainer(url: url)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { onClose() }
                    }
                }
        }
    }
}

private struct AVPlayerContainer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.player?.play()
        controller.allowsPictureInPicturePlayback = false
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

private struct InAppDocumentPreview: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            QuickLookController(url: url)
                .navigationTitle("Document")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { onClose() }
                    }
                }
        }
    }
}

private struct QuickLookController: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

#Preview {
    TelegramAlertsListView(messages: [
        TelegramMessage(
            id: "1", messageId: 1, chatId: -100123456,
            chatTitle: "Waterfall Security", senderName: "Admin",
            text: "Suspicious vehicle spotted on Main Rd. White sedan, no plates.",
            mediaType: "photo", fileId: "abc123",
            category: "alerts", categories: ["alerts"], date: Date()
        ),
        TelegramMessage(
            id: "2", messageId: 2, chatId: -100123456,
            chatTitle: "Waterfall Security", senderName: "John D.",
            text: "All clear on patrol route.",
            mediaType: "none", fileId: "",
            category: "general", categories: ["general"], date: Date().addingTimeInterval(-3600)
        )
    ])
}
