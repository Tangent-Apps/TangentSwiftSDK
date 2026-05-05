import Foundation
import UIKit
import AdSupport
import AppTrackingTransparency
import SuperwallKit

// MARK: - Superwall Manager
public final class SuperwallManager: NSObject, ObservableObject {

    // MARK: - Singleton
    public static let shared = SuperwallManager()

    // MARK: - Properties
    @Published public private(set) var isInitialized = false
    @Published public var paywallDismissed: Bool = false // Tracks when Superwall paywall is dismissed

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
        Superwall.configure(apiKey: apiKey)
        Superwall.shared.delegate = self

        isInitialized = true
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            Superwall.shared.identify(userId: vendorId)
        }
        setDeviceIds()
        print("✅ Superwall: Initialized")
    }

    /// Sets IDFA/IDFV as Superwall user attributes so S2S integrations (Adjust, etc.)
    /// receive device identifiers. Safe to call multiple times — call again after ATT
    /// consent to pick up a newly available IDFA.
    public func setDeviceIds() {
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        let idfv = UIDevice.current.identifierForVendor?.uuidString

        var attrs: [String: Any] = [:]
        if idfa != "00000000-0000-0000-0000-000000000000" {
            attrs["idfa"] = idfa
        }
        if let idfv {
            attrs["idfv"] = idfv
        }
        if !attrs.isEmpty {
            Superwall.shared.setUserAttributes(attrs)
        }
    }

    // MARK: - Subscription Status

    /// Check if user has an active subscription via Superwall
    public var isSubscribed: Bool {
        if case .active = Superwall.shared.subscriptionStatus {
            return true
        }
        return false
    }

    // MARK: - Paywall Management
    public func register(event: String, params: [String: Any] = [:]) {
        Superwall.shared.register(placement: event, params: params)
    }

    /// Shows the Superwall paywall
    /// - Parameter placement: The Superwall campaign trigger to register. Default is `"campaign_trigger"`.
    /// - Parameter showDiscountAfterDismiss: If `true`, shows a discount paywall after user dismisses. Default is `false`.
    public func showPaywall(placement: String = "campaign_trigger", showDiscountAfterDismiss: Bool = false) {
        self.showDiscountPaywallOnDismiss = showDiscountAfterDismiss
        Superwall.shared.register(placement: placement)
    }

    public func showDiscountPayWall() {
        Superwall.shared.register(placement: "discount_offer")
    }

    public func setUserAttributes(_ attributes: [String: Any]) {
        Superwall.shared.setUserAttributes(attributes)
    }
    
    public func registerAdjustADID(adid: String) {
        Superwall.shared.setIntegrationAttributes([.adjustId: adid])
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
            switch eventInfo.event {
            case .paywallOpen:
                TangentSwiftSDK.shared.analytics.track(event: .paywallViewed)

            case .paywallClose:
                // Notify observers that paywall was dismissed
                self.paywallDismissed = true
                NotificationCenter.default.post(name: .superwallPaywallDismissed, object: nil)

                TangentSwiftSDK.shared.analytics.track(event: .paywallDismissed)

                // Show discount offer with smart logic after paywall is dismissed (if enabled)
                if self.showDiscountPaywallOnDismiss {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if !self.isSubscribed {
                            self.showDiscountPayWall()
                        }
                    }
                }

            case .transactionComplete:
                // Call completion handler if set
                self.onSubscriptionComplete?()

            default:
                break
            }
        }
    }

    nonisolated public func handleLog(level: String, scope: String, message: String?, info: [String : Any]?, error: Error?) {
    }

    public func subscriptionStatusDidChange(from oldValue: SuperwallKit.SubscriptionStatus, to newValue: SuperwallKit.SubscriptionStatus) {
        print("📦 SuperwallManager: subscriptionStatus changed from \(oldValue) to \(newValue)")

        NotificationCenter.default.post(
            name: .superwallSubscriptionStatusDidChange,
            object: nil,
            userInfo: [
                "oldValue": oldValue.description,
                "newValue": newValue.description,
                "isActive": newValue.isActive
            ]
        )
    }
}

// MARK: - Notification Names
extension Notification.Name {
    public static let superwallPaywallDismissed = Notification.Name("superwallPaywallDismissed")
    public static let superwallSubscriptionStatusDidChange = Notification.Name("superwallSubscriptionStatusDidChange")
}
