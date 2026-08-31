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
        /// Mixpanel ingestion cluster, for projects in a non-US data-residency
        /// region — `https://api-eu.mixpanel.com` for EU. Nil keeps the SDK
        /// default (US). ⚠️ A mismatch here fails silently: events are accepted
        /// and posted to a cluster where the token does not exist, so they never
        /// arrive and it looks like tracking was never wired up.
        let mixpanelServerURL: String?
        let adjustAppToken: String?
        let adjustPurchaseEventToken: String?
        let adjustEnvironment: String
        let superwallAPIKey: String?
        let firebaseConfigPath: String?
        let enableATT: Bool
        let attConfiguration: ATTConfiguration?

        public init(
            mixpanelToken: String? = nil,
            // Defaulted and placed after the token so existing call sites — which
            // pass every argument by label — keep compiling untouched.
            mixpanelServerURL: String? = nil,
            adjustAppToken: String? = nil,
            adjustPurchaseEventToken: String? = nil,
            adjustEnvironment: String = "production",
            superwallAPIKey: String? = nil,
            firebaseConfigPath: String? = nil,
            enableATT: Bool = false,
            attConfiguration: ATTConfiguration? = nil
        ) {
            self.mixpanelToken = mixpanelToken
            self.mixpanelServerURL = mixpanelServerURL
            self.adjustAppToken = adjustAppToken
            self.adjustPurchaseEventToken = adjustPurchaseEventToken
            self.adjustEnvironment = adjustEnvironment
            self.superwallAPIKey = superwallAPIKey
            self.firebaseConfigPath = firebaseConfigPath
            self.enableATT = enableATT
            self.attConfiguration = attConfiguration
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
    @MainActor public func initialize(with configuration: Configuration) {
        guard !isInitialized else {
            print("⚠️ TangentSwiftSDK: SDK already initialized")
            return
        }
        
        self.configuration = configuration
        setupServices()
        isInitialized = true
        
        print("✅ TangentSwiftSDK: Initialized successfully")
    }
    
    // MARK: - Private Methods
    
    @MainActor private func setupServices() {
        guard let config = configuration else { return }

        // Initialize Analytics
        if let mixpanelToken = config.mixpanelToken {
            MixpanelManager.shared.initialize(
                token: mixpanelToken,
                serverURL: config.mixpanelServerURL
            )
        }

        if let adjustToken = config.adjustAppToken,
           let purchaseEventToken = config.adjustPurchaseEventToken {
            AdjustManager.shared.initialize(
                appToken: adjustToken,
                environment: config.adjustEnvironment,
                purchaseEventToken: purchaseEventToken
            )
        }

        // Initialize Monetization (Superwall only post-RC migration; SDK is
        // gated on a non-nil API key so passing nil cleanly disables it).
        if let superwallKey = config.superwallAPIKey {
            SuperwallManager.shared.initialize(apiKey: superwallKey)
        }

        // Initialize Tracking (Optional)
        if config.enableATT {
            ATTManager.shared.configure(with: config.attConfiguration)
        }
    }
}

// MARK: - Public Extensions for Easy Access
@MainActor
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
