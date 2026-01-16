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

  // MARK: - Subscription Status Helpers

  private func isTrialUser(from customerInfo: CustomerInfo) -> Bool {
    if let proEntitlement = customerInfo.entitlements["Pro"],
       proEntitlement.isActive,
       proEntitlement.periodType == .trial {
      return true
    }
    return false
  }

  private func isPaidUser(from customerInfo: CustomerInfo) -> Bool {
    if let proEntitlement = customerInfo.entitlements["Pro"],
       proEntitlement.isActive,
       proEntitlement.periodType == .normal {
      return true
    }
    return false
  }

  private func isSubscribed(from customerInfo: CustomerInfo) -> Bool {
    return customerInfo.entitlements["Pro"]?.isActive == true ||
           !customerInfo.activeSubscriptions.isEmpty
  }

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
          MixpanelManager.shared.track(event: .purchaseCancelled, properties: [
            "product_id": storeProduct.productIdentifier
          ])
        }
        return .cancelled
      } else {
        let customerInfo = revenueCatResult.customerInfo
        let subscribed = isSubscribed(from: customerInfo)
        let isTrial = isTrialUser(from: customerInfo)
        let isPaid = isPaidUser(from: customerInfo)
        let subscriptionType = getSubscriptionType(from: customerInfo)

        // Track successful purchase
        await MainActor.run {
          MixpanelManager.shared.track(event: .purchaseCompleted, properties: [
            "product_id": storeProduct.productIdentifier,
            "is_subscribed": subscribed,
            "is_trial": isTrial,
            "is_paid": isPaid,
            "subscription_type": subscriptionType
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
              currency: storeProduct.currencyCode ?? "USD"
            )
          }

          // Track subscription activation
          MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
            "trigger": "purchase",
            "is_subscribed": subscribed,
            "is_trial": isTrial,
            "is_paid": isPaid,
            "subscription_type": subscriptionType
          ])
        }
        return .purchased
      }
    } catch let error as ErrorCode {
      // Track purchase errors
      await MainActor.run {
        MixpanelManager.shared.track(event: .purchaseFailed, properties: [
          "product_id": product.productIdentifier,
          "error": error.localizedDescription
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
          "product_id": product.productIdentifier,
          "error": error.localizedDescription
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
      let subscribed = isSubscribed(from: customerInfo)
      let isTrial = isTrialUser(from: customerInfo)
      let isPaid = isPaidUser(from: customerInfo)
      let subscriptionType = getSubscriptionType(from: customerInfo)

      // Track successful restoration
      await MainActor.run {
        AdjustManager.shared.trackEvent("93azwp")
        MixpanelManager.shared.track(event: .restorePurchaseCompleted, properties: [
          "is_subscribed": subscribed,
          "is_trial": isTrial,
          "is_paid": isPaid,
          "subscription_type": subscriptionType
        ])

        // If user has active subscriptions, track subscription activation
        if subscribed {
          MixpanelManager.shared.track(event: .subscriptionActivated, properties: [
            "trigger": "restore_purchase",
            "is_subscribed": subscribed,
            "is_trial": isTrial,
            "is_paid": isPaid,
            "subscription_type": subscriptionType
          ])
        }
      }

      return .restored
    } catch let error {
      // Track restoration failure
      await MainActor.run {
        MixpanelManager.shared.track(event: .restorePurchaseFailed, properties: [
          "error": error.localizedDescription
        ])
      }
      return .failed(error)
    }
  }
}
