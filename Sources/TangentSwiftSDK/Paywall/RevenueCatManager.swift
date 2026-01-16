import Foundation
import RevenueCat
import StoreKit

// MARK: - RevenueCat Manager
public final class RevenueCatManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    public static let shared = RevenueCatManager()
    
    // MARK: - Published Properties
    @Published public var isSubscribed: Bool = false
    @Published public var isTrialUser: Bool = false
    @Published public var isPaidUser: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var offerings: Offerings?
    @Published public var errorMessage: String?
    
    // MARK: - Initialization
    private override init() {}
    
    // MARK: - Configuration
    public func initialize(apiKey: String) {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)
        
        // Set delegate for real-time updates
        Purchases.shared.delegate = self
        
        // Check initial subscription status
        Task {
            await checkSubscriptionStatus()
            await fetchOfferings()
        }
        
        print("✅ RevenueCat: Initialized")
    }
    
    // MARK: - Check Subscription Status
    public func checkSubscriptionStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            self.isSubscribed = customerInfo.entitlements["Pro"]?.isActive == true ||
                               !customerInfo.activeSubscriptions.isEmpty
            self.isTrialUser = checkIsTrialUser(from: customerInfo)
            self.isPaidUser = checkIsPaidUser(from: customerInfo)
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ RevenueCat: Error checking subscription status - \(error)")
        }
    }
    
    // MARK: - Fetch Offerings
    public func fetchOfferings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            self.offerings = offerings

        } catch {
            print("❌ RevenueCat: Error fetching offerings: \(error)")
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Debug: Fetch Products
    /// Fetches and prints products by IDs for debugging integration issues
    /// - Parameter productIds: Array of product identifiers to fetch from App Store Connect
    public func fetchProducts(productIds: [String]) async {
        isLoading = true
        defer { isLoading = false }

        let products: [StoreProduct] = await Purchases.shared.products(productIds)

        if products.isEmpty {
            self.errorMessage = "No products found for the given IDs"
        }
    }
    
    // MARK: - Purchase Product
    public func purchase(package: Package) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        // Track purchase attempt
        MixpanelManager.shared.track(event: .purchaseStarted, properties: [
            "product_id": package.storeProduct.productIdentifier,
            "plan_type": package.packageType.debugDescription
        ])
        
        do {
            let result = try await Purchases.shared.purchase(package: package)
            
            // Check if purchase was successful (not cancelled)
            if !result.userCancelled {
                // Update subscription status
                self.isSubscribed = result.customerInfo.entitlements["Pro"]?.isActive == true ||
                                   !result.customerInfo.activeSubscriptions.isEmpty
                self.isTrialUser = checkIsTrialUser(from: result.customerInfo)
                self.isPaidUser = checkIsPaidUser(from: result.customerInfo)

                // Track successful purchase
                MixpanelManager.shared.track(event: .purchaseCompleted, properties: [
                    "product_id": package.storeProduct.productIdentifier,
                    "plan_type": package.packageType.debugDescription,
                    "is_subscribed": self.isSubscribed,
                    "is_trial": self.isTrialUser,
                    "is_paid": self.isPaidUser,
                    "subscription_type": getSubscriptionType(from: result.customerInfo)
                ])
                
                // Track revenue
                let price = package.storeProduct.price as NSDecimalNumber
                MixpanelManager.shared.trackRevenue(
                    amount: price.doubleValue,
                    productId: package.storeProduct.productIdentifier
                )
                
                
                print("✅ RevenueCat: Purchase successful")
                isLoading = false
                return true
            } else {
                // Track purchase cancellation
                MixpanelManager.shared.track(event: .purchaseCancelled, properties: [
                    "product_id": package.storeProduct.productIdentifier
                ])
            }
            
        } catch {
            print("❌ RevenueCat: Purchase error: \(error)")
            self.errorMessage = error.localizedDescription
            
            // Track purchase error
            MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                "product_id": package.storeProduct.productIdentifier,
                "error": error.localizedDescription
            ])
        }
        
        isLoading = false
        return false
    }
    
    // MARK: - Purchase by Product ID (Convenience Method)
    public func purchase(productId: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let products: [StoreProduct] = await Purchases.shared.products([productId])
            guard let product = products.first else {
                errorMessage = "Product not found"
                print("❌ RevenueCat: Product not found: \(productId)")
                isLoading = false
                return false
            }
            
            let result = try await Purchases.shared.purchase(product: product)
            
            // Check if purchase was successful (not cancelled)
            if !result.userCancelled {
                // Update subscription status
                self.isSubscribed = result.customerInfo.entitlements["Pro"]?.isActive == true ||
                                   !result.customerInfo.activeSubscriptions.isEmpty
                self.isTrialUser = checkIsTrialUser(from: result.customerInfo)
                self.isPaidUser = checkIsPaidUser(from: result.customerInfo)

                print("✅ RevenueCat: Purchase successful for product: \(productId)")
                isLoading = false
                return true
            }
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
        return false
    }
    
    // MARK: - Restore Purchases
    public func restorePurchases() async -> Bool {
        isLoading = true
        errorMessage = nil
        
        // Track restore started
        MixpanelManager.shared.track(event: .restorePurchaseStarted)
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            
            // Update subscription status
            self.isSubscribed = customerInfo.entitlements["Pro"]?.isActive == true ||
                               !customerInfo.activeSubscriptions.isEmpty
            self.isTrialUser = checkIsTrialUser(from: customerInfo)
            self.isPaidUser = checkIsPaidUser(from: customerInfo)

            // Track successful restoration
            MixpanelManager.shared.track(event: .restorePurchaseCompleted, properties: [
                "has_active_subscription": self.isSubscribed,
                "is_trial": self.isTrialUser,
                "is_paid": self.isPaidUser,
                "subscription_type": getSubscriptionType(from: customerInfo)
            ])

            // If user has active subscriptions, track subscription activation
            if self.isSubscribed {
                MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
                    "trigger": "restore_purchase",
                    "is_subscribed": self.isSubscribed,
                    "is_trial": self.isTrialUser,
                    "is_paid": self.isPaidUser,
                    "subscription_type": getSubscriptionType(from: customerInfo)
                ])
            }
            
            isLoading = false
            return isSubscribed

        } catch {
            self.errorMessage = error.localizedDescription
            
            // Track restoration failure
            MixpanelManager.shared.track(event: .restorePurchaseFailed, properties: [
                "error": error.localizedDescription
            ])
            
            isLoading = false
            return false
        }
    }
    
    // MARK: - User Management
    public func identify(userId: String) {
        Purchases.shared.logIn(userId) { customerInfo, created, error in
            if error == nil {
                Task { @MainActor in
                    if let customerInfo = customerInfo {
                        self.isSubscribed = !customerInfo.activeSubscriptions.isEmpty
                    }
                }
            }
        }
    }
    
    
    // MARK: - Helper Methods
    
    /// Get localized price string for a product
    public func getPriceString(for productId: String) -> String? {
        // Try to get from offerings first (faster if available)
        if let offerings = offerings,
           let offering = offerings.current,
           let package = offering.availablePackages.first(where: {
               $0.storeProduct.productIdentifier == productId
           }) {
            return package.localizedPriceString
        }
        
        // If offerings not available, fetch product directly (this will be async in real usage)
        // For now, return nil and let UI use fallback pricing
        return nil
    }
    
    /// Get localized price string for a product (async version)
    public func getPriceStringAsync(for productId: String) async -> String? {
        let products: [StoreProduct] = await Purchases.shared.products([productId])
        guard let product = products.first else {
            return nil
        }
        return product.localizedPriceString
    }
    
    /// Get product directly by ID
    public func getProduct(for productId: String) async -> StoreProduct? {
        let products: [StoreProduct] = await Purchases.shared.products([productId])
        return products.first
    }
    
    /// Check if user has specific entitlement
    public func hasEntitlement(_ entitlementId: String) async -> Bool {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            return customerInfo.entitlements[entitlementId]?.isActive == true
        } catch {
            return false
        }
    }

    // MARK: - Subscription Status Helpers

    /// Check if user is currently on a free trial
    private func checkIsTrialUser(from customerInfo: CustomerInfo) -> Bool {
        if let proEntitlement = customerInfo.entitlements["Pro"],
           proEntitlement.isActive,
           proEntitlement.periodType == .trial {
            return true
        }
        return false
    }

    /// Check if user is a paid subscriber (not trial, not intro offer)
    private func checkIsPaidUser(from customerInfo: CustomerInfo) -> Bool {
        if let proEntitlement = customerInfo.entitlements["Pro"],
           proEntitlement.isActive,
           proEntitlement.periodType == .normal {
            return true
        }
        return false
    }

    /// Get subscription type as readable string
    private func getSubscriptionType(from customerInfo: CustomerInfo) -> String {
        guard let proEntitlement = customerInfo.entitlements["Pro"], proEntitlement.isActive else {
            return "none"
        }
        switch proEntitlement.periodType {
        case .trial:
            return "trial"
        case .intro:
            return "intro_offer"
        case .normal:
            return "full paid"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - PurchasesDelegate
extension RevenueCatManager: PurchasesDelegate {
    nonisolated public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            let wasSubscribed = self.isSubscribed
            let wasTrialUser = self.isTrialUser

            // Update subscription status when customer info changes
            self.isSubscribed = customerInfo.entitlements["Pro"]?.isActive == true ||
                               !customerInfo.activeSubscriptions.isEmpty
            self.isTrialUser = checkIsTrialUser(from: customerInfo)
            self.isPaidUser = checkIsPaidUser(from: customerInfo)

            let subscriptionType = getSubscriptionType(from: customerInfo)

            // Track subscription status changes
            if !wasSubscribed && self.isSubscribed {
                // User just became subscribed
                MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
                    "trigger": "status_change",
                    "is_subscribed": self.isSubscribed,
                    "is_trial": self.isTrialUser,
                    "is_paid": self.isPaidUser,
                    "subscription_type": subscriptionType
                ])
            } else if wasSubscribed && !self.isSubscribed {
                // User subscription expired or was cancelled
                MixpanelManager.shared.track(event: .subscriptionCancelled, properties: [
                    "was_trial": wasTrialUser
                ])
            } else if wasTrialUser && !self.isTrialUser && self.isSubscribed {
                // User converted from trial to paid
                MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
                    "trigger": "trial_converted",
                    "is_subscribed": self.isSubscribed,
                    "is_trial": false,
                    "is_paid": true,
                    "subscription_type": subscriptionType
                ])
            }

            // Track subscription status when app opens
            MixpanelManager.shared.track(event: .subscriptionStatus, properties: [
                "is_subscribed": self.isSubscribed, // has trial and paid users
                "is_trial": self.isTrialUser, // trial only
                "is_paid": self.isPaidUser, // full sub paid only
                "subscription_type": subscriptionType // trial or full paid or offer
            ])

            // Notify Superwall of subscription status change
//            SuperwallManager.shared.updateSubscriptionStatus()
        }
    }
}
