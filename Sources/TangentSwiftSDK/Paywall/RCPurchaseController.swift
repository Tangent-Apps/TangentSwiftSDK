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

enum PurchasingError: LocalizedError {
  case sk2ProductNotFound

  var errorDescription: String? {
    switch self {
    case .sk2ProductNotFound:
      return "Superwall didn't pass a StoreKit 2 product to purchase. Are you sure you're not "
        + "configuring Superwall with a SuperwallOption to use StoreKit 1?"
    }
  }
}

final class RCPurchaseController: PurchaseController {
  // MARK: Sync Subscription Status
  /// Makes sure that Superwall knows the customer's entitlements by
  /// changing `Superwall.shared.entitlements`
    func syncSubscriptionStatus() {
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
  func purchase(product: SuperwallKit.StoreProduct) async -> PurchaseResult {
    do {
      guard let sk2Product = product.sk2Product else {
        throw PurchasingError.sk2ProductNotFound
      }
      let storeProduct = RevenueCat.StoreProduct(sk2Product: sk2Product)
      let revenueCatResult = try await Purchases.shared.purchase(product: storeProduct)
      
      if revenueCatResult.userCancelled {
        // Track purchase cancellation
        await MainActor.run {
          MixpanelManager.shared.track(event: .purchaseFailed, properties: [
            "source": "revenuecat_purchase_controller",
            "product_id": storeProduct.productIdentifier,
            "reason": "user_cancelled"
          ])
        }
        return .cancelled
      } else {
        // Track successful purchase
        await MainActor.run {
          MixpanelManager.shared.track(event: .purchaseCompleted, properties: [
            "source": "revenuecat_purchase_controller",
            "product_id": storeProduct.productIdentifier
          ])
          
          // Track revenue with Mixpanel
          if let price = Double(storeProduct.price.description) {
            MixpanelManager.shared.trackRevenue(
              amount: price,
              productId: storeProduct.productIdentifier
            )
            
            // Track revenue with Adjust
            AdjustManager.shared.trackPurchaseCompleted(
              productId: storeProduct.productIdentifier,
              amount: price,
              currency: storeProduct.currencyCode ?? "USD",
              source: "revenuecat_purchase_controller", eventToken: "30tcgt"
            )
          }
          
          // Track subscription activation
          MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
            "source": "revenuecat_purchase_controller",
            "product_id": storeProduct.productIdentifier
          ])
        }
        return .purchased
      }
    } catch let error as ErrorCode {
      // Track purchase errors
      await MainActor.run {
        MixpanelManager.shared.track(event: .purchaseFailed, properties: [
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
      // Track general purchase errors
      await MainActor.run {
        MixpanelManager.shared.track(event: .purchaseFailed, properties: [
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
  func restorePurchases() async -> RestorationResult {
    do {
      let customerInfo = try await Purchases.shared.restorePurchases()
      
      // Track successful restoration
      await MainActor.run {
        AdjustManager.shared.trackEvent("93azwp")
        MixpanelManager.shared.track(event: .purchaseRestored, properties: [
          "source": "revenuecat_purchase_controller",
          "active_subscriptions": Array(customerInfo.activeSubscriptions),
          "active_entitlements": Array(customerInfo.entitlements.active.keys)
        ])
        
        // If user has active subscriptions, track subscription activation
        if !customerInfo.activeSubscriptions.isEmpty {
          MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
            "source": "restore_purchases",
            "active_subscriptions": Array(customerInfo.activeSubscriptions)
          ])
        }
      }
      
      return .restored
    } catch let error {
      // Track restoration failure
      await MainActor.run {
        MixpanelManager.shared.track(event: .purchaseFailed, properties: [
          "source": "revenuecat_purchase_controller",
          "action": "restore_purchases",
          "error_description": error.localizedDescription
        ])
      }
      return .failed(error)
    }
  }
}
