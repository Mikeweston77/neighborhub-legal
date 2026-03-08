import SwiftUI
import UIKit
import OSLog

struct AISearchResultsView: View {
    @ObservedObject var searchManager: AISearchManager
    let onMessageTap: (CommunityMessage) -> Void
    let onJumpToMessage: ((UUID) -> Void)?
    let onBusinessTap: ((LocalBusiness) -> Void)?
    let onBusinessShare: ((LocalBusiness) -> Void)?
    let onSendMessageToChat: ((String) -> Void)?
    let onSendBusinessListToChat: (([LocalBusiness]) -> Void)?
    @State private var selectedBusiness: LocalBusiness?
    @State private var showBusinessDetail = false
    @State private var showShareSheet = false
    @State private var showShareOptions = false
    @State private var shareText = ""
    @State private var dragOffset: CGSize = .zero
    @State private var businessSearchText: String = ""
    fileprivate let aiLogger = Logger(subsystem: "com.ml5ar66rq7.neighborhub", category: "AI.Search")

    init(searchManager: AISearchManager,
         onMessageTap: @escaping (CommunityMessage) -> Void,
         onBusinessTap: ((LocalBusiness) -> Void)? = nil,
         onBusinessShare: ((LocalBusiness) -> Void)? = nil,
         onSendMessageToChat: ((String) -> Void)? = nil,
         onSendBusinessListToChat: (([LocalBusiness]) -> Void)? = nil,
         onJumpToMessage: ((UUID) -> Void)? = nil) {
        self.searchManager = searchManager
        self.onMessageTap = onMessageTap
        self.onBusinessTap = onBusinessTap
        self.onBusinessShare = onBusinessShare
        self.onSendMessageToChat = onSendMessageToChat
        self.onSendBusinessListToChat = onSendBusinessListToChat
        self.onJumpToMessage = onJumpToMessage
    }

    var body: some View {
        contentView()
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 160 {
                            withAnimation(.spring()) {
                                searchManager.clearSearch()
                            }
                            aiLogger.log("AI search dismissed via drag")
                        }
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
            )
            .sheet(isPresented: $showBusinessDetail) {
                if let business = selectedBusiness {
                    BusinessDetailView(business: business) { business in
                        onBusinessShare?(business)
                    }
                    .presentationDetents([.fraction(0.75), .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [shareText])
            }
            .confirmationDialog("Share Business Results", isPresented: $showShareOptions) {
                Button("Send to Chat") {
                    sendToChat()
                }
                Button("Share to Other Apps") {
                    shareToExternalApps()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("How would you like to share the \(searchManager.businessResults.count) business results?")
            }
    }

    @ViewBuilder
    private func contentView() -> some View {
        Group {
            if searchManager.searchType == .businesses {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.cyan)
                        Text("Business Discovery")
                            .font(.headline)
                            .fontWeight(.bold)
                        Spacer()
                        Button("Share All (\(searchManager.businessResults.count))") {
                            prepareShareText()
                            showShareOptions = true
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .cyan]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                        .shadow(radius: 2)
                        .accessibilityLabel("Share all \(searchManager.businessResults.count) business results")
                        Button(action: {
                            searchManager.clearSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    // Dedicated business search bar
                    HStack {
                        TextField("Search for a business...", text: $businessSearchText, onCommit: {
                            let trimmed = businessSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                searchManager.searchBusinesses(query: trimmed, in: [])
                            }
                        })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                        Button(action: {
                            let trimmed = businessSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                searchManager.searchBusinesses(query: trimmed, in: [])
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.blue)
                        }
                        .padding(.trailing)
                    }
                    .padding(.bottom, 4)

                    if let locationError = searchManager.locationError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(locationError)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal)
                    }

                    Text("Found \(searchManager.businessResults.count) businesses for \"\(searchManager.searchQuery)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(searchManager.displayedBusinessResults) { result in
                                StableBusinessCard(
                                    business: result.business,
                                    matchedTerm: result.matchedTerm,
                                    relevanceScore: result.relevanceScore,
                                    onTap: {
                                        if let onBusinessTap = onBusinessTap {
                                            onBusinessTap(result.business)
                                        } else {
                                            selectedBusiness = result.business
                                            showBusinessDetail = true
                                        }
                                    },
                                    onShare: {
                                        onBusinessShare?(result.business)
                                    }
                                )
                            }

                            if searchManager.hasMoreResults {
                                Button(action: {
                                    searchManager.showAllResults.toggle()
                                }) {
                                    HStack {
                                        Image(systemName: searchManager.showAllResults ? "chevron.up" : "chevron.down")
                                        Text(searchManager.showAllResults ?
                                             "Show Less" :
                                             "Show \(searchManager.businessResults.count - searchManager.maxDisplayResults) More")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .padding(.horizontal)
            } else if searchManager.isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(searchManager.searchType == .businesses ? "Searching local businesses..." : "Searching messages...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            } else if searchManager.searchType == .messages && !searchManager.searchResults.isEmpty {
                // Message search results
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.purple)
                        Text("AI Message Search")
                            .font(.headline)
                            .fontWeight(.bold)
                        Spacer()
                        Button(action: {
                            searchManager.clearSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    Text("Found \(searchManager.searchResults.count) matches for \"\(searchManager.searchQuery)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(searchManager.displayedResults) { result in
                                SearchResultCard(
                                    result: result,
                                    onTap: {
                                        onMessageTap(result.message)
                                    },
                                    onJumpToMessage: {
                                        onJumpToMessage?(result.message.id)
                                    }
                                )
                                .padding(.horizontal)
                            }

                            if searchManager.hasMoreResults {
                                Button(action: {
                                    searchManager.showAllResults.toggle()
                                }) {
                                    HStack {
                                        Image(systemName: searchManager.showAllResults ? "chevron.up" : "chevron.down")
                                        Text(searchManager.showAllResults ?
                                             "Show Less" :
                                             "Show \(searchManager.searchResults.count - searchManager.maxDisplayResults) More")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .padding(.horizontal)
            }
        }
    }

    private func prepareShareText() {
        let businessList = searchManager.businessResults.map { result in
            let business = result.business
            return """
            📍 \(business.name)
            🏷️ \(business.category) • ⭐ \(String(format: "%.1f", business.rating))/5.0
            📍 \(String(format: "%.1f km away", business.distance))
            📍 \(business.address)
            \(business.phone != nil ? "📞 \(business.phone!)" : "")
            \(business.isOpen ? "🟢 Open Now" : "🔴 Closed")
            """
        }.joined(separator: "\n\n")

        shareText = """
        🤖 Business Discovery Results for "\(searchManager.searchQuery)"

        Found \(searchManager.businessResults.count) local businesses in your neighborhood:

        \(businessList)

        📱 Shared from NeighborHub - Your Community App
        🏘️ Connecting neighbors, one discovery at a time!
        """
    }

    private func prepareBusinessListData() -> [LocalBusiness] {
        return searchManager.businessResults.map { $0.business }
    }

    private func sendToChat() {
        if let businessListCallback = onSendBusinessListToChat {
            let businessList = prepareBusinessListData()
            businessListCallback(businessList)
        } else {
            onSendMessageToChat?(shareText)
        }
    }

    private func shareToExternalApps() {
        showShareSheet = true
    }

}
