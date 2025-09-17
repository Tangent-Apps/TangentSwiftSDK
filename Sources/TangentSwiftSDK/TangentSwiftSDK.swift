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
        let revenueCatAPIKey: String?
        let superwallAPIKey: String?
        let firebaseConfigPath: String?
        
        public init(
            mixpanelToken: String? = nil,
            adjustAppToken: String? = nil,
            revenueCatAPIKey: String? = nil,
            superwallAPIKey: String? = nil,
            firebaseConfigPath: String? = nil
        ) {
            self.mixpanelToken = mixpanelToken
            self.adjustAppToken = adjustAppToken
            self.revenueCatAPIKey = revenueCatAPIKey
            self.superwallAPIKey = superwallAPIKey
            self.firebaseConfigPath = firebaseConfigPath
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
            MixpanelManager.shared.initialize(token: mixpanelToken)
        }
        
        if let adjustToken = config.adjustAppToken {
            AdjustManager.shared.initialize(appToken: adjustToken)
        }
        
        // Initialize Monetization
        if let revenueCatKey = config.revenueCatAPIKey {
            RevenueCatManager.shared.initialize(apiKey: revenueCatKey)
        }
        
        if let superwallKey = config.superwallAPIKey {
            SuperwallManager.shared.initialize(apiKey: superwallKey)
        }
        
        // Initialize Tracking
        // ATT will be handled automatically
    }
}

// MARK: - Public Extensions for Easy Access

@available(iOS 14.0, *)
public extension TangentSwiftSDK {
    
    /// Access to analytics services
    var analytics: AnalyticsService {
        return AnalyticsService.shared
    }
    
    /// Access to tracking services
    var tracking: TrackingService {
        return TrackingService.shared
    }
    
    /// Access to monetization services
    var monetization: MonetizationService {
        return MonetizationService.shared
    }
    
    /// Access to paywall services (RevenueCat)
    var paywall: RevenueCatManager {
        return RevenueCatManager.shared
    }
    
    /// Access to superwall services
    var superwall: SuperwallManager {
        return SuperwallManager.shared
    }
}
