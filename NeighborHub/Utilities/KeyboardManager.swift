import SwiftUI
import UIKit
import Combine

// MARK: - Keyboard Manager
/// Centralized keyboard management for NeighborHub app
/// Handles keyboard appearance, dismissal, height tracking, and optimizations
class KeyboardManager: ObservableObject {
    static let shared = KeyboardManager()
    
    @Published var keyboardHeight: CGFloat = 0
    @Published var isKeyboardVisible: Bool = false
    @Published var keyboardAnimationDuration: TimeInterval = 0.25
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupKeyboardNotifications()
    }
    
    private func setupKeyboardNotifications() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                
                // Extract animation duration from notification
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
                self?.keyboardAnimationDuration = duration
                
                withAnimation(.easeInOut(duration: duration)) {
                    self?.keyboardHeight = keyboardFrame.height
                    self?.isKeyboardVisible = true
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] notification in
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
                withAnimation(.easeInOut(duration: duration)) {
                    self?.keyboardHeight = 0
                    self?.isKeyboardVisible = false
                }
            }
            .store(in: &cancellables)
    }
    
    /// Dismiss the keyboard globally
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    /// Force keyboard to appear for a specific text field
    func showKeyboard() {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.windows.first?.rootViewController?.view.endEditing(false)
            }
        }
    }
}

// MARK: - Enhanced Text Field Modifier
/// SwiftUI modifier for enhanced text input with keyboard optimizations
struct EnhancedTextInputModifier: ViewModifier {
    let keyboardType: UIKeyboardType
    let autocapitalization: UITextAutocapitalizationType
    let autocorrection: Bool
    let submitLabel: SubmitLabel
    let onSubmit: (() -> Void)?
    let onFocusChange: ((Bool) -> Void)?
    
    @StateObject private var keyboardManager = KeyboardManager.shared
    @FocusState private var isFocused: Bool
    
    init(
        keyboardType: UIKeyboardType = .default,
        autocapitalization: UITextAutocapitalizationType = .sentences,
        autocorrection: Bool = true,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self.keyboardType = keyboardType
        self.autocapitalization = autocapitalization
        self.autocorrection = autocorrection
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
        self.onFocusChange = onFocusChange
    }
    
    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .keyboardType(keyboardType)
            .autocapitalization(autocapitalization)
            .disableAutocorrection(!autocorrection)
            .submitLabel(submitLabel)
            .onSubmit {
                onSubmit?()
            }
            .onChange(of: isFocused) { _, focused in
                onFocusChange?(focused)
                
                // Add haptic feedback for focus changes
                if focused {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        keyboardManager.dismissKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}

// MARK: - Keyboard Avoiding Container
/// Container that automatically adjusts content when keyboard appears
struct KeyboardAvoidingContainer<Content: View>: View {
    let content: Content
    @StateObject private var keyboardManager = KeyboardManager.shared
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(.bottom, keyboardManager.keyboardHeight)
            .animation(.easeInOut(duration: keyboardManager.keyboardAnimationDuration), value: keyboardManager.keyboardHeight)
    }
}

// MARK: - Smart Text Field
/// Enhanced TextField with built-in optimizations and focus management
struct SmartTextField: View {
    let title: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let autocapitalization: UITextAutocapitalizationType
    let autocorrection: Bool
    let submitLabel: SubmitLabel
    let onSubmit: (() -> Void)?
    let onFocusChange: ((Bool) -> Void)?
    
    @FocusState private var isFocused: Bool
    @StateObject private var keyboardManager = KeyboardManager.shared
    
    init(
        _ title: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: UITextAutocapitalizationType = .sentences,
        autocorrection: Bool = true,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self.title = title
        self._text = text
        self.keyboardType = keyboardType
        self.autocapitalization = autocapitalization
        self.autocorrection = autocorrection
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
        self.onFocusChange = onFocusChange
    }
    
