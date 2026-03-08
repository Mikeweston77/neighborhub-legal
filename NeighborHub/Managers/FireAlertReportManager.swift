import Foundation
import SwiftUI
import CoreLocation

// MARK: - FireAlertReport: Encapsulates all fire alert fields
struct FireAlertReport: Identifiable, Codable {
    var id: UUID = UUID()
    var location: String = ""
    var useDeviceLocation: Bool = true
    var resolvedAddress: String = ""
    var coordinates: CLLocationCoordinate2D? = nil
    var buildingType: String = "House"
    var buildingOtherDescription: String = ""
    var visibleFlamesOrSmoke: Bool = true
    var photoData: Data? = nil
    var reportedAt: Date = Date()
    var contactName: String = ""
    var contactPhone: String = ""
    var useProfileContact: Bool = true
    var notes: String = ""
    var reporterName: String = ""
    var reporterSurname: String = ""
    var reporterCell: String = ""
}

// Custom Codable implementation to handle CLLocationCoordinate2D
extension FireAlertReport {
    enum CodingKeys: String, CodingKey {
        case id
        case location
        case useDeviceLocation
        case resolvedAddress
        case latitude
        case longitude
        case buildingType
        case buildingOtherDescription
        case visibleFlamesOrSmoke
        case photoData
        case reportedAt
        case contactName
        case contactPhone
        case useProfileContact
        case notes
        case reporterName
        case reporterSurname
        case reporterCell
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.id = id
        self.location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        self.useDeviceLocation = try c.decodeIfPresent(Bool.self, forKey: .useDeviceLocation) ?? true
        self.resolvedAddress = try c.decodeIfPresent(String.self, forKey: .resolvedAddress) ?? ""
        if let lat = try c.decodeIfPresent(Double.self, forKey: .latitude), let lon = try c.decodeIfPresent(Double.self, forKey: .longitude) {
            self.coordinates = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            self.coordinates = nil
        }
        self.buildingType = try c.decodeIfPresent(String.self, forKey: .buildingType) ?? "House"
        self.buildingOtherDescription = try c.decodeIfPresent(String.self, forKey: .buildingOtherDescription) ?? ""
        self.visibleFlamesOrSmoke = try c.decodeIfPresent(Bool.self, forKey: .visibleFlamesOrSmoke) ?? true
        self.photoData = try c.decodeIfPresent(Data.self, forKey: .photoData)
        self.reportedAt = try c.decodeIfPresent(Date.self, forKey: .reportedAt) ?? Date()
        self.contactName = try c.decodeIfPresent(String.self, forKey: .contactName) ?? ""
        self.contactPhone = try c.decodeIfPresent(String.self, forKey: .contactPhone) ?? ""
        self.useProfileContact = try c.decodeIfPresent(Bool.self, forKey: .useProfileContact) ?? true
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.reporterName = try c.decodeIfPresent(String.self, forKey: .reporterName) ?? ""
        self.reporterSurname = try c.decodeIfPresent(String.self, forKey: .reporterSurname) ?? ""
        self.reporterCell = try c.decodeIfPresent(String.self, forKey: .reporterCell) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(location, forKey: .location)
        try c.encode(useDeviceLocation, forKey: .useDeviceLocation)
        try c.encode(resolvedAddress, forKey: .resolvedAddress)
        if let coords = coordinates {
            try c.encode(coords.latitude, forKey: .latitude)
            try c.encode(coords.longitude, forKey: .longitude)
        }
        try c.encode(buildingType, forKey: .buildingType)
        try c.encode(buildingOtherDescription, forKey: .buildingOtherDescription)
        try c.encode(visibleFlamesOrSmoke, forKey: .visibleFlamesOrSmoke)
        try c.encodeIfPresent(photoData, forKey: .photoData)
        try c.encode(reportedAt, forKey: .reportedAt)
        try c.encode(contactName, forKey: .contactName)
        try c.encode(contactPhone, forKey: .contactPhone)
        try c.encode(useProfileContact, forKey: .useProfileContact)
        try c.encode(notes, forKey: .notes)
        try c.encode(reporterName, forKey: .reporterName)
        try c.encode(reporterSurname, forKey: .reporterSurname)
        try c.encode(reporterCell, forKey: .reporterCell)
    }
}

