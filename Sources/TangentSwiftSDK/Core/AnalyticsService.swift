import Foundation
import Mixpanel

// MARK: - Analytics Service
@MainActor
public final class AnalyticsService {
    public static let shared = AnalyticsService()
    
    private init() {}
    
    // MARK: - Event Tracking
    
    /// Track a predefined analytics event
    public func track(event: AnalyticsEvent, properties: [String: MixpanelType]? = nil) {
        MixpanelManager.shared.track(event: event, properties: properties)
        
        // Also track with Adjust if it's a revenue event
        if event == .purchaseCompleted || event == .subscriptionActivated {
            AdjustManager.shared.trackCustomEvent(event.rawValue, parameters: convertToStringDict(properties))
        }
    }
    
    /// Track a custom event by name
    public func trackCustomEvent(_ name: String, properties: [String: MixpanelType]? = nil) {
        MixpanelManager.shared.trackCustomEvent(name, properties: properties)
        AdjustManager.shared.trackCustomEvent(name, parameters: convertToStringDict(properties))
    }
    
    /// Track screen view
    public func trackScreenView(_ screenName: String, properties: [String: MixpanelType]? = nil) {
        MixpanelManager.shared.trackScreenView(screenName, properties: properties)
    }
    
    /// Track button tap
    public func trackButtonTap(_ buttonName: String, screen: String? = nil) {
        MixpanelManager.shared.trackButtonTap(buttonName, screen: screen)
    }
    
    /// Track error
    public func trackError(_ error: Error, context: String? = nil) {
        MixpanelManager.shared.trackError(error, context: context)
    }
    
    // MARK: - User Management
    
    /// Identify user
    public func identify(userId: String) {
        MixpanelManager.shared.identify(userId: userId)
    }
    
    /// Set user profile properties
    public func setUserProfile(properties: [String: MixpanelType]) {
        MixpanelManager.shared.setUserProfile(properties: properties)
    }
    
    /// Update a single user property
    public func updateUserProperty(key: String, value: MixpanelType) {
        MixpanelManager.shared.updateUserProperty(key: key, value: value)
    }
    
    // MARK: - Revenue Tracking
    
    /// Track revenue
    public func trackRevenue(amount: Double, productId: String, transactionId: String? = nil) {
        MixpanelManager.shared.trackRevenue(amount: amount, productId: productId, transactionId: transactionId)
    }
    
    // MARK: - Session Management
    
    /// Start session
    public func startSession() {
        MixpanelManager.shared.startSession()
    }
    
    /// End session
    public func endSession() {
        MixpanelManager.shared.endSession()
    }
    
    // MARK: - Helper Methods
    
    private func convertToStringDict(_ properties: [String: MixpanelType]?) -> [String: String] {
        guard let properties = properties else { return [:] }
        
        var stringDict: [String: String] = [:]
        for (key, value) in properties {
            stringDict[key] = "\(value)"
        }
        return stringDict
    }
}