    var body: some View {
        TextField(title, text: $text)
            .focused($isFocused)
            .keyboardType(keyboardType)
            .autocapitalization(autocapitalization)
            .disableAutocorrection(!autocorrection)
            .submitLabel(submitLabel)
            .onSubmit {
                onSubmit?()
            }
            .onChange(of: isFocused) { _, focused in
                onFocusChange?(focused)
                
                // Add haptic feedback for focus changes
                if focused {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
            }
    }
}

// MARK: - Smart Text Editor
/// Enhanced TextEditor with built-in optimizations and focus management
struct SmartTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat
    let autocapitalization: UITextAutocapitalizationType
    let autocorrection: Bool
    let onFocusChange: ((Bool) -> Void)?
    
    @FocusState private var isFocused: Bool
    @StateObject private var keyboardManager = KeyboardManager.shared
    
    init(
        text: Binding<String>,
        placeholder: String = "Enter text...",
        minHeight: CGFloat = 80,
        autocapitalization: UITextAutocapitalizationType = .sentences,
        autocorrection: Bool = true,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.autocapitalization = autocapitalization
        self.autocorrection = autocorrection
        self.onFocusChange = onFocusChange
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
            }
            
            TextEditor(text: $text)
                .focused($isFocused)
                .autocapitalization(autocapitalization)
                .disableAutocorrection(!autocorrection)
                .frame(minHeight: minHeight)
                .onChange(of: isFocused) { _, focused in
                    onFocusChange?(focused)
                    
                    // Add haptic feedback for focus changes
                    if focused {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                }
        }
    }
}

// MARK: - View Extensions
extension View {
    /// Apply enhanced text input optimizations
    func enhancedTextInput(
        keyboardType: UIKeyboardType = .default,
        autocapitalization: UITextAutocapitalizationType = .sentences,
        autocorrection: Bool = true,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(EnhancedTextInputModifier(
            keyboardType: keyboardType,
            autocapitalization: autocapitalization,
            autocorrection: autocorrection,
            submitLabel: submitLabel,
            onSubmit: onSubmit,
            onFocusChange: onFocusChange
        ))
    }
    
    /// Wrap content in keyboard avoiding container
    func keyboardAvoiding() -> some View {
        KeyboardAvoidingContainer { self }
    }
    
    /// Add tap gesture to dismiss keyboard
    func dismissKeyboardOnTap() -> some View {
        onTapGesture {
            KeyboardManager.shared.dismissKeyboard()
        }
    }
    
    /// Add keyboard toolbar with done button
    func keyboardToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    KeyboardManager.shared.dismissKeyboard()
                }
                .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Focus Management
/// Enhanced focus state management for complex forms
class FocusManager: ObservableObject {
    @Published var currentField: AnyHashable?
    
    func focus<T: Hashable>(on field: T) {
        currentField = AnyHashable(field)
    }
    
    func clearFocus() {
        currentField = nil
    }
    
    func nextField<T: CaseIterable & Hashable>(from current: T) -> T? where T.AllCases.Index: Comparable {
        let allCases = Array(T.allCases)
        guard let currentIndex = allCases.firstIndex(of: current) else { return nil }
        let nextIndex = allCases.index(after: currentIndex)
        return nextIndex < allCases.endIndex ? allCases[nextIndex] : nil
    }
}

// MARK: - Performance Optimizations
/// Debounced text input to improve performance during typing
@propertyWrapper
struct DebouncedText {
    @State private var debouncedValue: String = ""
    @State private var currentValue: String = ""
    private let delay: TimeInterval
    private let onValueChanged: ((String) -> Void)?
    
    var wrappedValue: String {
        get { currentValue }
        nonmutating set {
            currentValue = newValue
            debounceUpdate()
        }
    }
    
    var projectedValue: Binding<String> {
        Binding(
            get: { currentValue },
            set: { newValue in
                currentValue = newValue
                debounceUpdate()
            }
        )
    }
    
    init(wrappedValue: String = "", delay: TimeInterval = 0.3, onValueChanged: ((String) -> Void)? = nil) {
        self.delay = delay
        self.onValueChanged = onValueChanged
        self._currentValue = State(initialValue: wrappedValue)
        self._debouncedValue = State(initialValue: wrappedValue)
    }
    
    private func debounceUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [currentValue] in
            if self.currentValue == currentValue {
                self.debouncedValue = currentValue
                self.onValueChanged?(currentValue)
            }
        }
    }
    
    /// Get the debounced value
    func getDebouncedValue() -> String {
        debouncedValue
    }
}
