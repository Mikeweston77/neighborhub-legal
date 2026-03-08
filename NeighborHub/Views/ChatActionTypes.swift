import SwiftUI

/// Enum for chat action types
enum ChatActionType: String, CaseIterable, Identifiable {
    case pinnedMessages
    case search
    case markAllRead
    case muteNotifications
    case exportChat
    case camera
    case attach
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .pinnedMessages: return "pin.circle"
        case .search: return "magnifyingglass.circle"
        case .markAllRead: return "envelope.open.fill"
        case .muteNotifications: return "bell.slash.circle"
        case .exportChat: return "square.and.arrow.up"
        case .camera: return "camera"
    case .attach: return "paperclip"
        @unknown default:
            return "questionmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .pinnedMessages: return .purple
        case .search: return .blue
        case .markAllRead: return .green
        case .muteNotifications: return .orange
        case .exportChat: return .indigo
        case .camera: return .blue
    case .attach: return .pink
        @unknown default:
            return .gray
        }
    }
    
    var label: String {
        switch self {
        case .pinnedMessages: return "Pinned"
        case .search: return "Search"
        case .markAllRead: return "Mark Read"
        case .muteNotifications: return "Mute"
        case .exportChat: return "Export"
        case .camera: return "Camera"
    case .attach: return "Attach"
        @unknown default:
            return "Other"
        }
    }
}

/// Handler typealias for chat actions
typealias ChatActionHandler = (ChatActionType) -> Void

// MARK: - Camera Action Button & Handler

/// Camera action button view
struct CameraActionButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "camera")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.accentColor.opacity(0.13)))
                .shadow(color: Color.black.opacity(0.07), radius: 2, x: 0, y: 1)
        }
        .accessibilityLabel("Open Camera")
    }
}

/// Attachment action button (photo or file) styled to match other circular action buttons
struct AttachmentActionButton: View {
    let action: () -> Void
    var color: Color = .pink
    var label: String = ""
    var isActive: Bool = false

    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                ZStack {
                    if isActive {
                        Circle()
                            .stroke(color, lineWidth: 4)
                            .frame(width: 72, height: 72)
                            .scaleEffect(pulse ? 1.12 : 0.92)
                            .opacity(pulse ? 0.22 : 0.08)
                            .animation(Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                            .onAppear { pulse = true }
                            .onDisappear { pulse = false }
                    }

                    Circle()
                        .fill(Color.white)
                        .frame(width: 56, height: 56)
                        .shadow(color: color.opacity(0.22), radius: 10, x: 0, y: 4)

                    Circle()
                        .fill(color.opacity(0.22))
                        .frame(width: 48, height: 48)

                    Image(systemName: "paperclip")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }
            }
            if !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .accessibilityLabel("Add Photo or File")
    }
}

// Usage Example (in your chat view):
// CameraActionButton { openCamera() }
// Or use ChatActionType.camera in your action menu logic.


// MARK: - TapToDismissActionButtonsModifier

/// A reusable ViewModifier that dismisses action buttons when tapping outside.
struct TapToDismissActionButtonsModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        // Use a full-screen overlay so taps anywhere outside the action buttons are caught.
        // Note: the action buttons view should be placed above this modifier (for example,
        // inside the same ZStack) and given a higher `zIndex` so taps on the buttons
        // still register. Example usage in your chat view:
        // ZStack {
        //   chatContent
        //   if showActionButtons { actionButtons.zIndex(1) }
        // }
        // .tapToDismissActionButtons(isPresented: $showActionButtons)
        content
            .overlay(
                Group {
                    if isPresented {
                        // Use a nearly-transparent color (not fully clear) so it receives touches.
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isPresented = false
                            }
                    }
                }
            )
    }
}

extension View {
    /// Dismisses action buttons when tapping outside the content.
    /// - Parameter isPresented: Binding to the action buttons' visibility state.
    func tapToDismissActionButtons(isPresented: Binding<Bool>) -> some View {
        self.modifier(TapToDismissActionButtonsModifier(isPresented: isPresented))
    }
}
