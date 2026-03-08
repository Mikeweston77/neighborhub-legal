//
//  AnalyticsService.swift
//  NeighborHub
//
//  Centralized analytics tracking service for user engagement and feature usage
//

import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Centralized service for tracking app analytics and user engagement
final class AnalyticsService {
    static let shared = AnalyticsService()
    
    private init() {}
    
    // MARK: - Screen View Events
    
    func trackScreenView(_ screenName: String, screenClass: String? = nil) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName,
            AnalyticsParameterScreenClass: screenClass ?? screenName
        ])
        #endif
        print("📊 Analytics: Screen view - \(screenName)")
    }
    
    // MARK: - Feature Usage Events
    
    func trackFeatureUsed(_ featureName: String, parameters: [String: Any]? = nil) {
        #if canImport(FirebaseAnalytics)
        var params: [String: Any] = ["feature_name": featureName]
        if let additionalParams = parameters {
            params.merge(additionalParams) { _, new in new }
        }
        Analytics.logEvent("feature_used", parameters: params)
        #endif
        print("📊 Analytics: Feature used - \(featureName)")
    }
    
    // MARK: - User Actions
    
    func trackIncidentReport(category: String, severity: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("report_incident", parameters: [
            "category": category,
            "severity": severity
        ])
        #endif
        print("📊 Analytics: Incident reported - \(category)")
    }
    
    func trackEventCreated(category: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("create_event", parameters: [
            "event_category": category
        ])
        #endif
        print("📊 Analytics: Event created - \(category)")
    }
    
    func trackEventRSVP(eventId: String, status: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("event_rsvp", parameters: [
            "event_id": eventId,
            "rsvp_status": status
        ])
        #endif
        print("📊 Analytics: RSVP - \(status)")
    }
    
    func trackMarketplaceListing(category: String, listingType: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("create_marketplace_listing", parameters: [
            "listing_category": category,
            "listing_type": listingType
        ])
        #endif
        print("📊 Analytics: Marketplace listing - \(category)")
    }
    
    func trackChatMessage(messageType: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("send_chat_message", parameters: [
            "message_type": messageType
        ])
        #endif
        print("📊 Analytics: Chat message - \(messageType)")
    }
    
    func trackBusinessSearch(query: String, resultsCount: Int) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("business_search", parameters: [
            "search_query": query,
            "results_count": resultsCount
        ])
        #endif
        print("📊 Analytics: Business search - \(query) (\(resultsCount) results)")
    }
    
    func trackEmergencyContact(contactType: String, action: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("emergency_contact", parameters: [
            "contact_type": contactType,
            "action": action  // "call", "view", "add", "edit"
        ])
        #endif
        print("📊 Analytics: Emergency contact - \(contactType) - \(action)")
    }
    
    func trackPollVote(pollId: String, optionIndex: Int) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("vote_poll", parameters: [
            "poll_id": pollId,
            "option_index": optionIndex
        ])
        #endif
        print("📊 Analytics: Poll vote - option \(optionIndex)")
    }
    
    // MARK: - User Properties
    
    func setUserProperty(name: String, value: String?) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserProperty(value, forName: name)
        #endif
        print("📊 Analytics: User property set - \(name): \(value ?? "nil")")
    }
    
    func setUserVerificationStatus(verified: Bool) {
        setUserProperty(name: "user_verified", value: verified ? "true" : "false")
    }
    
    func setUserRole(isAdmin: Bool, isCommittee: Bool) {
        if isAdmin {
            setUserProperty(name: "user_role", value: "admin")
        } else if isCommittee {
            setUserProperty(name: "user_role", value: "committee")
        } else {
            setUserProperty(name: "user_role", value: "member")
        }
    }
    
    // MARK: - Error Tracking
    
    func trackError(_ error: Error, context: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("app_error", parameters: [
            "error_description": error.localizedDescription,
            "error_context": context
        ])
        #endif
        
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().record(error: error)
        Crashlytics.crashlytics().log("Context: \(context)")
        #endif
        
        print("❌ Analytics: Error - \(context): \(error.localizedDescription)")
    }
    
    // MARK: - Performance Tracking
    
    func trackLoadTime(_ screenName: String, duration: TimeInterval) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("screen_load_time", parameters: [
            "screen_name": screenName,
            "duration_ms": Int(duration * 1000)
        ])
        #endif
        print("📊 Analytics: Load time - \(screenName): \(String(format: "%.2f", duration))s")
    }
}
