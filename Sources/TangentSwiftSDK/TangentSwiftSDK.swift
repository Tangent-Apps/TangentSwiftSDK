import Foundation
import UIKit

/// TangentSwiftSDK - A comprehensive SDK for iOS app analytics, tracking, and monetization
@available(iOS 14.0, *)
public final class TangentSwiftSDK {
    
    // MARK: - Singleton
    public static let shared = TangentSwiftSDK()
    
    // MARK: - Configuration
    public struct Configuration {
        let mixpanelToken: String?
        let adjustAppToken: String?
        let adjustPurchaseEventToken: String?
        /// Analytics event name → Adjust event token, e.g. `["trial_started": "abc123"]`.
        /// Adjust only accepts events it has a token for, so `analytics.trackCustomEvent`
        /// forwards a name to Adjust only if it appears here. Empty = Mixpanel only.
        let adjustEventTokens: [String: String]
        let superwallAPIKey: String?
        let firebaseConfigPath: String?
        let enableATT: Bool
        let attConfiguration: ATTConfiguration?
        /// Seconds Adjust waits for the ATT answer before sending its first
        /// session / minting the ADID. Default 2 so purchase attribution never
        /// blocks on a post-paywall ATT prompt. Raise only if you show ATT
        /// before the paywall AND need IDFA in the first session.
        let adjustAttConsentWaitingInterval: UInt

        public init(
            mixpanelToken: String? = nil,
            adjustAppToken: String? = nil,
            adjustPurchaseEventToken: String? = nil,
            adjustEventTokens: [String: String] = [:],
            superwallAPIKey: String? = nil,
            firebaseConfigPath: String? = nil,
            enableATT: Bool = false,
            attConfiguration: ATTConfiguration? = nil,
            adjustAttConsentWaitingInterval: UInt = 2
        ) {
            self.mixpanelToken = mixpanelToken
            self.adjustAppToken = adjustAppToken
            self.adjustPurchaseEventToken = adjustPurchaseEventToken
            self.adjustEventTokens = adjustEventTokens
            self.superwallAPIKey = superwallAPIKey
            self.firebaseConfigPath = firebaseConfigPath
            self.enableATT = enableATT
            self.attConfiguration = attConfiguration
            self.adjustAttConsentWaitingInterval = adjustAttConsentWaitingInterval
        }
    }
    
    // MARK: - ATT Configuration
    public struct ATTConfiguration {
        let title: String
        let description: String
        let benefits: [ATTBenefit]
        let allowButtonText: String
        let denyButtonText: String
        
        public init(
            title: String = "Help Us Personalize Your Experience",
            description: String = "We'd like your permission to track your activity across apps and websites to provide you with a personalized experience.",
            benefits: [ATTBenefit] = [
                ATTBenefit(icon: "sparkles", text: "Personalized content"),
                ATTBenefit(icon: "chart.line.uptrend.xyaxis", text: "Better insights"),
                ATTBenefit(icon: "heart.fill", text: "Improved experience")
            ],
            allowButtonText: String = "Allow Tracking",
            denyButtonText: String = "Ask App Not to Track"
        ) {
            self.title = title
            self.description = description
            self.benefits = benefits
            self.allowButtonText = allowButtonText
            self.denyButtonText = denyButtonText
        }
    }
    
    public struct ATTBenefit {
        let icon: String
        let text: String
        
        public init(icon: String, text: String) {
            self.icon = icon
            self.text = text
        }
    }
    
    // MARK: - Private Properties
    private var isInitialized = false
    private var configuration: Configuration?
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Public Methods
    
    /// Initialize the SDK with configuration
    /// - Parameter configuration: SDK configuration with API keys
    public func initialize(with configuration: Configuration) {
        guard !isInitialized else { return }

        self.configuration = configuration
        setupServices()
        isInitialized = true

        print("✅ TangentSwiftSDK: Initialized")
    }
    
    // MARK: - Private Methods
    
    private func setupServices() {
        guard let config = configuration else { return }
        // Initialize Paywall
        if let superwallKey = config.superwallAPIKey {
            SuperwallManager.shared.initialize(apiKey: superwallKey)
        }

        // Initialize Analytics
        if let mixpanelToken = config.mixpanelToken {
            MixpanelManager.shared.initialize(token: mixpanelToken)
        }

        if let adjustToken = config.adjustAppToken,
           let purchaseEventToken = config.adjustPurchaseEventToken {
            AdjustManager.shared.initialize(
                appToken: adjustToken,
                purchaseEventToken: purchaseEventToken,
                eventTokens: config.adjustEventTokens,
                attConsentWaitingInterval: config.adjustAttConsentWaitingInterval,
                didGetADID: { adid in
                    SuperwallManager.shared.registerAdjustADID(adid: adid)
                }
            )
        }

        // Initialize Tracking (Optional)
        if config.enableATT {
            ATTManager.shared.configure(with: config.attConfiguration)
        }
    }
}

// MARK: - Public Extensions for Easy Access
public extension TangentSwiftSDK {
    
    /// Access to analytics services
    var analytics: AnalyticsService {
        return AnalyticsService.shared
    }
    
    /// Access to tracking services
    var tracking: TrackingService {
        return TrackingService.shared
    }
    
    /// Access to superwall services
    var superwall: SuperwallManager {
        return SuperwallManager.shared
    }
}
