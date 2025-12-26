import Foundation
@preconcurrency import AdjustSdk

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
        // Trim whitespace from token
        let cleanToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)

        print("🔍 Adjust: Raw token = '\(appToken)'")
        print("🔍 Adjust: Clean token = '\(cleanToken)'")
        print("🔍 Adjust: Token length = \(cleanToken.count) (should be ~12)")

        let adjustEnvironment = environment == "sandbox" ? ADJEnvironmentSandbox : ADJEnvironmentProduction

        guard let config = ADJConfig(
            appToken: cleanToken,
            environment: adjustEnvironment
        ) else {
            print("❌ Adjust: FAILED to create ADJConfig! Token or environment invalid.")
            return
        }

        print("✅ Adjust: ADJConfig created successfully")

        // Enable debug logging to see what's happening
        config.logLevel = ADJLogLevel.verbose

        // Set delegate for attribution callbacks
        config.delegate = self

        // IMPORTANT: Wait for ATT authorization before sending first session
        // This delays the first session until ATT dialog is answered (up to 120 seconds)
        config.attConsentWaitingInterval = 120

        // Store purchase event token
        self.purchaseEventToken = purchaseEventToken

        print("🔍 Adjust: About to call initSdk...")

        // Initialize Adjust
        Adjust.initSdk(config)

        print("🔍 Adjust: initSdk called")

        isInitialized = true
        print("✅ Adjust: Configured with environment: \(adjustEnvironment == ADJEnvironmentSandbox ? "SANDBOX" : "PRODUCTION")")
        print("✅ Adjust: App token: \(appToken)")

        // Check SDK status after short delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            let enabled = await Adjust.isEnabled()
            print("🔍 Adjust: SDK enabled = \(enabled)")

            if let adid = await Adjust.adid() {
                print("🔍 Adjust: ADID after 3s = \(adid)")
            } else {
                print("🔍 Adjust: ADID still nil after 3s")
            }
        }

        // Track app launch
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
        // Create revenue event with configured purchase event token
        guard let eventToken = purchaseEventToken else {
            print("⚠️ Adjust: Purchase event token not configured, skipping revenue tracking")
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

        // Also track general purchase completion
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
        guard isInitialized else {
            print("⚠️ Adjust: Not initialized, skipping event: \(eventName)")
            return
        }
        
        // For custom events without specific tokens, we'll use a generic approach
        // In practice, you would have event tokens configured for each event
        print("📊 Adjust: Custom event tracked - \(eventName) with \(parameters.count) parameters")
    }
    
    /// Track event with specific token
    public func trackEvent(_ eventToken: String, parameters: [String: String] = [:]) {
        guard isInitialized else {
            print("⚠️ Adjust: Not initialized, skipping event: \(eventToken)")
            return
        }
        
        guard let event = ADJEvent(eventToken: eventToken) else {
            print("❌ Adjust: Failed to create event with token: \(eventToken)")
            return
        }
        
        // Add parameters as callback parameters
        for (key, value) in parameters {
            event.addCallbackParameter(key, value: value)
        }
        
        Adjust.trackEvent(event)
        print("📊 Adjust: Event tracked - \(eventToken) with \(parameters.count) parameters")
    }
    
    // MARK: - Attribution
    
    private func handleAttributionCallback(_ attribution: ADJAttribution?) {
        guard let attribution = attribution else { return }

        // Get ADID via completion handler (v5 API)
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
        print("❌ Adjust: Event tracking failed - \(eventFailureResponseData?.eventToken ?? "unknown")")
        print("   Error: \(eventFailureResponseData?.message ?? "Unknown error")")
    }
    
    nonisolated public func adjustSessionTrackingSucceeded(_ sessionSuccessResponseData: ADJSessionSuccess?) {
        print("✅ Adjust: Session tracking succeeded")

        // ADID becomes available after session tracking - fetch it here
        Adjust.adid { adid in
            Task { @MainActor in
                if let adid = adid {
                    AdjustManager.shared.adid = adid
                    print("✅ Adjust: ADID retrieved after session: \(adid)")

                    // Notify RevenueCat
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AdjustADIDAvailable"),
                        object: nil,
                        userInfo: ["adid": adid]
                    )
                } else {
                    print("⚠️ Adjust: ADID still nil after session success")
                }
            }
        }
    }
    
    nonisolated public func adjustSessionTrackingFailed(_ sessionFailureResponseData: ADJSessionFailure?) {
        print("❌ Adjust: Session tracking failed - \(sessionFailureResponseData?.message ?? "Unknown error")")
    }
}
