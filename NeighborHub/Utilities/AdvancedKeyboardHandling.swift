import SwiftUI
import UIKit

// MARK: - Advanced Keyboard Handling for NeighborHub
/// Additional utilities for advanced keyboard handling specific to NeighborHub features

// MARK: - Keyboard-Aware Form Container
/// A container that automatically handles keyboard navigation and form optimization
struct KeyboardAwareForm<Content: View>: View {
    let content: Content
    @StateObject private var keyboardManager = KeyboardManager.shared
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(.horizontal)
                .padding(.bottom, keyboardManager.keyboardHeight + 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: keyboardManager.isKeyboardVisible) { _, isVisible in
                if isVisible {
                    // Auto-scroll to keep focused field visible
                    withAnimation(.easeInOut(duration: keyboardManager.keyboardAnimationDuration)) {
                        // Scroll to bottom when keyboard appears
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .id("keyboardAwareForm")
    }
}

// MARK: - Auto-Focus Chain Manager
/// Manages automatic focus chain progression for forms
class AutoFocusChain: ObservableObject {
    @Published var currentFieldIndex: Int = 0
    private var fields: [AnyHashable] = []
    
    func setFields<T: Hashable>(_ fieldArray: [T]) {
        self.fields = fieldArray.map { AnyHashable($0) }
    }
    
    func nextField() -> AnyHashable? {
        guard currentFieldIndex < fields.count - 1 else { return nil }
        currentFieldIndex += 1
        return fields[currentFieldIndex]
    }
    
    func previousField() -> AnyHashable? {
        guard currentFieldIndex > 0 else { return nil }
        currentFieldIndex -= 1
        return fields[currentFieldIndex]
    }
    
    func jumpToField(at index: Int) -> AnyHashable? {
        guard index >= 0 && index < fields.count else { return nil }
        currentFieldIndex = index
        return fields[index]
    }
    
    func reset() {
        currentFieldIndex = 0
    }
}

// MARK: - Smart Form Navigation Toolbar
/// Custom keyboard toolbar with navigation buttons
struct SmartFormToolbar: ToolbarContent {
    @ObservedObject var autoFocus: AutoFocusChain
    @FocusState.Binding var focusedField: AnyHashable?
    let onDone: (() -> Void)?
    
    init(autoFocus: AutoFocusChain, focusedField: FocusState<AnyHashable?>.Binding, onDone: (() -> Void)? = nil) {
        self.autoFocus = autoFocus
        self._focusedField = focusedField
        self.onDone = onDone
    }
    
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            // Previous button
            Button(action: {
                if let previousField = autoFocus.previousField() {
                    focusedField = previousField
                }
            }) {
                Image(systemName: "chevron.up")
            }
            .disabled(autoFocus.currentFieldIndex == 0)
            
            // Next button
            Button(action: {
                if let nextField = autoFocus.nextField() {
                    focusedField = nextField
                } else {
                    // Last field - dismiss keyboard or call done
                    KeyboardManager.shared.dismissKeyboard()
                    onDone?()
                }
            }) {
                Image(systemName: "chevron.down")
            }
            
            Spacer()
            
            // Done button
            Button("Done") {
                KeyboardManager.shared.dismissKeyboard()
                onDone?()
            }
            .fontWeight(.semibold)
        }
    }
}

// MARK: - Keyboard Performance Monitor
/// Monitors keyboard performance and provides optimization suggestions
class KeyboardPerformanceMonitor: ObservableObject {
    @Published var averageResponseTime: TimeInterval = 0
    @Published var isPerformanceOptimal: Bool = true
    
    private var responseTimes: [TimeInterval] = []
    private var lastKeyPressTime: Date?
    
