import SwiftUI

struct HomeDigestPreview: View {
    private func friendlyDigest(
        hasPendingWellnessCheckin: Bool = false,
        unreadMessagesCount: Int = 2,
        activeReminderCount: Int = 1,
        upcomingEventsCount: Int = 1,
        precipitationChancePercent: Int = 30,
        hasActivePollWithoutVote: Bool = true
    ) -> String {
        // Reuse the same user-name greeting logic as HomeView
        let rawName = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstName = rawName.split(separator: " ").first.map(String.init) ?? "Neighbor"

        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Good morning"
        case 12..<17: greeting = "Good afternoon"
        case 17..<22: greeting = "Good evening"
        default: greeting = "Hello"
        }

        let weatherText = "Today's forecast: \(precipitationChancePercent)% chance of rain."

        var parts: [String] = []
        if upcomingEventsCount > 0 {
            parts.append("\(upcomingEventsCount) upcoming event\(upcomingEventsCount == 1 ? "" : "s")")
        }
        if unreadMessagesCount > 0 {
            parts.append("\(unreadMessagesCount) unread chat\(unreadMessagesCount == 1 ? "" : "s")")
        }
        if hasActivePollWithoutVote {
            parts.append("a poll awaiting your vote")
        }
        if activeReminderCount > 0 {
            parts.append("\(activeReminderCount) active reminder\(activeReminderCount == 1 ? "" : "s")")
        }

        let activitySummary = parts.isEmpty ? "You're all caught up." : parts.joined(separator: ", ") + "."

        return "\(greeting), \(firstName)! \(weatherText) \(activitySummary)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Sample Daily Digest")
                .font(.title2.bold())
            Text(friendlyDigest())
                .font(.body)
                .multilineTextAlignment(.leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding()
            Spacer()
        }
        .padding()
    }
}

struct HomeDigestPreview_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HomeDigestPreview()
                .previewDisplayName("Sample Digest")
                .preferredColorScheme(.light)

            HomeDigestPreview()
                .previewDisplayName("Dark Mode")
                .preferredColorScheme(.dark)
        }
    }
}
