import Foundation
import SuperwallKit

// MARK: - Superwall Manager
@MainActor
public final class SuperwallManager: NSObject, ObservableObject {

    // MARK: - Singleton
    public static let shared = SuperwallManager()

    // MARK: - Properties
    @Published public private(set) var isInitialized = false
    @Published public var paywallDismissed: Bool = false // Tracks when Superwall paywall is dismissed
    private let purchaseController = StoreKitPurchaseController()

    /// Tracks whether a Superwall paywall is currently open, so we only attribute
    /// transaction events to Superwall when the purchase was actually initiated from it.
    private var isSuperwallPaywallOpen = false

    // Completion handler called when subscription is successful
    public var onSubscriptionComplete: (() -> Void)?

    /// appAccountToken attached to Superwall-driven StoreKit purchases so
    /// App Store Server Notifications can attribute them to a user
    /// server-side. Set once at app startup, before any paywall shows.
    public var appAccountToken: UUID? {
        get { StoreKitPurchaseController.appAccountToken }
        set { StoreKitPurchaseController.appAccountToken = newValue }
    }

    // MARK: - Initialization
    private override init() {
        super.init()
    }
    
    // MARK: - Configuration
    public func initialize(apiKey: String, isSubscribed: Bool = false) {
        // Idempotency — Superwall.configure must only be called once per process.
        // SDK init and DIContainer both used to call this; now SDK init owns it
        // exclusively, but the guard protects against accidental double-init
        // (e.g. tests, hot-reload).
        guard !isInitialized else {
            if isSubscribed {
                Superwall.shared.subscriptionStatus = .active(Set([Entitlement(id: "Pro")]))
            }
            return
        }

        Superwall.configure(
            apiKey: apiKey,
            purchaseController: purchaseController
        )
        Superwall.shared.delegate = self

        // Mark subscribed IMMEDIATELY after configure, before any auto-triggers
        if isSubscribed {
            Superwall.shared.subscriptionStatus = .active(Set([Entitlement(id: "Pro")]))
            print("✅ Superwall: User already subscribed — set active before sync")
        }

        // Start subscription sync (StoreKitPurchaseController listens to
        // Transaction.updates and Transaction.currentEntitlements)
        purchaseController.syncSubscriptionStatus()

        isInitialized = true
        print("✅ Superwall: Configured successfully with API key and purchase controller")
    }
    
    // MARK: - Paywall Management
    public func register(event: String, params: [String: Any] = [:]) {
        Superwall.shared.register(placement: event, params: params)
        print("📱 Superwall: Registered event - \(event)")
    }
    
    /// Register a placement and report back what Superwall actually DID with it.
    ///
    /// ⚠️ **`register(event:params:)` above is fire-and-forget, and silence from
    /// it is ambiguous in the worst way.** A campaign that is paused, filtered out
    /// by an audience rule, held out for an experiment, or simply not configured
    /// produces exactly the same nothing as a campaign that is about to present —
    /// so an app waiting on a paywall cannot tell "any moment now" from "never",
    /// and shows a spinner forever. Superwall knows the difference and will say so
    /// if asked; this is the asking.
    ///
    /// Additive: the existing `register` is untouched, so Poly.ai is unchanged.
    public func registerWithHandler(
        event: String,
        params: [String: Any] = [:],
        onPresent: (() -> Void)? = nil,
        onSkip: ((String) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        let handler = PaywallPresentationHandler()
        handler.onPresent { info in
            print("📱 Superwall: PRESENTED \(event) — \(info.identifier)")
            Task { @MainActor in onPresent?() }
        }
        handler.onSkip { reason in
            print("⚠️ Superwall: SKIPPED \(event) — \(reason.description)")
            Task { @MainActor in onSkip?(reason.description) }
        }
        handler.onError { error in
            print("❌ Superwall: ERROR \(event) — \(error.localizedDescription)")
            Task { @MainActor in onError?(error.localizedDescription) }
        }
        Superwall.shared.register(placement: event, params: params, handler: handler)
        print("📱 Superwall: Registered event - \(event) (with handler)")
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
    
    public func setSubscribed() {
        guard isInitialized else { return }
        Superwall.shared.subscriptionStatus = .active(Set([Entitlement(id: "Pro")]))
        print("✅ Superwall: Marked user as subscribed (Pro)")
    }

    /// Push the NOT-subscribed state to Superwall. Without this, once
    /// `setSubscribed()` forces `.active` Superwall stays active forever and
    /// refuses to present gated placements even after the app loses premium
    /// (e.g. sandbox expiry) — stranding the user with no way to re-subscribe.
    public func setUnsubscribed() {
        guard isInitialized else { return }
        Superwall.shared.subscriptionStatus = .inactive
        print("🚫 Superwall: Marked user as not subscribed (inactive)")
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
            let eventName = String(describing: eventInfo.event)
            print("📱 Superwall Event: \(eventName)")
            
            switch eventInfo.event {
            case .paywallOpen:
                print("🚀 Superwall paywall opened")
                self.isSuperwallPaywallOpen = true
                TangentSwiftSDK.shared.analytics.track(event: .paywallViewed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

            case .paywallClose:
                print("🚀 Superwall paywall closed")
                self.isSuperwallPaywallOpen = false

                // Notify observers that paywall was dismissed
                self.paywallDismissed = true
                NotificationCenter.default.post(name: .superwallPaywallDismissed, object: nil)

                TangentSwiftSDK.shared.analytics.track(event: .paywallDismissed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

                // Show discount offer with smart logic after paywall is dismissed.
                // Read entitlement from Superwall's own subscriptionStatus —
                // StoreKitPurchaseController keeps it synced from
                // Transaction.updates, so we don't need an external check.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let isSubscribed: Bool
                    if case .active = Superwall.shared.subscriptionStatus {
                        isSubscribed = true
                    } else {
                        isSubscribed = false
                    }
                    if !isSubscribed {
                        print("🎟️ Showing discount paywall after Superwall dismissal")
                        self.showDiscountPayWall()
                    }
                }

            case .transactionStart:
                guard self.isSuperwallPaywallOpen else { break }
                print("🚀 Superwall transaction started")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseStarted, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

            case .transactionComplete:
                guard self.isSuperwallPaywallOpen else {
                    // Still call completion handler for navigation
                    self.onSubscriptionComplete?()
                    break
                }
                print("✅ Superwall purchase completed")
                // NOTE: Purchase Completed and Subscription Activated events
                // are NOT fired here. The app-side PurchaseAttributionForwarder
                // emits them with full product context (product_id, revenue,
                // currency, transaction_id) — firing them from this delegate
                // produced the "product_id: undefined" data-quality bug.
                // StoreKitPurchaseController posts a notification that the
                // forwarder observes for explicit hand-off.

                // Call completion handler if set
                self.onSubscriptionComplete?()

            case .transactionFail:
                guard self.isSuperwallPaywallOpen else { break }
                print("❌ Superwall transaction failed")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                    "source": "superwall",
                    "event": eventName
                ])

            case .transactionAbandon:
                guard self.isSuperwallPaywallOpen else { break }
                print("🚫 Superwall transaction abandoned")
                TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                    "source": "superwall",
                    "event": eventName,
                    "reason": "user_cancelled"
                ])

            case .transactionRestore:
                guard self.isSuperwallPaywallOpen else { break }
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
