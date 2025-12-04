import Foundation
import RevenueCat
import StoreKit

// MARK: - RevenueCat Manager
@MainActor
public final class RevenueCatManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    public static let shared = RevenueCatManager()
    
    // MARK: - Published Properties
    @Published public var isSubscribed: Bool = false
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
        
        print("✅ RevenueCat: Configured successfully")
    }
    
    // MARK: - Check Subscription Status
    public func checkSubscriptionStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            self.isSubscribed = customerInfo.entitlements["Pro"]?.isActive == true ||
                               !customerInfo.activeSubscriptions.isEmpty
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
        print("🔍 RevenueCat: Fetching products...")
        print("   Product IDs: \(productIds)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        isLoading = true
        defer { isLoading = false }

        let products: [StoreProduct] = await Purchases.shared.products(productIds)

        if products.isEmpty {
            print("❌ RevenueCat: No products found")
            print("   Possible reasons:")
            print("   - Product IDs don't match App Store Connect")
            print("   - Products not approved/available in your region")
            print("   - Agreements not signed in App Store Connect")
            self.errorMessage = "No products found for the given IDs"
        } else {
            print("✅ RevenueCat: Found \(products.count) product(s)")
            print("")

            for product in products {
                print("   📱 Product: \(product.productIdentifier)")
                print("      Title: \(product.localizedTitle)")
                print("      Description: \(product.localizedDescription)")
                print("      Price: \(product.localizedPriceString)")
                print("      Price (Decimal): \(product.price)")
                print("      Currency: \(product.currencyCode ?? "N/A")")
                print("      Product Type: \(product.productType)")
                if let subscriptionPeriod = product.subscriptionPeriod {
                    print("      Subscription Period: \(subscriptionPeriod)")
                }
                if let introPrice = product.introductoryDiscount {
                    print("      Intro Price: \(introPrice.localizedPriceString)")
                }
                print("")
            }
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    // MARK: - Purchase Product
    public func purchase(package: Package) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        // Track purchase attempt
        MixpanelManager.shared.track(event: .purchaseStarted, properties: [
            "source": "revenuecat_manager",
            "product_id": package.storeProduct.productIdentifier,
            "package_type": package.packageType.debugDescription
        ])
        
        do {
            let result = try await Purchases.shared.purchase(package: package)
            
            // Check if purchase was successful (not cancelled)
            if !result.userCancelled {
                // Update subscription status
                self.isSubscribed = result.customerInfo.entitlements["Pro"]?.isActive == true ||
                                   !result.customerInfo.activeSubscriptions.isEmpty
                
                // Track successful purchase
                MixpanelManager.shared.track(event: .purchaseCompleted, properties: [
                    "source": "revenuecat_manager",
                    "product_id": package.storeProduct.productIdentifier,
                    "package_type": package.packageType.debugDescription
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
                MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                    "source": "revenuecat_manager",
                    "product_id": package.storeProduct.productIdentifier,
                    "reason": "user_cancelled"
                ])
            }
            
        } catch {
            print("❌ RevenueCat: Purchase error: \(error)")
            self.errorMessage = error.localizedDescription
            
            // Track purchase error
            MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                "source": "revenuecat_manager",
                "product_id": package.storeProduct.productIdentifier,
                "error_description": error.localizedDescription
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
                
                print("✅ RevenueCat: Purchase successful for product: \(productId)")
                isLoading = false
                return true
            }
            
        } catch {
            print("❌ RevenueCat: Purchase error for \(productId): \(error)")
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
        return false
    }
    
    // MARK: - Restore Purchases
    public func restorePurchases() async -> Bool {
        isLoading = true
        errorMessage = nil
        
        // Track restore attempt
        MixpanelManager.shared.track(event: .purchaseRestored, properties: [
            "source": "revenuecat_manager",
            "action": "restore_attempt"
        ])
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            
            // Update subscription status
            self.isSubscribed = customerInfo.entitlements["Pro"]?.isActive == true ||
                               !customerInfo.activeSubscriptions.isEmpty
            
            // Track successful restoration
            MixpanelManager.shared.track(event: .purchaseRestored, properties: [
                "source": "revenuecat_manager",
                "success": true,
                "active_subscriptions": Array(customerInfo.activeSubscriptions),
                "active_entitlements": Array(customerInfo.entitlements.active.keys)
            ])
            
            // If user has active subscriptions, track subscription activation
            if self.isSubscribed {
                MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
                    "source": "restore_purchases",
                    "active_subscriptions": Array(customerInfo.activeSubscriptions)
                ])
            }
            
            print("✅ RevenueCat: Restore successful")
            isLoading = false
            return isSubscribed
            
        } catch {
            print("❌ RevenueCat: Restore error: \(error)")
            self.errorMessage = error.localizedDescription
            
            // Track restoration failure
            MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                "source": "revenuecat_manager",
                "action": "restore_purchases",
                "error_description": error.localizedDescription
            ])
            
            isLoading = false
            return false
        }
    }
    
    // MARK: - User Management
    public func identify(userId: String) {
        Purchases.shared.logIn(userId) { customerInfo, created, error in
            if let error = error {
                print("❌ RevenueCat: Error identifying user - \(error)")
            } else {
                print("✅ RevenueCat: User identified - \(userId)")
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
}

// MARK: - PurchasesDelegate
extension RevenueCatManager: PurchasesDelegate {
    nonisolated public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            let wasSubscribed = self.isSubscribed
            
            // Update subscription status when customer info changes
            self.isSubscribed = customerInfo.entitlements["Pro"]?.isActive == true ||
                               !customerInfo.activeSubscriptions.isEmpty
            
            // Track subscription status changes
            if !wasSubscribed && self.isSubscribed {
                // User just became subscribed
                MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
                    "source": "revenuecat_delegate",
                    "active_subscriptions": Array(customerInfo.activeSubscriptions),
                    "active_entitlements": Array(customerInfo.entitlements.active.keys),
                    "trigger": "customer_info_updated"
                ])
            } else if wasSubscribed && !self.isSubscribed {
                // User just lost subscription
                MixpanelManager.shared.track(event: .subscriptionCancelled, properties: [
                    "source": "revenuecat_delegate",
                    "trigger": "customer_info_updated"
                ])
            }
            
            // Track general customer info updates
            MixpanelManager.shared.track(event: .featureUsed, properties: [
                "feature": "customer_info_updated",
                "is_subscribed": self.isSubscribed,
                "active_subscriptions_count": customerInfo.activeSubscriptions.count,
                "active_entitlements_count": customerInfo.entitlements.active.count
            ])
            
            // Notify Superwall of subscription status change
//            SuperwallManager.shared.updateSubscriptionStatus()
        }
    }
}
