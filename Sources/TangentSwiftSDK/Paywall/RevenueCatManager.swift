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
            await MainActor.run {
                self.isSubscribed = !customerInfo.activeSubscriptions.isEmpty
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                print("❌ RevenueCat: Error checking subscription status - \(error)")
            }
        }
    }
    
    // MARK: - Fetch Offerings
    public func fetchOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            await MainActor.run {
                self.offerings = offerings
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                print("❌ RevenueCat: Error fetching offerings - \(error)")
            }
        }
    }
    
    // MARK: - Purchase Product
    public func purchaseProduct(_ product: StoreProduct) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let (_, customerInfo, _) = try await Purchases.shared.purchase(product: product)
            
            // Update subscription status
            isSubscribed = !customerInfo.activeSubscriptions.isEmpty
            
            // Track purchase in analytics
            MixpanelManager.shared.trackRevenue(
                amount: Double(truncating: product.price),
                productId: product.productIdentifier
            )
            
            AdjustManager.shared.trackPurchaseCompleted(
                productId: product.productIdentifier,
                amount: Double(truncating: product.price),
                source: "paywall",
                eventToken: "purchase_token" // This should be configured per app
            )
            
            print("✅ RevenueCat: Purchase successful - \(product.productIdentifier)")
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            
            // Track failed purchase
            AdjustManager.shared.trackPurchaseFailed(
                productId: product.productIdentifier,
                reason: error.localizedDescription,
                source: "paywall"
            )
            
            print("❌ RevenueCat: Purchase failed - \(error)")
            return false
        }
    }
    
    // MARK: - Restore Purchases
    public func restorePurchases() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            isSubscribed = !customerInfo.activeSubscriptions.isEmpty
            
            // Track restore in analytics
            AdjustManager.shared.trackPurchaseRestored(
                productIds: Array(customerInfo.activeSubscriptions),
                source: "restore_button"
            )
            
            print("✅ RevenueCat: Restore successful")
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ RevenueCat: Restore failed - \(error)")
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
    
    public func logout() {
        Purchases.shared.logOut { customerInfo, error in
            if let error = error {
                print("❌ RevenueCat: Error logging out - \(error)")
            } else {
                print("✅ RevenueCat: User logged out")
                Task { @MainActor in
                    if let customerInfo = customerInfo {
                        self.isSubscribed = !customerInfo.activeSubscriptions.isEmpty
                    }
                }
            }
        }
    }
}

// MARK: - PurchasesDelegate
extension RevenueCatManager: PurchasesDelegate {
    nonisolated public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.isSubscribed = !customerInfo.activeSubscriptions.isEmpty
            print("📱 RevenueCat: Customer info updated - Active subscriptions: \(customerInfo.activeSubscriptions.count)")
        }
    }
}