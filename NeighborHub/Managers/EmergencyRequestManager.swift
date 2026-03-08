import Foundation
import SwiftUI
import UIKit
import Photos
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

/// EmergencyRequestManager
/// Central place for building and sending emergency requests (Fire / Emergency / Medical).
/// Purpose:
/// - Build `LocalEvent` objects for persistence (same shape used by HomeView/EventsView)
/// - Build payloads suitable for a help server
/// - Build WhatsApp app/web URLs for fallback behavior
///
/// Contract (inputs/outputs):
/// - Inputs: emergency type, optional message, optional fire location, optional fire date, contact info, optional server config
/// - Output: a constructed `LocalEvent` and optionally sends the payload via server or returns a URL to open
/// - Error modes: invalid URL construction, server network errors are reported via completion

    final class EmergencyRequestManager: ObservableObject {
        enum EmergencyType: String, Codable {
        case fire = "Fire"
        case emergency = "Emergency"
        case medical = "Medical"
    }

    struct RecipientInfo {
        let name: String?
        public let phone: String?
        public let relationship: String?
        public init(name: String? = nil, phone: String? = nil, relationship: String? = nil) {
            self.name = name
            self.phone = phone
            self.relationship = relationship
        }
    }

    struct ServerConfig {
        let url: URL
        public let apiKey: String?
        public init(url: URL, apiKey: String? = nil) {
            self.url = url
            self.apiKey = apiKey
        }
    }

    init() {}

    // Build a LocalEvent for persistence. LocalEvent is expected to exist in the project models.
    func buildLocalEvent(type: EmergencyType,
                                titlePrefix: String = "Request:",
                                message: String?,
                                location: String?,
                                date: Date,
                                creatorName: String?,
                                creatorSurname: String?,
                                contact: RecipientInfo?,
                                metadata: [String: String]? = nil,
                                imageData: Data? = nil) -> LocalEvent {
        // Note: LocalEvent currently does not have a dedicated metadata field; include imageData and leave metadata to be embedded in messages if needed.
        return LocalEvent(
            id: UUID(),
            title: "\(titlePrefix) \(type.rawValue)",
            description: message?.isEmpty == true ? nil : message,
            location: location?.isEmpty == true ? nil : location,
            date: date,
            eventType: .request,
            comments: [],
            imageData: imageData,
            fileURL: nil,
            creatorName: creatorName?.isEmpty == true ? nil : creatorName,
            creatorSurname: creatorSurname?.isEmpty == true ? nil : creatorSurname,
            contactName: contact?.name,
            contactCell: contact?.phone
            ,metadata: metadata
        )
    }

    // Build a full plain-text message body which can be used for WhatsApp or server payload
    func buildMessageBody(type: EmergencyType,
                                 name: String,
                                 address: String?,
                                 cell: String?,
                                 emergencyContact: RecipientInfo?,
                                 description: String?,
                                 metadata: [String: String]? = nil,
                                 reportedDate: Date? = nil,
                                 photoAttached: Bool = false) -> String {
        let header: String
        switch type {
        case .fire:
            header = "*🚨🔥 FIRE ALERT! 🔥🚨*"
        case .emergency:
            header = "*🚨⚠️ EMERGENCY ALERT! ⚠️🚨*"
        case .medical:
            header = "*🚨🏥 MEDICAL EMERGENCY! 🩺🚨*"
        }
        var body = "\(header)\n"

        // Fire: prioritize fire-specific fields supplied via metadata (location/address, building type, visible flames, device location flag, photo)
        if type == .fire {
            if let addr = address, !addr.isEmpty {
                body += "\nLocation: \(addr)"
            }
            if let rd = reportedDate {
                let df = DateFormatter()
                df.dateStyle = .medium
                df.timeStyle = .short
                body += "\nDate Reported: \(df.string(from: rd))"
            }
            if let meta = metadata {
                if let b = meta["buildingType"], !b.isEmpty {
                    if b == "Other", let other = meta["buildingOtherDescription"], !other.isEmpty {
                        body += "\nType: \(other)"
                    } else {
                        body += "\nType: \(b)"
                    }
                }
                // Location source line removed per specification
                if let v = meta["visibleFlamesOrSmoke"] {
                    if v.lowercased() == "yes" { body += "\nVisible flames or heavy smoke: Yes" } else { body += "\nVisible flames or heavy smoke: No" }
                }
            }
            if let desc = description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body += "\n\nNotes:\n\(desc)"
            }
            if photoAttached {
                body += "\n\nPhoto: Attached (see app for image)"
            }
            // Include reporter profile for responders; do not include stored emergency contact
            if let c = cell, !c.isEmpty {
                body += "\n\nReporter: \(name) — \(c)"
            } else {
                body += "\n\nReporter: \(name)"
            }
            return body
        }

        // For emergency/medical: continue to use reporter's name, address, cell and emergency contact
        body += "\nName: \(name)"
        if let address = address, !address.isEmpty { body += "\nAddress: \(address)" }
        if let cell = cell, !cell.isEmpty { body += "\nCell: \(cell)" }
        if let rd = reportedDate {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            body += "\nDate Reported: \(df.string(from: rd))"
        }
    // Do not include stored emergency contact; reporter info is already included above
        if let desc = description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += "\n\nDescription:\n\(desc)"
        }
        if photoAttached {
            body += "\n\nPhoto: Attached (see app for image)"
        }
        return body
    }

    // Build a WhatsApp app URL (if app present) and web fallback URL
    // Updated to use a specific WhatsApp number for emergency messages
    func buildWhatsAppURLs(body: String, toPhone: String? = "0793867472") -> (app: URL?, web: URL?) {
        guard let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return (nil, nil)
        }
        if let to = toPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !to.isEmpty {
            let appString = "whatsapp://send?phone=\(to)&text=\(encoded)"
            let webString = "https://wa.me/\(to)?text=\(encoded)"
            return (URL(string: appString), URL(string: webString))
        }
        let appString = "whatsapp://send?text=\(encoded)"
        let webString = "https://api.whatsapp.com/send?text=\(encoded)"
        return (URL(string: appString), URL(string: webString))
    }

    // Save emergency photo to photo library with completion callback
    private func saveEmergencyPhotoToLibrary(_ imageData: Data, completion: @escaping (Bool) -> Void) {
        guard let image = UIImage(data: imageData) else {
            completion(false)
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            DispatchQueue.main.async {
                completion(true)
            }
        }
    }
    
    // Attempt to open WhatsApp (app or web) from a caller context. This is provided for convenience.
    // The caller should run this on the main thread. Optionally saves photo evidence to library.
    func openWhatsAppFallback(body: String, toPhone: String? = nil, imageData: Data? = nil) {
        let targetNumber: String? = {
            if let toPhone, !toPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return toPhone
            }
            return "+27739540267"
        }()
        let urls = buildWhatsAppURLs(body: body, toPhone: targetNumber)

        // If there's image data, save it to photo library first
        if let imgData = imageData {
            saveEmergencyPhotoToLibrary(imgData) { success in
                if success {
                    print("Emergency photo saved to photo library")
                } else {
                    print("Failed to save emergency photo to library")
                }
            }
        }

        if let app = urls.app, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
            return
        }
        if let web = urls.web {
            UIApplication.shared.open(web)
        }
    }

    // Send payload to configured help server. Completion returns success boolean and optional error.
    func sendToServer(config: ServerConfig, payload: [String: Any], imageData: Data? = nil, completion: @escaping (Bool, Error?) -> Void) {
        var req = URLRequest(url: config.url)
        req.httpMethod = "POST"
        if let key = config.apiKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        // If imageData is provided, construct a multipart/form-data body
        if let img = imageData {
            let boundary = "----NeighborHubBoundary\(UUID().uuidString)"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            // Add JSON part
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"payload\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
                body.append(jsonData)
                body.append("\r\n".data(using: .utf8)!)
            }
            // Add image part
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"evidence.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(img)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            req.httpBody = body
        } else {
            // Default JSON body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            } catch {
                completion(false, error)
                return
            }
        }

        let task = URLSession.shared.dataTask(with: req) { data, resp, error in
            if let e = error { completion(false, e); return }
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                completion(true, nil)
            } else {
                completion(false, nil)
            }
        }
        task.resume()
    }

    // Convert common phone formats to E.164. Defaults local 10-digit numbers to South Africa (+27).
    private func normalizedE164Phone(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let hasPlus = raw.hasPrefix("+")
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        if hasPlus {
            return "+\(digits)"
        }
        if digits.hasPrefix("00") {
            return "+\(digits.dropFirst(2))"
        }
        if digits.hasPrefix("0") && digits.count == 10 {
            return "+27\(digits.dropFirst())"
        }
        if digits.hasPrefix("27") {
            return "+\(digits)"
        }
        return "+\(digits)"
    }

    private func resolvedTwilioRecipient(e164FromWaNumber waNumber: String?, emergencyContact: RecipientInfo?, fallbackCell: String?) -> RecipientInfo? {
        if let waE164 = normalizedE164Phone(waNumber) {
            return RecipientInfo(name: emergencyContact?.name, phone: waE164, relationship: emergencyContact?.relationship)
        }
        if let contactE164 = normalizedE164Phone(emergencyContact?.phone) {
            return RecipientInfo(name: emergencyContact?.name, phone: contactE164, relationship: emergencyContact?.relationship)
        }
        if let cellE164 = normalizedE164Phone(fallbackCell) {
            return RecipientInfo(name: emergencyContact?.name, phone: cellE164, relationship: emergencyContact?.relationship)
        }
        return nil
    }

    // Convenience async wrapper: attempts server send and falls back to WhatsApp if server send fails or no server provided.
    // Completion runs on main thread.
    func sendRequest(type: EmergencyType,
                     name: String,
                     address: String?,
                     cell: String?,
                     emergencyContact: RecipientInfo?,
                     description: String?,
                     metadata: [String: String]?,
                     reportedDate: Date?,
                     photoAttached: Bool,
                     imageData: Data? = nil,
                     serverURL: URL?,
                     serverAPIKey: String?,
                     waNumber: String?,
                     preferTwilio: Bool = true) {

        #if canImport(FirebaseFunctions)
        if preferTwilio,
           let recipient = resolvedTwilioRecipient(e164FromWaNumber: waNumber, emergencyContact: emergencyContact, fallbackCell: cell) {
            sendEmergencyViaTwilio(
                type: type,
                name: name,
                address: address,
                cell: cell,
                emergencyContact: recipient,
                description: description,
                metadata: metadata,
                reportedDate: reportedDate,
                imageData: imageData
            ) { success, errorMessage in
                if !success {
                    print("⚠️ Twilio auto-send failed, using existing fallback flow: \(errorMessage ?? "Unknown error")")
                    self.sendRequest(
                        type: type,
                        name: name,
                        address: address,
                        cell: cell,
                        emergencyContact: emergencyContact,
                        description: description,
                        metadata: metadata,
                        reportedDate: reportedDate,
                        photoAttached: photoAttached,
                        imageData: imageData,
                        serverURL: serverURL,
                        serverAPIKey: serverAPIKey,
                        waNumber: waNumber,
                        preferTwilio: false
                    )
                }
            }
            return
        }
        #endif

        let body = buildMessageBody(type: type, name: name, address: address, cell: cell, emergencyContact: emergencyContact, description: description, metadata: metadata, reportedDate: reportedDate, photoAttached: photoAttached)

        if let url = serverURL {
            let cfg = ServerConfig(url: url, apiKey: serverAPIKey)
            var payload: [String: Any] = [
                "type": type.rawValue,
                "reporter": ["name": name, "cell": cell ?? ""],
                "address": address ?? "",
                "description": description ?? "",
                "fullMessage": body,
                "metadata": metadata ?? [:],
                "photoAttached": photoAttached
            ]
            // If image data is provided, prefer multipart upload (handled in sendToServer)
            if let r = waNumber { payload["toPhone"] = r }
            if let rd = reportedDate {
                let iso = ISO8601DateFormatter.string(from: rd, timeZone: .current, formatOptions: [.withInternetDateTime])
                payload["reportedDate"] = iso
            }
            sendToServer(config: cfg, payload: payload, imageData: imageData) { success, _ in
                if !success {
                    DispatchQueue.main.async {
                        self.openWhatsAppFallback(body: body, toPhone: waNumber, imageData: imageData)
                    }
                }
            }
            return
        }

        // No server configured — open WhatsApp directly
        DispatchQueue.main.async {
            self.openWhatsAppFallback(body: body, toPhone: waNumber, imageData: imageData)
        }
    }

    // Variant that provides a completion callback indicating whether the send succeeded (server accepted) or not.
    // If no server is configured, this will open WhatsApp and call completion(true).
    func sendRequestWithCompletion(type: EmergencyType,
                                   name: String,
                                   address: String?,
                                   cell: String?,
                                   emergencyContact: RecipientInfo?,
                                   description: String?,
                                   metadata: [String: String]?,
                                   reportedDate: Date?,
                                   photoAttached: Bool,
                                   imageData: Data? = nil,
                                   serverURL: URL?,
                                   serverAPIKey: String?,
                                   waNumber: String?,
                                   preferTwilio: Bool = true,
                                   completion: @escaping (Bool) -> Void) {

        #if canImport(FirebaseFunctions)
        if preferTwilio,
           let recipient = resolvedTwilioRecipient(e164FromWaNumber: waNumber, emergencyContact: emergencyContact, fallbackCell: cell) {
            sendEmergencyViaTwilio(
                type: type,
                name: name,
                address: address,
                cell: cell,
                emergencyContact: recipient,
                description: description,
                metadata: metadata,
                reportedDate: reportedDate,
                imageData: imageData
            ) { success, errorMessage in
                if !success {
                    print("⚠️ Twilio auto-send failed, using existing fallback flow: \(errorMessage ?? "Unknown error")")
                    self.sendRequestWithCompletion(
                        type: type,
                        name: name,
                        address: address,
                        cell: cell,
                        emergencyContact: emergencyContact,
                        description: description,
                        metadata: metadata,
                        reportedDate: reportedDate,
                        photoAttached: photoAttached,
                        imageData: imageData,
                        serverURL: serverURL,
                        serverAPIKey: serverAPIKey,
                        waNumber: waNumber,
                        preferTwilio: false,
                        completion: completion
                    )
                    return
                }
                completion(success)
            }
            return
        }
        #endif

        let body = buildMessageBody(type: type, name: name, address: address, cell: cell, emergencyContact: emergencyContact, description: description, metadata: metadata, reportedDate: reportedDate, photoAttached: photoAttached)

        if let url = serverURL {
            let cfg = ServerConfig(url: url, apiKey: serverAPIKey)
            var payload: [String: Any] = [
                "type": type.rawValue,
                "reporter": ["name": name, "cell": cell ?? ""],
                "address": address ?? "",
                "description": description ?? "",
                "fullMessage": body,
                "metadata": metadata ?? [:],
                "photoAttached": photoAttached
            ]
            if let r = waNumber { payload["toPhone"] = r }
            if let rd = reportedDate {
                let iso = ISO8601DateFormatter.string(from: rd, timeZone: .current, formatOptions: [.withInternetDateTime])
                payload["reportedDate"] = iso
            }
            sendToServer(config: cfg, payload: payload, imageData: imageData) { success, _ in
                if !success {
                    DispatchQueue.main.async {
                        self.openWhatsAppFallback(body: body, toPhone: waNumber, imageData: imageData)
                    }
                    completion(false)
                } else {
                    completion(true)
                }
            }
            return
        }

        // No server configured — open WhatsApp and consider it success for caller purposes
        DispatchQueue.main.async {
            self.openWhatsAppFallback(body: body, toPhone: waNumber, imageData: imageData)
            completion(true)
        }
    }
    
    // MARK: - Twilio WhatsApp Integration
    
    /// Send emergency alert via Twilio WhatsApp Cloud Function (automated, no user action required)
    /// This will send the WhatsApp message automatically without opening any UI
    /// - Parameters:
    ///   - type: Emergency type (fire, medical, emergency)
    ///   - name: Reporter's name
    ///   - address: Location address
    ///   - cell: Reporter's phone number
    ///   - emergencyContact: Emergency contact information
    ///   - description: Additional description or notes
    ///   - metadata: Additional metadata (building type, flames visible, etc.)
    ///   - reportedDate: Date/time of emergency
    ///   - imageData: Optional photo evidence (saved to photo library)
    ///   - completion: Callback with success status and optional error message
    func sendEmergencyViaTwilio(type: EmergencyType,
                               name: String,
                               address: String?,
                               cell: String?,
                               emergencyContact: RecipientInfo?,
                               description: String?,
                               metadata: [String: String]?,
                               reportedDate: Date?,
                               imageData: Data? = nil,
                               completion: @escaping (Bool, String?) -> Void) {
        
        #if canImport(FirebaseFunctions)
        // Save photo evidence to library if provided
        if let imgData = imageData {
            saveEmergencyPhotoToLibrary(imgData) { success in
                if success {
                    print("✅ Emergency photo saved to photo library")
                } else {
                    print("⚠️ Failed to save emergency photo to library")
                }
            }
        }
        
        // Validate emergency contact phone
        guard let contactPhone = emergencyContact?.phone, !contactPhone.isEmpty else {
            DispatchQueue.main.async {
                completion(false, "Emergency contact phone number is required")
            }
            return
        }
        
        // Prepare Cloud Function payload
        var payload: [String: Any] = [
            "emergencyType": type.rawValue.lowercased(),
            "userName": name,
            "timestamp": reportedDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
            "emergencyContactPhone": contactPhone
        ]
        
        // Optional fields
        if let addr = address, !addr.isEmpty {
            payload["userAddress"] = addr
        }
        if let phone = cell, !phone.isEmpty {
            payload["userPhone"] = phone
        }
        if let contactName = emergencyContact?.name {
            payload["emergencyContactName"] = contactName
        }
        if let desc = description, !desc.isEmpty {
            payload["description"] = desc
        }
        if let meta = metadata {
            payload["metadata"] = meta
        }
        
        // Call Firebase Cloud Function
        let functions = Functions.functions()
        functions.httpsCallable("sendEmergencyWhatsApp").call(payload) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    let nsError = error as NSError
                    let errorMessage: String
                    
                    // Parse Firebase Functions error
                    if nsError.domain == FunctionsErrorDomain {
                        switch FunctionsErrorCode(rawValue: nsError.code) {
                        case .unauthenticated:
                            errorMessage = "Authentication required. Please log in."
                        case .permissionDenied:
                            errorMessage = "Permission denied. Cannot send to this number."
                        case .invalidArgument:
                            errorMessage = nsError.localizedDescription
                        case .resourceExhausted:
                            errorMessage = nsError.localizedDescription // Rate limit message
                        case .notFound:
                            errorMessage = "Emergency service not available"
                        case .failedPrecondition:
                            errorMessage = "Twilio WhatsApp not configured"
                        default:
                            errorMessage = "Failed to send emergency alert: \(nsError.localizedDescription)"
                        }
                    } else {
                        errorMessage = "Network error: \(error.localizedDescription)"
                    }
                    
                    print("❌ Twilio emergency send failed: \(errorMessage)")
                    completion(false, errorMessage)
                    return
                }
                
                // Success - parse response
                if let data = result?.data as? [String: Any],
                   let success = data["success"] as? Bool,
                   success,
                   let emergencyId = data["emergencyId"] as? String {
                    print("✅ Emergency alert sent via Twilio. Emergency ID: \(emergencyId)")
                    completion(true, nil)
                } else {
                    completion(false, "Unexpected response from emergency service")
                }
            }
        }
        #else
        // Firebase Functions not available - fall back to WhatsApp URL scheme
        DispatchQueue.main.async {
            let body = self.buildMessageBody(
                type: type,
                name: name,
                address: address,
                cell: cell,
                emergencyContact: emergencyContact,
                description: description,
                metadata: metadata,
                reportedDate: reportedDate,
                photoAttached: imageData != nil
            )
            self.openWhatsAppFallback(body: body, toPhone: emergencyContact?.phone, imageData: imageData)
            completion(true, "WhatsApp opened - please send message manually")
        }
        #endif
    }
    
    // MARK: - Test Twilio Sandbox
    
    /// Test Twilio WhatsApp Sandbox (for development/testing)
    /// Use this to verify Twilio is configured correctly before going to production
    /// - Parameters:
    ///   - toPhone: Phone number in E.164 format (e.g., +27793867472)
    ///   - message: Test message to send
    ///   - completion: Callback with success status
    func testTwilioWhatsApp(toPhone: String, message: String, completion: @escaping (Bool, String?) -> Void) {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions()
        functions.httpsCallable("testTwilioWhatsApp").call([
            "toPhone": toPhone,
            "message": message
        ]) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    let errorMessage = (error as NSError).localizedDescription
                    print("❌ Twilio test failed: \(errorMessage)")
                    completion(false, errorMessage)
                    return
                }
                
                if let data = result?.data as? [String: Any],
                   let success = data["success"] as? Bool,
                   success {
                    print("✅ Test WhatsApp message sent successfully")
                    completion(true, "Test message sent successfully")
                } else {
                    completion(false, "Unexpected response")
                }
            }
        }
        #else
        DispatchQueue.main.async {
            completion(false, "Firebase Functions not available")
        }
        #endif
    }
}
