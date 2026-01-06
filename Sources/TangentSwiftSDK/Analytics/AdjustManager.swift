import Foundation
@preconcurrency import AdjustSdk
import RevenueCat

public final class AdjustManager: NSObject, ObservableObject {
    public static let shared = AdjustManager()

    @Published public private(set) var isInitialized = false
    @Published public private(set) var adid: String?

    private var purchaseEventToken: String?

    private override init() {
        super.init()
    }

    // MARK: - Configuration

    public func initialize(appToken: String, environment: String = "production", purchaseEventToken: String) {
        let cleanToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let adjustEnvironment = environment == "sandbox" ? ADJEnvironmentSandbox : ADJEnvironmentProduction

        guard let config = ADJConfig(
            appToken: cleanToken,
            environment: adjustEnvironment
        ) else {
            print("❌ Adjust: Failed to create config")
            return
        }

        config.logLevel = ADJLogLevel.verbose
        config.delegate = self
        config.attConsentWaitingInterval = 120
        self.purchaseEventToken = purchaseEventToken

        Adjust.initSdk(config)
        isInitialized = true
        print("✅ Adjust: Initialized (\(adjustEnvironment == ADJEnvironmentSandbox ? "sandbox" : "production"))")

        // Check for ADID after delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let adid = await Adjust.adid(), self.adid == nil {
                await MainActor.run { self.adid = adid }
                Purchases.shared.attribution.setAdjustID(adid)
                print("✅ Adjust: Set ADID on RevenueCat: \(adid)")
            }
        }

        trackAppLaunch()
    }

    // MARK: - Event Tracking

    /// Track app launch event
    public func trackAppLaunch() {
        trackCustomEvent("app_launched", parameters: [
            "platform": "iOS",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        ])
    }

    /// Track onboarding completion
    public func trackOnboardingCompleted(additionalProperties: [String: String] = [:]) {
        trackCustomEvent("onboarding_completed", parameters: additionalProperties)
    }

    /// Track paywall view
    public func trackPaywallViewed(source: String, placement: String? = nil) {
        var parameters = ["source": source]
        if let placement = placement {
            parameters["placement"] = placement
        }
        trackCustomEvent("paywall_viewed", parameters: parameters)
    }

    /// Track purchase started
    public func trackPurchaseStarted(productId: String, source: String) {
        trackCustomEvent("purchase_started", parameters: [
            "product_id": productId,
            "source": source
        ])
    }

    /// Track purchase completed with revenue
    public func trackPurchaseCompleted(productId: String, amount: Double, currency: String = "USD", source: String) {
        guard let eventToken = purchaseEventToken else {
            print("⚠️ Adjust: Purchase event token not configured")
            return
        }

        if let revenueEvent = ADJEvent(eventToken: eventToken) {
            revenueEvent.setRevenue(amount, currency: currency)
            revenueEvent.setProductId(productId)
            revenueEvent.addCallbackParameter("source", value: source)
            revenueEvent.addCallbackParameter("product_id", value: productId)
            Adjust.trackEvent(revenueEvent)
            print("💰 Adjust: Revenue tracked - \(amount) \(currency) for \(productId)")
        }

        trackCustomEvent("purchase_completed", parameters: [
            "product_id": productId,
            "amount": String(amount),
            "currency": currency,
            "source": source
        ])
    }

    /// Track subscription activation
    public func trackSubscriptionActivated(productId: String? = nil, source: String) {
        var parameters = ["source": source]
        if let productId = productId {
            parameters["product_id"] = productId
        }
        trackCustomEvent("subscription_activated", parameters: parameters)
    }

    /// Track purchase failed
    public func trackPurchaseFailed(productId: String? = nil, reason: String? = nil, source: String) {
        var parameters = ["source": source]
        if let productId = productId {
            parameters["product_id"] = productId
        }
        if let reason = reason {
            parameters["reason"] = reason
        }
        trackCustomEvent("purchase_failed", parameters: parameters)
    }

    /// Track purchase restored
    public func trackPurchaseRestored(productIds: [String]? = nil, source: String) {
        var parameters = ["source": source]
        if let productIds = productIds {
            parameters["restored_products"] = productIds.joined(separator: ",")
        }
        trackCustomEvent("purchase_restored", parameters: parameters)
    }

    // MARK: - Generic Event Tracking

    /// Track custom event with parameters
    public func trackCustomEvent(_ eventName: String, parameters: [String: String] = [:]) {
        guard isInitialized else { return }
    }

    /// Track event with specific token
    public func trackEvent(_ eventToken: String, parameters: [String: String] = [:]) {
        guard isInitialized else { return }

        guard let event = ADJEvent(eventToken: eventToken) else {
            print("❌ Adjust: Failed to create event with token: \(eventToken)")
            return
        }

        for (key, value) in parameters {
            event.addCallbackParameter(key, value: value)
        }

        Adjust.trackEvent(event)
    }

    // MARK: - Attribution

    private func handleAttributionCallback(_ attribution: ADJAttribution?) {
        guard let attribution = attribution else { return }

        Adjust.adid(completionHandler: { [weak self] adid in
            Task { @MainActor in
                self?.adid = adid

                print("📈 Adjust Attribution:")
                print("  - ADID: \(adid ?? "N/A")")
                print("  - Network: \(attribution.network ?? "N/A")")
                print("  - Campaign: \(attribution.campaign ?? "N/A")")
                print("  - Creative: \(attribution.creative ?? "N/A")")
                print("  - Click Label: \(attribution.clickLabel ?? "N/A")")
            }
        })
    }

    // MARK: - ATT Support
    public func updateTrackingPermission(_ allowed: Bool) {
        if allowed {
            print("📊 Adjust: Full tracking enabled")
        } else {
            print("📊 Adjust: Limited tracking")
        }
    }

    public func trackATTPermission(granted: Bool, status: String) {
        print("📊 Adjust: ATT Permission - Granted: \(granted), Status: \(status)")
    }
}

// MARK: - AdjustDelegate
extension AdjustManager: AdjustDelegate {
    nonisolated public func adjustAttributionChanged(_ attribution: ADJAttribution?) {
        Task { @MainActor in
            handleAttributionCallback(attribution)
        }
    }

    nonisolated public func adjustEventTrackingSucceeded(_ eventSuccessResponseData: ADJEventSuccess?) {
        print("✅ Adjust: Event tracking succeeded - \(eventSuccessResponseData?.eventToken ?? "unknown")")
    }

    nonisolated public func adjustEventTrackingFailed(_ eventFailureResponseData: ADJEventFailure?) {
        print("❌ Adjust: Event failed - \(eventFailureResponseData?.message ?? "unknown")")
    }

    nonisolated public func adjustSessionTrackingSucceeded(_ sessionSuccessResponseData: ADJSessionSuccess?) {
        Adjust.adid { adid in
            Task { @MainActor in
                if let adid = adid {
                    AdjustManager.shared.adid = adid
                    Purchases.shared.attribution.setAdjustID(adid)
                    print("✅ Adjust: Set ADID on RevenueCat: \(adid)")

                    NotificationCenter.default.post(
                        name: NSNotification.Name("AdjustADIDAvailable"),
                        object: nil,
                        userInfo: ["adid": adid]
                    )
                }
            }
        }
    }

    nonisolated public func adjustSessionTrackingFailed(_ sessionFailureResponseData: ADJSessionFailure?) {
        print("❌ Adjust: Session failed - \(sessionFailureResponseData?.message ?? "unknown")")
    }
}
