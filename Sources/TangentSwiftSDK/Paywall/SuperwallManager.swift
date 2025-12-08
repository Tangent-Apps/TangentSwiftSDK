import Foundation
import SuperwallKit
import RevenueCat

// MARK: - Superwall Manager
public final class SuperwallManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    public static let shared = SuperwallManager()
    
    // MARK: - Properties
    @Published public private(set) var isInitialized = false
    @Published public var paywallDismissed: Bool = false // Tracks when Superwall paywall is dismissed
    private let purchaseController = RCPurchaseController()

    // Completion handler called when subscription is successful
    public var onSubscriptionComplete: (() -> Void)?
    
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
        Superwall.shared.register(placement: event, params: params)
        print("📱 Superwall: Registered event - \(event)")
    }
    
    public func showPaywall() {
        Superwall.shared.register(placement: "campaign_trigger")
    }
    
    public func showDiscountPayWall() {
        Superwall.shared.register(placement: "paywall_decline")
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

    // MARK: - Debug: Fetch Paywalls
    /// Fetches and prints Superwall configuration for debugging integration issues
    public func fetchPaywalls() async {
        print("🔍 Superwall: Checking configuration...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        guard isInitialized else {
            print("❌ Superwall: Not initialized. Call initialize(apiKey:) first.")
            return
        }

        print("✅ Superwall: SDK is initialized")
        print("   User ID: \(Superwall.shared.userId)")
        print("   Is Logged In: \(Superwall.shared.isLoggedIn)")
        print("   Subscription Status: \(Superwall.shared.subscriptionStatus)")

        // Get user attributes
        let attributes = Superwall.shared.userAttributes
        print("   User Attributes: \(attributes)")

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ Superwall: Configuration check complete")
        print("   Note: Paywalls are configured remotely in Superwall dashboard")
        print("   Trigger a placement to test paywall display")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - SuperwallDelegate
extension SuperwallManager: SuperwallDelegate {
    nonisolated public func handleSuperwallEvent(withInfo eventInfo: SuperwallEventInfo) {
        Task { @MainActor in
            let eventName = String(describing: eventInfo.event)
            print("📱 Superwall Event: \(eventName)")
            
            switch eventInfo.event {
            case .paywallOpen:
                print("🚀 Superwall paywall opened")
                TangentSwiftSDK.shared.analytics.track(event: .paywallViewed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])
                
            case .paywallClose:
                print("🚀 Superwall paywall closed")

                // Notify observers that paywall was dismissed
                self.paywallDismissed = true
                NotificationCenter.default.post(name: .superwallPaywallDismissed, object: nil)

                TangentSwiftSDK.shared.analytics.track(event: .paywallDismissed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

                // Show discount offer with smart logic after paywall is dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if !TangentSwiftSDK.shared.paywall.isSubscribed {
                        print("🎟️ Showing discount paywall after Superwall dismissal")
                        self.showDiscountPayWall()
                    }
                }
                
            case .transactionStart:
                print("🚀 Superwall transaction started")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseStarted, properties: [
                    "source": "superwall",
                    "event": eventName
                ])
                
            case .transactionComplete:
                print("✅ Superwall purchase completed")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseCompleted, properties: [
                    "source": "superwall",
                    "event": eventName
                ])
                TangentSwiftSDK.shared.analytics.track(event: .subscriptionActivated, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

                // Call completion handler if set
                self.onSubscriptionComplete?()
                
            case .transactionFail:
                print("❌ Superwall transaction failed")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])
                
            case .transactionAbandon:
                print("🚫 Superwall transaction abandoned")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                    "source": "superwall",
                    "event": eventName,
                    "reason": "user_cancelled"
                ])
                
            case .transactionRestore:
                print("🔄 Superwall purchase restored")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseRestored, properties: [
                    "source": "superwall",
                    "event": eventName
                ])
                
            default:
                // Handle other events
                print("📱 Superwall Event (other): \(eventName)")
            }
        }
    }
    
    nonisolated public func handleLog(level: String, scope: String, message: String?, info: [String : Any]?, error: Error?) {
        #if DEBUG
        print("📱 Superwall Log [\(level)]: \(message ?? "")")
        #endif
    }
}

// MARK: - Notification Names
extension Notification.Name {
    public static let superwallPaywallDismissed = Notification.Name("superwallPaywallDismissed")
}
