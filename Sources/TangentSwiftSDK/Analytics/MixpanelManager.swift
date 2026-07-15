import Foundation
import Mixpanel

// MARK: - Mixpanel Manager
@MainActor
public final class MixpanelManager: NSObject {
    
    // MARK: - Singleton
    public static let shared = MixpanelManager()
    
    // MARK: - Properties
    private var mixpanel: MixpanelInstance?
    private var userProperties: [String: MixpanelType] = [:]
    
    // MARK: - Initialization
    private override init() {
        super.init()
    }
    
    // MARK: - Configuration
    public func initialize(token: String) {
        Mixpanel.initialize(token: token, trackAutomaticEvents: true)
        mixpanel = Mixpanel.mainInstance()
        
        #if DEBUG
        mixpanel?.loggingEnabled = true
        #endif
        
        print("✅ Mixpanel: Configured successfully")
    }
    
    // MARK: - User Identification
    public func identify(userId: String) {
        mixpanel?.identify(distinctId: userId)
        print("📊 Mixpanel: User identified - \(userId)")
    }
    
    public func setUserProfile(properties: [String: MixpanelType]) {
        mixpanel?.people.set(properties: properties)
        userProperties = properties
        print("📊 Mixpanel: User profile updated")
    }
    
    public func updateUserProperty(key: String, value: MixpanelType) {
        mixpanel?.people.set(property: key, to: value)
        userProperties[key] = value
    }
    
    // MARK: - Event Tracking
    public func track(event: AnalyticsEvent, properties: [String: MixpanelType]? = nil) {
        var eventProperties = properties ?? [:]
        
        // Add common properties
        eventProperties["platform"] = "iOS"
        eventProperties["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        mixpanel?.track(event: event.rawValue, properties: eventProperties)
        
        #if DEBUG
        print("📊 Mixpanel: Tracked '\(event.rawValue)' with properties: \(eventProperties)")
        #endif
    }
    
    public func trackCustomEvent(_ eventName: String, properties: [String: MixpanelType]? = nil) {
        var eventProperties = properties ?? [:]
        
        // Add common properties
        eventProperties["platform"] = "iOS"
        eventProperties["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        mixpanel?.track(event: eventName, properties: eventProperties)
        
        #if DEBUG
        print("📊 Mixpanel: Tracked '\(eventName)' with properties: \(eventProperties)")
        #endif
    }
    
    // MARK: - Timed Events
    public func timeEvent(_ event: AnalyticsEvent) {
        mixpanel?.time(event: event.rawValue)
        print("⏱ Mixpanel: Started timing '\(event.rawValue)'")
    }
    
    /// People charge only — no `Purchase Completed` event side-effect.
    /// Use this when the caller is already firing a richer Purchase Completed
    /// event themselves (e.g. PurchaseAttributionForwarder) and just needs
    /// the Mixpanel People profile revenue update.
    public func trackPeopleCharge(amount: Double, properties: [String: MixpanelType] = [:]) {
        guard amount > 0 else { return }
        mixpanel?.people.trackCharge(amount: amount, properties: properties)
        #if DEBUG
        print("💰 Mixpanel: People charge \(amount)")
        #endif
    }

    // MARK: - Revenue Tracking
    public func trackRevenue(amount: Double, productId: String, transactionId: String? = nil) {
        var properties: [String: MixpanelType] = [
            "amount": amount,
            "product_id": productId,
            "currency": "USD"
        ]
        
        if let transactionId = transactionId {
            properties["transaction_id"] = transactionId
        }
        
        mixpanel?.people.trackCharge(amount: amount, properties: properties)
        track(event: .purchaseCompleted, properties: properties)
        
        print("💰 Mixpanel: Revenue tracked - $\(amount) for \(productId)")
    }
    
    // MARK: - Super Properties
    public func setSuperProperties(_ properties: [String: MixpanelType]) {
        mixpanel?.registerSuperProperties(properties)
        print("📊 Mixpanel: Super properties set")
    }
    
    public func clearSuperProperties() {
        mixpanel?.clearSuperProperties()
    }
    
    // MARK: - Session Management
    public func startSession() {
        track(event: .sessionStart)
    }
    
    public func endSession() {
        track(event: .sessionEnd)
    }
    
    // MARK: - Reset
    public func reset() {
        mixpanel?.reset()
        userProperties.removeAll()
        print("📊 Mixpanel: Reset complete")
    }
    
    // MARK: - ATT Support
    public func updateTrackingPermission(_ allowed: Bool) {
        if allowed {
            print("📊 Mixpanel: Full tracking enabled")
        } else {
            print("📊 Mixpanel: Anonymous tracking only")
        }
    }
}

// MARK: - Helper Extensions
public extension MixpanelManager {
    
    func trackScreenView(_ screenName: String, properties: [String: MixpanelType]? = nil) {
        var props = properties ?? [:]
        props["screen_name"] = screenName
        track(event: .screenViewed, properties: props)
    }
    
    func trackButtonTap(_ buttonName: String, screen: String? = nil) {
        var props: [String: MixpanelType] = ["button_name": buttonName]
        if let screen = screen {
            props["screen"] = screen
        }
        track(event: .buttonTapped, properties: props)
    }
    
    func trackError(_ error: Error, context: String? = nil) {
        var props: [String: MixpanelType] = [
            "error_message": error.localizedDescription,
            "error_type": String(describing: type(of: error))
        ]
        if let context = context {
            props["context"] = context
        }
        track(event: .errorOccurred, properties: props)
    }
}