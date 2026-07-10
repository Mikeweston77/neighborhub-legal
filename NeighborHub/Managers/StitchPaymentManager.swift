import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// Manager for initiating Stitch payment operations.
///
/// Handles communication with Firebase Cloud Functions to create payment links
/// and retrieve checkout URLs for Stitch payment processing.
final class StitchPaymentManager {
    static let shared = StitchPaymentManager()

    private init() {}

    /// Initiates a payment by calling the backend `createStitchPaymentLink` function.
    ///
    /// - Parameter request: The payment request containing type, amount, and related metadata.
    /// - Returns: A response containing the reference and checkout URL.
    /// - Throws: `StitchPaymentError` if payment initiation fails.
    func initiatePayment(request: StitchPaymentRequest) async throws -> StitchPaymentResponse {
        guard request.amount > 0 else {
            throw StitchPaymentError.invalidAmount
        }

        #if canImport(FirebaseFunctions)
        var payload: [String: Any] = [
            "paymentType": request.paymentType.backendValue,
            "amount": request.amount,
            "currency": request.currency,
            "title": request.paymentType == .subscription ? "NeighborHub Subscription" : "NeighborHub Listing Purchase",
            "description": request.description,
            "platform": "IOS"
        ]

        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            throw StitchPaymentError.unauthenticated
        }
        payload["memberUID"] = user.uid
        payload["payerEmail"] = user.email ?? UserDefaults.standard.string(forKey: "userEmail") ?? ""
        payload["payerName"] = user.displayName ?? UserDefaults.standard.string(forKey: "userName") ?? "NeighborHub Member"
        #endif

        if let planType = request.planType {
            payload["subscriptionType"] = planType.backendValue
        }

        if let billingDay = request.billingDay {
            payload["billingDay"] = billingDay
        }

        if let autoPayEnabled = request.autoPayEnabled {
            payload["autoPayEnabled"] = autoPayEnabled
        } else if let checkoutMode = request.checkoutMode {
            payload["autoPayEnabled"] = checkoutMode.autoPayEnabled
        }

        if let checkoutMode = request.checkoutMode {
            payload["checkoutMode"] = checkoutMode.backendValue
            payload["billingInterval"] = checkoutMode.billingIntervalValue
        }

        if let preferredPaymentMethod = request.preferredPaymentMethod {
            payload["paymentMethod"] = preferredPaymentMethod.backendValue
            payload["preferredPaymentMethod"] = preferredPaymentMethod.backendValue
        }

        if let billingStartDate = request.billingStartDate {
            let formatter = ISO8601DateFormatter()
            payload["billingStartDate"] = formatter.string(from: billingStartDate)
        }

        if let listingId = request.listingId, !listingId.isEmpty {
            payload["listingId"] = listingId
        }

        if let subscriptionDocId = request.subscriptionDocId,
           !subscriptionDocId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["subscriptionDocId"] = subscriptionDocId
        }

        do {
            let result = try await Functions.functions().httpsCallable("createStitchPaymentLink").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw StitchPaymentError.invalidResponse("Missing response data")
            }

            let reference = (data["reference"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let redirectUrlString = (
                (data["checkoutUrl"] as? String)
                ?? (data["link"] as? String)
                ?? (data["url"] as? String)
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            guard !reference.isEmpty,
                  let redirectUrl = URL(string: redirectUrlString)
            else {
                throw StitchPaymentError.invalidResponse("Missing reference or checkout URL")
            }

            let expiresAtString = data["expiresAt"] as? String
            let expiresAt: Date?
            if let expiresAtString = expiresAtString {
                let formatter = ISO8601DateFormatter()
                expiresAt = formatter.date(from: expiresAtString)
            } else {
                expiresAt = nil
            }

            return StitchPaymentResponse(
                reference: reference,
                redirectUrl: redirectUrl,
                expiresAt: expiresAt
            )
        } catch {
            // Firebase Functions errors are always bridgeable to NSError.
            // The actual backend message is stored under NSLocalizedDescriptionKey.
            // Prefer the userInfo key directly so we get the HttpsError message text
            // rather than the generic localized description which may just say "network".
            let nsErr = error as NSError
            let backendMessage: String
            if let msg = nsErr.userInfo[NSLocalizedDescriptionKey] as? String, !msg.isEmpty {
                backendMessage = msg
            } else if let msg = nsErr.userInfo["NSDebugDescription"] as? String, !msg.isEmpty {
                backendMessage = msg
            } else {
                let fallback = nsErr.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                backendMessage = fallback.isEmpty ? "Unable to start checkout. Please try again." : fallback
            }
            throw StitchPaymentError.network(backendMessage)
        }
        #else
        throw StitchPaymentError.firebaseFunctionsUnavailable
        #endif
    }
}

