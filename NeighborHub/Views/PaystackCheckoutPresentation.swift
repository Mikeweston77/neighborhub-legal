import Foundation
import SafariServices

#if canImport(UIKit)
import UIKit
#endif

#if canImport(PaystackCore)
import PaystackCore
#endif

#if canImport(PaystackUI)
import PaystackUI
#endif

enum PaystackCheckoutPresentation {
    static func presentNativeCheckout(
        accessCode: String,
        onSuccess: @escaping (String) -> Void,
        onCancelled: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) -> Bool {
        // Paystack's native charge UI uses dynamic colors that become
        // invisible in dark mode. We always use SFSafariViewController
        // instead, which properly supports both light and dark appearance.
        let checkoutURLString = "https://checkout.paystack.com/\(accessCode)"
        guard let checkoutURL = URL(string: checkoutURLString) else {
            onError("Invalid Paystack checkout URL.")
            return false
        }
        presentCheckout(checkoutURL, onResetReference: { }, onError: onError)
        return true
    }

    static func isMatchingCallback(_ payload: PaystackPaymentCallbackPayload, reference: String?) -> Bool {
        guard let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty else {
            return false
        }

        return payload.reference == reference
    }

    static func presentCheckout(
        _ checkoutURL: URL,
        onResetReference: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard checkoutURL.scheme?.lowercased() == "https" else {
            onResetReference()
            onError("Invalid checkout URL returned by Paystack.")
            return
        }

        #if canImport(UIKit)
        let safariVC = SFSafariViewController(url: checkoutURL)
        safariVC.dismissButtonStyle = .close
        safariVC.preferredControlTintColor = .systemBlue

        if let presenter = topMostViewController() {
            presenter.present(safariVC, animated: true)
            return
        }
        #endif

        guard UIApplication.shared.canOpenURL(checkoutURL) else {
            onResetReference()
            onError("Unable to open Paystack checkout on this device.")
            return
        }

        UIApplication.shared.open(checkoutURL, options: [:]) { didOpen in
            if !didOpen {
                onResetReference()
                onError("Unable to open Paystack checkout on this device.")
            }
        }
    }

    private static func makePaystack() -> Paystack? {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "PAYSTACK_PUBLIC_KEY") as? String
        let trimmedKey = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedKey.isEmpty else {
            return nil
        }

        return try? PaystackBuilder.newInstance
            .setKey(trimmedKey)
            .build()
    }

    #if canImport(UIKit)
    private static func topMostViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController
        else {
            return nil
        }

        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
    #endif
}