    func recordKeyPress() {
        let now = Date()
        if let lastTime = lastKeyPressTime {
            let responseTime = now.timeIntervalSince(lastTime)
            responseTimes.append(responseTime)
            
            // Keep only last 20 measurements
            if responseTimes.count > 20 {
                responseTimes.removeFirst()
            }
            
            // Calculate average
            averageResponseTime = responseTimes.reduce(0, +) / Double(responseTimes.count)
            
            // Check if performance is optimal (< 100ms average)
            isPerformanceOptimal = averageResponseTime < 0.1
        }
        lastKeyPressTime = now
    }
    
    func getOptimizationSuggestions() -> [String] {
        var suggestions: [String] = []
        
        if !isPerformanceOptimal {
            suggestions.append("Consider reducing autocorrection for better performance")
            suggestions.append("Try using .disableAutocorrection(true) for numeric fields")
            suggestions.append("Use appropriate keyboard types for each field")
        }
        
        if averageResponseTime > 0.2 {
            suggestions.append("Keyboard response is slow - consider device optimization")
        }
        
        return suggestions
    }
}

// MARK: - Context-Aware Keyboard Configuration
/// Automatically configures keyboard settings based on content context
struct ContextAwareKeyboard: ViewModifier {
    let contentType: ContentType
    
    enum ContentType {
        case name, email, phone, address, password, search, message, number, currency
        
        var keyboardType: UIKeyboardType {
            switch self {
            case .email: return .emailAddress
            case .phone: return .phonePad
            case .number: return .numberPad
            case .currency: return .decimalPad
            case .search: return .webSearch
            default: return .default
            }
        }
        
        var autocapitalization: UITextAutocapitalizationType {
            switch self {
            case .name, .address: return .words
            case .message: return .sentences
            case .email, .phone, .password, .number, .currency: return .none
            case .search: return .none
            }
        }
        
        var autocorrection: Bool {
            switch self {
            case .email, .phone, .password, .number, .currency: return false
            case .name, .address, .message, .search: return true
            }
        }
        
        var submitLabel: SubmitLabel {
            switch self {
            case .search: return .search
            case .message: return .send
            case .email, .password: return .done
            default: return .next
            }
        }
    }
    
    func body(content: Content) -> some View {
        content
            .keyboardType(contentType.keyboardType)
            .autocapitalization(contentType.autocapitalization)
            .disableAutocorrection(!contentType.autocorrection)
            .submitLabel(contentType.submitLabel)
    }
}

// MARK: - Accessibility Enhanced Text Input
/// Text input with enhanced accessibility features
struct AccessibleTextInput: View {
    let label: String
    @Binding var text: String
    let contentType: ContextAwareKeyboard.ContentType
    let isRequired: Bool
    let accessibilityHint: String?
    
    @FocusState private var isFocused: Bool
    @StateObject private var performanceMonitor = KeyboardPerformanceMonitor()
    
    init(
        _ label: String,
        text: Binding<String>,
        contentType: ContextAwareKeyboard.ContentType = .name,
        isRequired: Bool = false,
        accessibilityHint: String? = nil
    ) {
        self.label = label
        self._text = text
        self.contentType = contentType
        self.isRequired = isRequired
        self.accessibilityHint = accessibilityHint
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
            
            TextField(label, text: $text)
                .focused($isFocused)
                .modifier(ContextAwareKeyboard(contentType: contentType))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .accessibilityLabel(label)
                .accessibilityHint(accessibilityHint ?? "")
                .accessibilityValue(text.isEmpty ? "Empty" : text)
                .onChange(of: text) { _, _ in
                    performanceMonitor.recordKeyPress()
                }
            
            // Performance indicator (only shown if performance is poor)
            if !performanceMonitor.isPerformanceOptimal {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Keyboard response slow")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Extensions
extension View {
    /// Apply context-aware keyboard configuration
    func contextAwareKeyboard(_ contentType: ContextAwareKeyboard.ContentType) -> some View {
        modifier(ContextAwareKeyboard(contentType: contentType))
    }
    
    /// Wrap in keyboard-aware form container
    func keyboardAwareForm() -> some View {
        KeyboardAwareForm { self }
    }
}
