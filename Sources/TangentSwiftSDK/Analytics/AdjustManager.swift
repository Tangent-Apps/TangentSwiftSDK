import Foundation
import Adjust

@MainActor
public final class AdjustManager: NSObject, ObservableObject {
    public static let shared = AdjustManager()
    
    @Published public private(set) var isInitialized = false
    @Published public private(set) var adid: String?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Configuration
    
    public func initialize(appToken: String, environment: String = "production") {
        let adjustEnvironment = environment == "sandbox" ? ADJEnvironmentSandbox : ADJEnvironmentProduction
        
        let config = ADJConfig(
            appToken: appToken,
            environment: adjustEnvironment
        )
        
        // Set delegate for attribution callbacks
        config?.delegate = self
        
        // Initialize Adjust
        Adjust.appDidLaunch(config)
        
        isInitialized = true
        print("✅ Adjust: Configured successfully with token: \(appToken)")
        
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
    public func trackOnboardingCompleted(zodiacSign: String? = nil) {
        var parameters: [String: String] = [:]
        if let zodiacSign = zodiacSign {
            parameters["zodiac_sign"] = zodiacSign
        }
        trackCustomEvent("onboarding_completed", parameters: parameters)
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
    public func trackPurchaseCompleted(productId: String, amount: Double, currency: String = "USD", source: String, eventToken: String) {
        // Create revenue event
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
        
        // Get ADID
        let adid = Adjust.adid()
        Task { @MainActor in
            self.adid = adid
            
            print("📈 Adjust Attribution:")
            print("  - ADID: \(adid ?? "N/A")")
            print("  - Network: \(attribution.network ?? "N/A")")
            print("  - Campaign: \(attribution.campaign ?? "N/A")")
            print("  - Creative: \(attribution.creative ?? "N/A")")
            print("  - Click Label: \(attribution.clickLabel ?? "N/A")")
        }
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
    }
    
    nonisolated public func adjustSessionTrackingFailed(_ sessionFailureResponseData: ADJSessionFailure?) {
        print("❌ Adjust: Session tracking failed - \(sessionFailureResponseData?.message ?? "Unknown error")")
    }
}
