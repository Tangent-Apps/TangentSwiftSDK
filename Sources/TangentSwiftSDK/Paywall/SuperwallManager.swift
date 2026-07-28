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

    /// Attribution context for the most recently seen Superwall paywall.
    ///
    /// Captured on `.paywallOpen` and upgraded on `.transactionComplete`
    /// (`didConvert = true`, `productId` set). Consumers firing purchase
    /// analytics from StoreKit's `Transaction.updates` can read this to
    /// attribute the purchase to the paywall/placement/experiment that drove
    /// it — `paywallOpen` always precedes the transaction, so the context is
    /// in place regardless of delegate-vs-listener ordering.
    public struct PaywallAttribution {
        public let paywallId: String
        public let paywallName: String
        /// The placement that triggered the paywall (nil when presented programmatically).
        public let placement: String?
        /// How the paywall was presented: "programmatically", "identifier", or "placement".
        public let presentedBy: String
        public let experimentId: String?
        public let variantId: String?
        /// Product purchased on this paywall. Only set once `didConvert` is true.
        public let productId: String?
        public let didConvert: Bool
        public let capturedAt: Date
    }

    /// The last paywall the user saw (or converted on). See ``PaywallAttribution``.
    public private(set) var lastPaywallAttribution: PaywallAttribution?

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

    // MARK: - Deep Link Handling (Stripe web checkout return)
    public func handleDeepLink(_ url: URL) {
        _ = Superwall.handleDeepLink(url)
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
            case .paywallOpen(let paywallInfo):
                self.lastPaywallAttribution = Self.attribution(from: paywallInfo, productId: nil, didConvert: false)
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

            case .transactionComplete(_, let product, _, let paywallInfo):
                self.lastPaywallAttribution = Self.attribution(from: paywallInfo, productId: product.productIdentifier, didConvert: true)
                // Call completion handler if set
                self.onSubscriptionComplete?()

            default:
                break
            }
        }
    }

    private static func attribution(from paywallInfo: PaywallInfo, productId: String?, didConvert: Bool) -> PaywallAttribution {
        PaywallAttribution(
            paywallId: paywallInfo.identifier,
            paywallName: paywallInfo.name,
            placement: paywallInfo.presentedByPlacementWithName,
            presentedBy: paywallInfo.presentedBy,
            experimentId: paywallInfo.experiment?.id,
            variantId: paywallInfo.experiment?.variant.id,
            productId: productId,
            didConvert: didConvert,
            capturedAt: Date()
        )
    }

    nonisolated public func handleLog(level: String, scope: String, message: String?, info: [String : Any]?, error: Error?) {
    }

    public func subscriptionStatusDidChange(from oldValue: SuperwallKit.SubscriptionStatus, to newValue: SuperwallKit.SubscriptionStatus) {
        print("📦 SuperwallManager: subscriptionStatus changed from \(oldValue) to \(newValue)")

        // Stripe web checkout: fire completion when user transitions to active
        if newValue.isActive && !oldValue.isActive {
            Task { @MainActor in
                self.onSubscriptionComplete?()
            }
        }

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

    nonisolated public func willRedeemLink() {
        print("📦 SuperwallManager: willRedeemLink — Stripe return URL received, verifying...")
        NotificationCenter.default.post(name: .superwallWillRedeemLink, object: nil)
    }

    nonisolated public func didRedeemLink(result: RedemptionResult) {
        print("📦 SuperwallManager: didRedeemLink — result: \(result)")

        var info: [String: Any] = [:]
        switch result {
        case .success(let code, _):
            info["status"] = "success"
            info["code"] = code
        case .error(let code, let error):
            info["status"] = "error"
            info["code"] = code
            info["message"] = error.message
        case .expiredCode(let code, _):
            info["status"] = "expiredCode"
            info["code"] = code
        case .invalidCode(let code):
            info["status"] = "invalidCode"
            info["code"] = code
        case .expiredSubscription(let code, _):
            info["status"] = "expiredSubscription"
            info["code"] = code
        }

        NotificationCenter.default.post(name: .superwallDidRedeemLink, object: nil, userInfo: info)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    public static let superwallPaywallDismissed = Notification.Name("superwallPaywallDismissed")
    public static let superwallSubscriptionStatusDidChange = Notification.Name("superwallSubscriptionStatusDidChange")

    /// Fired when the Superwall SDK begins redeeming a web-checkout (Stripe) deep link.
    /// Observe to show a "Redeeming…" progress state.
    public static let superwallWillRedeemLink = Notification.Name("superwallWillRedeemLink")

    /// Fired when the Superwall SDK finishes a redemption attempt. `userInfo` carries:
    /// - `status`: one of `success` | `error` | `expiredCode` | `invalidCode` | `expiredSubscription`
    /// - `code`: the redemption code
    /// - `message`: present only for `error` status
    public static let superwallDidRedeemLink = Notification.Name("superwallDidRedeemLink")
}
