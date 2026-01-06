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

    /// Controls whether to show discount paywall after Superwall dismissal
    private var showDiscountPaywallOnDismiss: Bool = false
    
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
        print("✅ Superwall: Initialized")
    }

    // MARK: - Paywall Management
    public func register(event: String, params: [String: Any] = [:]) {
        Superwall.shared.register(placement: event, params: params)
    }
    
    /// Shows the Superwall paywall
    /// - Parameter showDiscountAfterDismiss: If `true`, shows a discount paywall after user dismisses. Default is `false`.
    public func showPaywall(showDiscountAfterDismiss: Bool = false) {
        self.showDiscountPaywallOnDismiss = showDiscountAfterDismiss
        Superwall.shared.register(placement: "campaign_trigger")
    }
    
    public func showDiscountPayWall() {
        Superwall.shared.register(placement: "discount_offer")
    }
    
    public func setUserAttributes(_ attributes: [String: Any]) {
        Superwall.shared.setUserAttributes(attributes)
    }

    public func identify(userId: String) {
        Superwall.shared.identify(userId: userId)
    }

    public func reset() {
        Superwall.shared.reset()
    }

    /// Update Superwall user properties for onboarding status
    public func updateOnboardingStatus(_ hasCompleted: Bool) {
        setUserAttributes([
            "has_completed_onboarding": hasCompleted
        ])
    }

    // MARK: - Debug: Fetch Paywalls
    /// Fetches and prints Superwall configuration for debugging integration issues
    public func fetchPaywalls() async {
        guard isInitialized else { return }
    }
}

// MARK: - SuperwallDelegate
extension SuperwallManager: SuperwallDelegate {
    nonisolated public func handleSuperwallEvent(withInfo eventInfo: SuperwallEventInfo) {
        Task { @MainActor in
            let eventName = String(describing: eventInfo.event)

            switch eventInfo.event {
            case .paywallOpen:
                TangentSwiftSDK.shared.analytics.track(event: .paywallViewed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

            case .paywallClose:
                // Notify observers that paywall was dismissed
                self.paywallDismissed = true
                NotificationCenter.default.post(name: .superwallPaywallDismissed, object: nil)

                TangentSwiftSDK.shared.analytics.track(event: .paywallDismissed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

                // Show discount offer with smart logic after paywall is dismissed (if enabled)
                if self.showDiscountPaywallOnDismiss {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if !TangentSwiftSDK.shared.paywall.isSubscribed {
                            self.showDiscountPayWall()
                        }
                    }
                }

            case .transactionStart:
                TangentSwiftSDK.shared.analytics.track(event: .purchaseStarted, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

            case .transactionComplete:
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
                TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

            case .transactionAbandon:
                TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                    "source": "superwall",
                    "event": eventName,
                    "reason": "user_cancelled"
                ])

            case .transactionRestore:
                TangentSwiftSDK.shared.analytics.track(event: .purchaseRestored, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

            default:
                break
            }
        }
    }

    nonisolated public func handleLog(level: String, scope: String, message: String?, info: [String : Any]?, error: Error?) {
    }
}

// MARK: - Notification Names
extension Notification.Name {
    public static let superwallPaywallDismissed = Notification.Name("superwallPaywallDismissed")
}
