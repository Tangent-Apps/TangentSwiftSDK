import Foundation
import RevenueCat
import StoreKit

// MARK: - Monetization Service
@MainActor
public final class MonetizationService: ObservableObject {
    public static let shared = MonetizationService()
    
    private init() {}
    
    // MARK: - Subscription Status
    
    /// Check if user is subscribed
    public var isSubscribed: Bool {
        return RevenueCatManager.shared.isSubscribed
    }
    
    /// Check if operations are loading
    public var isLoading: Bool {
        return RevenueCatManager.shared.isLoading
    }
    
    /// Get current offerings
    public var offerings: Offerings? {
        return RevenueCatManager.shared.offerings
    }
    
    /// Get error message if any
    public var errorMessage: String? {
        return RevenueCatManager.shared.errorMessage
    }
    
    // MARK: - Subscription Management
    
    /// Check subscription status
    public func checkSubscriptionStatus() async {
        await RevenueCatManager.shared.checkSubscriptionStatus()
    }
    
    /// Fetch offerings
    public func fetchOfferings() async {
        await RevenueCatManager.shared.fetchOfferings()
    }
    
    /// Purchase a product
    public func purchaseProduct(_ product: Package) async -> Bool {
        return await RevenueCatManager.shared.purchase(package: product)
    }
    
    /// Restore purchases
    public func restorePurchases() async -> Bool {
        return await RevenueCatManager.shared.restorePurchases()
    }
    
    // MARK: - User Management
    
    /// Identify user for RevenueCat
    public func identify(userId: String) {
        RevenueCatManager.shared.identify(userId: userId)
    }
    
}
