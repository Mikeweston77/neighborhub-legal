import SwiftUI

// MARK: - Moderation Settings Helper Views
struct ModerationLevelRow: View {
    let level: ModerationLevel
    let description: String
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
            
            Text(level.displayName)
                .font(.caption)
                .fontWeight(.medium)
            
            Text("- \(description)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private var levelColor: Color {
        switch level {
        case .disabled: return .gray
        case .light: return .green
        case .moderate: return .orange
        case .strict: return .red
        }
    }
}