// MARK: - FireAlertReportViewModel: Manages state, validation, and sending
class FireAlertReportViewModel: ObservableObject {
    @Published var report = FireAlertReport()
    @Published var validationError: String? = nil
    @Published var isSending: Bool = false
    @Published var sendSuccess: Bool? = nil

    // Validate required fields
    func validate() -> Bool {
        if report.useDeviceLocation && report.resolvedAddress.isEmpty && report.coordinates == nil {
            validationError = "Location could not be determined."
            return false
        }
        if !report.useProfileContact && (report.contactName.isEmpty || report.contactPhone.isEmpty) {
            validationError = "Please provide a contact name and phone."
            return false
        }
        validationError = nil
        return true
    }

    // Build metadata for persistence and sending
    var metadata: [String: String] {
        var meta: [String: String] = [
            "buildingType": report.buildingType,
            "usedDeviceLocation": report.useDeviceLocation ? "yes" : "no"
        ]
        if report.buildingType == "Other" && !report.buildingOtherDescription.isEmpty {
            meta["buildingOtherDescription"] = report.buildingOtherDescription
        }
        return meta
    }

    // Compose message body for WhatsApp/server
    func buildMessageBody() -> String {
        var body = "*🚨🔥 FIRE ALERT! 🔥🚨*\n"
        if report.useDeviceLocation {
            if !report.resolvedAddress.isEmpty {
                body += "\nLocation: \(report.resolvedAddress)"
            } else if let coords = report.coordinates {
                body += String(format: "\nLocation: Lat: %.5f, Lon: %.5f", coords.latitude, coords.longitude)
            }
        } else if !report.location.isEmpty {
            body += "\nLocation: \(report.location)"
        }
        if !report.buildingType.isEmpty {
            if report.buildingType == "Other" && !report.buildingOtherDescription.isEmpty {
                body += "\nBuilding: \(report.buildingOtherDescription)"
            } else {
                body += "\nBuilding: \(report.buildingType)"
            }
        }
        body += "\nDate Reported: \(DateFormatter.localizedString(from: report.reportedAt, dateStyle: .medium, timeStyle: .short))"
        if !report.notes.isEmpty {
            body += "\n\nNotes:\n\(report.notes)"
        }
        if report.photoData != nil {
            body += "\n\n📷 Photo Evidence Available"
            body += "\n(Image will be attached to server report or saved to photos if using WhatsApp)"
        }
        // Contact info
        if report.useProfileContact {
            body += "\n\nReporter: \(report.reporterName) \(report.reporterSurname) — \(report.reporterCell)"
        } else {
            body += "\n\nContact for responders: \(report.contactName) — \(report.contactPhone)"
        }
        return body
    }

    // Send logic (stub, to be integrated with EmergencyRequestManager)
    func send(serverURL: URL?, serverAPIKey: String?, waNumber: String?, manager: EmergencyRequestManager) {
        guard validate() else { return }
        isSending = true
        sendSuccess = nil
        let contact = report.useProfileContact ? nil : EmergencyRequestManager.RecipientInfo(name: report.contactName, phone: report.contactPhone, relationship: nil)
        manager.sendRequestWithCompletion(
            type: .fire,
            name: "\(report.reporterName) \(report.reporterSurname)",
            address: report.useDeviceLocation ? (report.resolvedAddress.isEmpty ? nil : report.resolvedAddress) : (report.location.isEmpty ? nil : report.location),
            cell: report.reporterCell.isEmpty ? nil : report.reporterCell,
            emergencyContact: contact,
            description: report.notes.isEmpty ? nil : report.notes,
            metadata: metadata,
            reportedDate: report.reportedAt,
            photoAttached: report.photoData != nil,
            imageData: report.photoData,
            serverURL: serverURL,
            serverAPIKey: serverAPIKey,
            waNumber: waNumber
        ) { [weak self] success in
            DispatchQueue.main.async {
                self?.isSending = false
                self?.sendSuccess = success
            }
        }
    }
}
