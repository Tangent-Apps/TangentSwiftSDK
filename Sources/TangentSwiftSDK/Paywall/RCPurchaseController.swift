//
//  RCPurchaseController.swift
//  TangentSwiftSDK
//
//  RevenueCat Purchase Controller for Superwall integration
//

import Foundation
import RevenueCat
import SuperwallKit
import StoreKit

public enum PurchasingError: LocalizedError {
  case sk2ProductNotFound

  public var errorDescription: String? {
    switch self {
    case .sk2ProductNotFound:
      return "Superwall didn't pass a StoreKit 2 product to purchase. Are you sure you're not "
        + "configuring Superwall with a SuperwallOption to use StoreKit 1?"
    }
  }
}

public final class RCPurchaseController: PurchaseController {
  // MARK: Sync Subscription Status
  /// Makes sure that Superwall knows the customer's entitlements by
  /// changing `Superwall.shared.entitlements`
    public func syncSubscriptionStatus() {
        Task {
            for await customerInfo in Purchases.shared.customerInfoStream {
                // Gets called whenever new CustomerInfo is available
                let superwallEntitlements = customerInfo.entitlements.activeInCurrentEnvironment.keys.map {
                    Entitlement(id: $0)
                }
                await MainActor.run { [superwallEntitlements] in
                    Superwall.shared.subscriptionStatus = .active(Set(superwallEntitlements))
                }
            }
        }
    }

  // MARK: Handle Purchases
  /// Makes a purchase with RevenueCat and returns its result. This gets called when
  /// someone tries to purchase a product on one of your paywalls.
  public func purchase(product: SuperwallKit.StoreProduct) async -> PurchaseResult {
    do {
      if #available(iOS 15.0, *) {
        guard let sk2Product = product.sk2Product else {
          throw PurchasingError.sk2ProductNotFound
        }
        let storeProduct = RevenueCat.StoreProduct(sk2Product: sk2Product)
        let revenueCatResult = try await Purchases.shared.purchase(product: storeProduct)
        
        if revenueCatResult.userCancelled {
          // Track purchase cancellation using TangentSwiftSDK
          await MainActor.run {
            TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
              "source": "revenuecat_purchase_controller",
              "product_id": storeProduct.productIdentifier,
              "reason": "user_cancelled"
            ])
          }
          return .cancelled
        } else {
          // Track successful purchase using TangentSwiftSDK
          await MainActor.run {
            TangentSwiftSDK.shared.analytics.track(event: .purchaseCompleted, properties: [
              "source": "revenuecat_purchase_controller",
              "product_id": storeProduct.productIdentifier
            ])
            
            // Track revenue
            let price = NSDecimalNumber(decimal: storeProduct.price).doubleValue
            TangentSwiftSDK.shared.analytics.trackRevenue(
              amount: price,
              productId: storeProduct.productIdentifier
            )
            
            // Track subscription activation
            TangentSwiftSDK.shared.analytics.track(event: .subscriptionActivated, properties: [
              "source": "revenuecat_purchase_controller",
              "product_id": storeProduct.productIdentifier
            ])
          }
          return .purchased
        }
      } else {
        // For iOS 14, return failed with unsupported error
        await MainActor.run {
          TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
            "source": "revenuecat_purchase_controller",
            "product_id": product.productIdentifier,
            "reason": "ios_version_unsupported"
          ])
        }
        return .failed(PurchasingError.sk2ProductNotFound)
      }
    } catch let error as ErrorCode {
      // Track purchase errors using TangentSwiftSDK
      await MainActor.run {
        TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
          "source": "revenuecat_purchase_controller",
          "product_id": product.productIdentifier,
          "error_code": error.errorCode,
          "error_description": error.localizedDescription
        ])
      }
      
      if error == .paymentPendingError {
        return .pending
      } else {
        return .failed(error)
      }
    } catch {
      // Track general purchase errors using TangentSwiftSDK
      await MainActor.run {
        TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
          "source": "revenuecat_purchase_controller",
          "product_id": product.productIdentifier,
          "error_description": error.localizedDescription
        ])
      }
      return .failed(error)
    }
  }

  // MARK: Handle Restores
  /// Makes a restore with RevenueCat and returns `.restored`, unless an error is thrown.
  /// This gets called when someone tries to restore purchases on one of your paywalls.
  public func restorePurchases() async -> RestorationResult {
    do {
      let customerInfo = try await Purchases.shared.restorePurchases()
      
      // Track successful restoration using TangentSwiftSDK
      await MainActor.run {
        TangentSwiftSDK.shared.analytics.track(event: .purchaseRestored, properties: [
          "source": "revenuecat_purchase_controller",
          "active_subscriptions": Array(customerInfo.activeSubscriptions),
          "active_entitlements": Array(customerInfo.entitlements.active.keys)
        ])
        
        // If user has active subscriptions, track subscription activation
        if !customerInfo.activeSubscriptions.isEmpty {
          TangentSwiftSDK.shared.analytics.track(event: .subscriptionActivated, properties: [
            "source": "restore_purchases",
            "active_subscriptions": Array(customerInfo.activeSubscriptions)
          ])
        }
      }
      
      return .restored
    } catch let error {
      // Track restoration failure using TangentSwiftSDK
      await MainActor.run {
        TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
          "source": "revenuecat_purchase_controller",
          "action": "restore_purchases",
          "error_description": error.localizedDescription
        ])
      }
      return .failed(error)
    }
  }
}
