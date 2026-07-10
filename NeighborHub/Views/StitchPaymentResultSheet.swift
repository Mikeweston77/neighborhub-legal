import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

/// Internal enum for tracking Stitch payment display states.
private enum StitchPaymentDisplayState {
    case waiting
    case processing
    case success
    case cancelled
    case failed

    var title: String {
        switch self {
        case .waiting: return "Waiting For Confirmation"
        case .processing: return "Processing Payment"
        case .success: return "Payment Complete"
        case .cancelled: return "Payment Cancelled"
        case .failed: return "Payment Failed"
        }
    }

    var message: String {
        switch self {
        case .waiting:
            return "Complete checkout in your browser. This screen updates automatically once Stitch confirms the payment."
        case .processing:
            return "Your payment callback was received. We are verifying the final status."
        case .success:
            return "Your payment was successful and has been recorded."
        case .cancelled:
            return "The checkout was cancelled before completion."
        case .failed:
            return "The payment did not complete. You can try again."
        }
    }

    var iconName: String {
        switch self {
        case .waiting, .processing: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .waiting, .processing: return .orange
        case .success: return .green
        case .cancelled: return .secondary
        case .failed: return .red
        }
    }
}

/// Modal sheet that displays payment status and updates automatically via Firestore listener.
///
/// Shows real-time payment status using Firestore real-time listeners, updates from
/// Stitch webhook callbacks, and manual refresh capability.
struct StitchPaymentResultSheet: View {
    let reference: String
    let onCompletion: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var state: StitchPaymentDisplayState = .waiting
    @State private var detailMessage: String?
    @State private var didNotifySuccess: Bool = false
    @State private var isRefreshing: Bool = false

    #if canImport(FirebaseFirestore)
    @State private var listener: ListenerRegistration?
    #endif

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Image(systemName: state.iconName)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundColor(state.iconColor)

                Text(state.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(detailMessage ?? state.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Text("Reference: \(reference)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 4)

                if isRefreshing {
                    ProgressView()
                        .padding(.top, 2)
                }

                Spacer(minLength: 8)

                Button(action: refreshStatus) {
                    Text("Refresh Status")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)

                Button(action: {
                    dismiss()
                }) {
                    Text(state == .success ? "Done" : "Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .navigationTitle("Payment Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                startListening()
                refreshStatus()
            }
            .onDisappear {
                stopListening()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stitchPaymentCallbackReceived)) { notification in
                guard let payload = notification.object as? StitchPaymentCallbackPayload else {
                    return
                }
                guard payload.reference == reference else {
                    return
                }
                handleCallback(payload)
            }
        }
    }

    /// Handles the Stitch payment callback from the redirect.
    private func handleCallback(_ payload: StitchPaymentCallbackPayload) {
        if payload.trusted == "0" {
            state = .processing
            detailMessage = "Return link could not be fully verified. Waiting for backend confirmation..."
            refreshStatus()
            return
        }

        switch payload.status {
        case "success":
            state = .processing
            detailMessage = "Payment callback received. Verifying final payment state..."
            refreshStatus()
        case "cancel", "cancelled":
            state = .cancelled
            detailMessage = nil
        case "failed":
            state = .failed
            detailMessage = payload.error
        default:
            state = .processing
            detailMessage = payload.error
            refreshStatus()
        }
    }

    /// Applies the Firestore payment status to the display state.
    private func applyStatus(_ rawStatus: String?) {
        let normalized = (rawStatus ?? "pending").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if ["success", "succeeded", "paid", "completed"].contains(normalized) {
            state = .success
            detailMessage = nil
            notifySuccessIfNeeded()
            return
        }

        if ["cancel", "cancelled"].contains(normalized) {
            state = .cancelled
            detailMessage = nil
            return
        }

        if ["failed", "failure", "error", "declined"].contains(normalized) {
            state = .failed
            detailMessage = nil
            return
        }

        if ["submitted", "processing", "received", "checkout_created", "checkout_created_dummy", "pending", "pending_auto"].contains(normalized) {
            state = .processing
            return
        }

        state = .waiting
    }

    /// Notifies completion handler one time after successful payment.
    private func notifySuccessIfNeeded() {
        guard !didNotifySuccess else {
            return
        }
        didNotifySuccess = true
        onCompletion(true)
    }

    /// Manually refreshes payment status from Firestore.
    private func refreshStatus() {
        #if canImport(FirebaseFirestore)
        isRefreshing = true
        Task {
            defer {
                Task { @MainActor in
                    isRefreshing = false
                }
            }

            do {
                let snapshot = try await Firestore.firestore()
                    .collection("stitchPayments")
                    .document(reference)
                    .getDocument()

                await MainActor.run {
                    applyStatus(snapshot.data()?["status"] as? String)
                }
            } catch {
                await MainActor.run {
                    detailMessage = "Unable to load latest status. Please try refresh again."
                }
            }
        }
        #else
        detailMessage = "Live status updates are unavailable in this build."
        #endif
    }

    /// Starts real-time listener on the payment document.
    private func startListening() {
        #if canImport(FirebaseFirestore)
        listener = Firestore.firestore().collection("stitchPayments").document(reference)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else {
                    return
                }

                let status = data["status"] as? String
                DispatchQueue.main.async {
                    applyStatus(status)
                }
            }
        #endif
    }

    /// Stops real-time listener.
    private func stopListening() {
        #if canImport(FirebaseFirestore)
        listener?.remove()
        listener = nil
        #endif
    }
}

#Preview {
    StitchPaymentResultSheet(
        reference: "test_ref_123",
        onCompletion: { success in
            print("Payment completed: \(success)")
        }
    )
}
