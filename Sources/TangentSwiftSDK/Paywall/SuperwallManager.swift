import Foundation
import SuperwallKit
import RevenueCat

// MARK: - Superwall Manager
@MainActor
public final class SuperwallManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    public static let shared = SuperwallManager()
    
    // MARK: - Properties
    @Published public private(set) var isInitialized = false
    private let purchaseController = RCPurchaseController()
    
    // MARK: - Initialization
    private override init() {
        super.init()
    }
    
    // MARK: - Configuration
    public func initialize(apiKey: String) {
        Superwall.configure(
            apiKey: apiKey,
            purchaseController: purchaseController
        )
        Superwall.shared.delegate = self
        
        // Start subscription sync
        purchaseController.syncSubscriptionStatus()
        
        isInitialized = true
        print("✅ Superwall: Configured successfully with API key and purchase controller")
    }
    
    // MARK: - Paywall Management
    public func register(event: String, params: [String: Any] = [:]) {
        Superwall.shared.register(event: event, params: params)
        print("📱 Superwall: Registered event - \(event)")
    }
    
    public func showPaywall() {
        Superwall.shared.register(event: "campaign_trigger")
    }
    
    public func showDiscountPayWall() {
        Superwall.shared.register(event: "paywall_decline")
    }
    
    public func setUserAttributes(_ attributes: [String: Any]) {
        Superwall.shared.setUserAttributes(attributes)
        print("👤 Superwall: User attributes set")
    }
    
    public func identify(userId: String) {
        Superwall.shared.identify(userId: userId)
        print("👤 Superwall: User identified - \(userId)")
    }
    
    public func reset() {
        Superwall.shared.reset()
        print("🔄 Superwall: User reset")
    }
    
    /// Update Superwall user properties for onboarding status
    public func updateOnboardingStatus(_ hasCompleted: Bool) {
        setUserAttributes([
            "has_completed_onboarding": hasCompleted
        ])
        print("✅ Superwall: Updated onboarding status to \(hasCompleted)")
    }
}

// MARK: - SuperwallDelegate
extension SuperwallManager: SuperwallDelegate {
    nonisolated public func handleSuperwallEvent(withInfo eventInfo: SuperwallEventInfo) {
        Task { @MainActor in
            print("📱 Superwall Event: \(eventInfo.event)")
            
            switch eventInfo.event {
            case "paywall_open":
                print("🚀 Superwall paywall opened")
                TangentSwiftSDK.shared.analytics.track(event: .paywallViewed, properties: [
                    "source": "superwall",
                    "event": eventInfo.event
                ])
                
            case "paywall_close":
                print("🚀 Superwall paywall closed")
                TangentSwiftSDK.shared.analytics.track(event: .paywallDismissed, properties: [
                    "source": "superwall",
                    "event": eventInfo.event
                ])
                
                // Show discount offer with smart logic after paywall is dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if !TangentSwiftSDK.shared.paywall.isSubscribed {
                        print("🎟️ Showing discount paywall after Superwall dismissal")
                        self.showDiscountPayWall()
                    }
                }
                
            case "transaction_start":
                print("🚀 Superwall transaction started")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseStarted, properties: [
                    "source": "superwall",
                    "event": eventInfo.event
                ])
                
            case "transaction_complete":
                print("✅ Superwall purchase completed")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseCompleted, properties: [
                    "source": "superwall",
                    "event": eventInfo.event
                ])
                TangentSwiftSDK.shared.analytics.track(event: .subscriptionActivated, properties: [
                    "source": "superwall",
                    "event": eventInfo.event
                ])
                
            case "transaction_fail":
                print("❌ Superwall transaction failed")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                    "source": "superwall",
                    "event": eventInfo.event
                ])
                
            case "transaction_abandon":
                print("🚫 Superwall transaction abandoned")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                    "source": "superwall",
                    "event": eventInfo.event,
                    "reason": "user_cancelled"
                ])
                
            case "transaction_restore":
                print("🔄 Superwall purchase restored")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseRestored, properties: [
                    "source": "superwall",
                    "event": eventInfo.event
                ])
                
            default:
                break
            }
        }
    }
    
    nonisolated public func handleLog(level: String, scope: String, message: String?, info: [String : Any]?, error: Error?) {
        #if DEBUG
        print("📱 Superwall Log [\(level)]: \(message ?? "")")
        #endif
    }
}
