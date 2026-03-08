import SwiftUI

struct EventDetailView: View {
    let event: LocalEvent
    var onDismiss: () -> Void = {}

    @State private var showFullScreenImage: Bool = false
    @State private var showMapOptions: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Attachment (image) preview
                    if let imageData = event.imageData, let uiImage = UIImage(data: imageData) {
                        Button(action: { showFullScreenImage = true }) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .clipped()
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showFullScreenImage) {
                            EventFullScreenView(event: event) {
                                showFullScreenImage = false
                            }
                        }
                    }

                    Text(event.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(event.eventType.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.accentColor)

                    // Location
                    if let location = event.location, !location.isEmpty {
                        Button(action: { showMapOptions = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.red)
                                Text(location)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .actionSheet(isPresented: $showMapOptions) {
                            ActionSheet(
                                title: Text("Open Location"),
                                message: Text("Choose a maps app to open this location."),
                                buttons: [
                                    .default(Text("Apple Maps")) { openInAppleMaps(address: location) },
                                    .default(Text("Google Maps")) { openInGoogleMaps(address: location) },
                                    .cancel()
                                ]
                            )
                        }
                    }

                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.top, 6)
                    }

                    // File attachment
                    if let fileURL = event.fileURL {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            Text(fileURL.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer()
                            Menu {
                                Button(action: { UIApplication.shared.open(fileURL) }) { Label("Open", systemImage: "arrow.up.right.square") }
                                Button(action: { UIPasteboard.general.string = fileURL.absoluteString }) { Label("Copy Link", systemImage: "doc.on.doc") }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 6)
                    }

                    Divider()

                    // Contact details
                    if let contact = event.contactName, !contact.isEmpty || (event.contactCell != nil && !(event.contactCell!.isEmpty)) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let contact = event.contactName, !contact.isEmpty {
                                Text(contact)
                                    .font(.headline)
                            }
                            if let cell = event.contactCell, !cell.isEmpty {
                                HStack(spacing: 8) {
                                    Text(cell)
                                        .font(.subheadline)
                                    Spacer()
                                    Menu {
                                        Button(action: {
                                            if let url = URL(string: "tel:\(cell.filter { $0.isNumber })") { UIApplication.shared.open(url) }
                                        }) { Label("Call", systemImage: "phone.fill") }
                                        Button(action: {
                                            var waNumber = cell.filter { $0.isNumber }
                                            if waNumber.hasPrefix("0") && waNumber.count == 10 { waNumber = "27" + waNumber.dropFirst() }
                                            if let url = URL(string: "https://wa.me/\(waNumber)") { UIApplication.shared.open(url) }
                                        }) { Label("WhatsApp", systemImage: "message.circle.fill") }
                                        Divider()
                                        Button(action: { UIPasteboard.general.string = cell }) { Label("Copy", systemImage: "doc.on.doc") }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title3)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            // Removed navigation bar title and toolbar
        }
    }

    // MARK: - Maps helpers
    private func openInAppleMaps(address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") { UIApplication.shared.open(url) }
    }

    private func openInGoogleMaps(address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let googleMapsURL = URL(string: "comgooglemaps://?q=\(encoded)")
        if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
        else if let web = URL(string: "https://maps.google.com/?q=\(encoded)") { UIApplication.shared.open(web) }
    }
}
