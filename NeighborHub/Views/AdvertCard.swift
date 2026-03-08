import SwiftUI

struct AdvertCard: View {
    let ad: Advert
    @Environment(\.colorScheme) private var colorScheme

    private var cardCorner: CGFloat { 14 }

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.10, green: 0.12, blue: 0.18),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(
                colors: [Color.white, Color(red: 0.94, green: 0.97, blue: 1.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var rimGradient: LinearGradient {
        if colorScheme == .dark {
            LinearGradient(
                colors: [Color.blue.opacity(0.16), Color.purple.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LinearGradient(
                colors: [Color.blue.opacity(0.12), Color.cyan.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Image with subtle 3D tilt and rim
            ZStack {
                if let ui = ad.uiImage {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(10)
                        .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0))
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.6 : 0.12),
                            radius: 8, x: 0, y: 6)
                } else if let urlStr = ad.imageStorageURL ?? ad.imageStorageURLs?.first,
                    let url = URL(string: urlStr)
                {
                    // Load remote image asynchronously
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemFill))
                                .frame(width: 100, height: 100)
                                .overlay(ProgressView())
                                .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0))
                                .shadow(
                                    color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.08),
                                    radius: 6, x: 0, y: 4)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                                .cornerRadius(10)
                                .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0))
                                .shadow(
                                    color: Color.black.opacity(colorScheme == .dark ? 0.6 : 0.12),
                                    radius: 8, x: 0, y: 6)
                        default:
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemFill))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "photo").font(.largeTitle).foregroundColor(
                                        .secondary)
                                )
                                .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0))
                                .shadow(
                                    color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.08),
                                    radius: 6, x: 0, y: 4)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "photo").font(.largeTitle).foregroundColor(.secondary)
                        )
                        .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0))
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.08),
                            radius: 6, x: 0, y: 4)
                }

                // Image count badge when multiple images present
                if let count = imageCount(for: ad), count > 1 {
                    ZStack {
                        Circle().fill(Color.black.opacity(colorScheme == .dark ? 0.65 : 0.6))
                            .frame(width: 28, height: 28)
                        Text("\(count)")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                    }
                    .offset(x: 36, y: -36)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(ad.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                    Spacer()
                    if ad.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.6), radius: 6, x: 0, y: 2)
                    }
                }

                Text(ad.summary)
                    .font(.subheadline)
                    .foregroundColor(
                        colorScheme == .dark ? Color(.secondaryLabel) : Color(.secondaryLabel)
                    )
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let price = ad.price {
                        Text(price == 0 ? "Free" : String(format: "%.0f %@", price, ad.currency))
                            .font(.subheadline).bold()
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                    Text(ad.locationName ?? "Nearby")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Show attachment recovery option if needed
                if hasAttachmentIssues(ad) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text("Attachment issue")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Recover") {
                            AttachmentRecoveryManager.shared.recoverSpecificAdvert(ad.id)
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(12)
        .background(
            ZStack {
                // Base fill (plain system background to hide the gradient)
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .fill(Color(.systemBackground))

                // Soft rim light
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .stroke(rimGradient, lineWidth: 1.5)
                    .blendMode(.overlay)

                // Subtle inner highlight to give bevel / 3D feel
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.6), Color.clear,
                            ], startPoint: .topLeading, endPoint: .center)
                    )
                    .mask(
                        RoundedRectangle(cornerRadius: cardCorner, style: .continuous).fill(
                            LinearGradient(
                                colors: [Color.black, Color.clear], startPoint: .topLeading,
                                endPoint: .center)))

                // Accent glow (top-right)
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 2
                    )
                    .blur(radius: 6)
                    .opacity(0.9)
            }
        )
        .compositingGroup()
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.08),
            radius: colorScheme == .dark ? 18 : 8, x: 0, y: colorScheme == .dark ? 10 : 4
        )
        .cornerRadius(cardCorner)
    }
}

extension AdvertCard {
    /// Determine approximate number of images available for the advert from local, embedded, or remote sources
    private func imageCount(for ad: Advert) -> Int? {
        if let paths = ad.imageLocalPaths, !paths.isEmpty { return paths.count }
        if let arr = ad.imageDatas, !arr.isEmpty { return arr.count }
        if ad.imageData != nil { return 1 }
        if let arr = ad.imageStorageURLs, !arr.isEmpty { return arr.count }
        if ad.imageStorageURL != nil { return 1 }
        // uiImage may come from a single local path — we can't know other remote URLs here
        return nil
    }

    /// Check if advert has attachment issues (local images but missing remote URLs)
    private func hasAttachmentIssues(_ ad: Advert) -> Bool {
        let hasLocalImages =
            (ad.imageLocalPath != nil)
            || (ad.imageLocalPaths != nil && !ad.imageLocalPaths!.isEmpty)
        let missingStorageURL =
            ad.imageStorageURL == nil
            || (ad.imageStorageURLs == nil || ad.imageStorageURLs!.isEmpty)

        return hasLocalImages && missingStorageURL
    }
}
