//
//  StoreKitPurchaseController.swift
//  TangentSwiftSDK
//
//  Native StoreKit 2 purchase controller for Superwall. Replaces the
//  RevenueCat-backed RCPurchaseController. Unlike the old controller this
//  one does NOT hardcode any Adjust event tokens — analytics emission is
//  handled by the app-side PurchaseAttributionForwarder which observes the
//  same Transaction.updates stream and dispatches the right per-token
//  Adjust event for each transaction type (jid2u2 / 4iihrx / ej4ikl / etc.).
//

import Foundation
import SuperwallKit
import StoreKit
import Security

enum StoreKitPurchaseError: LocalizedError {
    case sk2ProductNotFound
    case unverifiedTransaction
    case unknownResult

    var errorDescription: String? {
        switch self {
        case .sk2ProductNotFound:
            return "Superwall didn't pass a StoreKit 2 product."
        case .unverifiedTransaction:
            return "Transaction failed Apple's signature verification."
        case .unknownResult:
            return "Unknown StoreKit purchase result."
        }
    }
}

@MainActor
final class StoreKitPurchaseController: PurchaseController {

    private var syncTask: Task<Void, Never>?

    // MARK: Sync Subscription Status

    /// Keeps `Superwall.shared.subscriptionStatus` aligned with the device's
    /// actual entitlement state. Reads `Transaction.currentEntitlements` on
    /// startup, then re-reads whenever `Transaction.updates` fires.
    /// Honors the Keychain `lifetime_subscription_purchased` flag as a
    /// fallback (matches what RCPurchaseController did).
    func syncSubscriptionStatus() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.refreshSuperwallEntitlement()

            for await result in Transaction.updates {
                if case .verified = result {
                    await self?.refreshSuperwallEntitlement()
                }
            }
        }
    }

    private func refreshSuperwallEntitlement() async {
        var hasPremium = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.ownershipType == .purchased else { continue }
            // Non-renewing lifetime (no expiration) or unexpired subscription.
            if tx.expirationDate == nil || (tx.expirationDate ?? .distantPast) > Date() {
                hasPremium = true
                break
            }
        }

        // Keychain lifetime fallback — RC may not have surfaced the lifetime
        // transaction yet on a fresh reinstall, but the app may have written
        // the keychain flag during the original purchase.
        if !hasPremium, Self.hasLifetimeInKeychain() {
            hasPremium = true
        }

        await MainActor.run {
            if hasPremium {
                Superwall.shared.subscriptionStatus = .active(Set([Entitlement(id: "Pro")]))
            } else {
                Superwall.shared.subscriptionStatus = .inactive
            }
        }
    }

    // MARK: Keychain Lifetime

    private static func hasLifetimeInKeychain() -> Bool {
        let key = "lifetime_subscription_purchased"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.tangent.polyAI",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, !data.isEmpty else {
            return false
        }
        return data[0] == 1
    }

    // MARK: Handle Purchases

    /// Called by Superwall when the user taps a purchase button on one of its
    /// paywalls. We hand off to native SK2: `Product.purchase()`, finish the
    /// transaction, then re-sync entitlement. The PurchaseAttributionForwarder
    /// will see the same transaction via its own `Transaction.updates`
    /// listener and emit Mixpanel + Adjust *Purchase Completed* + revenue
    /// events with the right per-token payload — no per-token analytics
    /// hardcoded here.
    ///
    /// The canonical `Purchase Started` / `Purchase Failed` Mixpanel events
    /// ARE fired here directly. Pre-RC-removal those came from RC's own
    /// purchase delegate; post-removal callers must invoke them so funnels
    /// stay complete. We fire from inside the SDK rather than via a
    /// notification because Superwall-driven purchases have no app-side
    /// caller to hook into — the user tapping a Superwall paywall button
    /// is the entry point.
    func purchase(product: SuperwallKit.StoreProduct) async -> PurchaseResult {
        let productId = product.productIdentifier
        MixpanelManager.shared.track(event: .purchaseStarted, properties: [
            "source": "superwall_paywall",
            "product_id": productId,
        ])

        guard let sk2Product = product.sk2Product else {
            MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                "source": "superwall_paywall",
                "product_id": productId,
                "reason": "sk2_product_not_found",
            ])
            return .failed(StoreKitPurchaseError.sk2ProductNotFound)
        }

        do {
            let result = try await sk2Product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // IMPORTANT: do NOT call transaction.finish() here. The
                    // app-side listeners (SubscriptionService for subs/
                    // lifetime, CoinService for consumables) take ownership
                    // and finish after they've processed the transaction.
                    // If we finished here, a coin purchase via Superwall
                    // could race CoinService's listener and miss crediting
                    // until next launch.
                    await refreshSuperwallEntitlement()

                    // Notify app-side observers (PurchaseAttributionForwarder
                    // for Mixpanel/Adjust, WalletService for gem crediting).
                    // Apple's Transaction.updates listener doesn't reliably
                    // fire for foreground purchases returned by
                    // `Product.purchase()`, so we hand off the transaction
                    // explicitly. The JWS rides in userInfo because the
                    // wallet server verifies the SIGNED transaction — the
                    // Transaction object alone isn't enough to credit.
                    NotificationCenter.default.post(
                        name: Notification.Name("PolyAITransactionFromSuperwall"),
                        object: transaction,
                        userInfo: ["jws": verification.jwsRepresentation]
                    )

                    return .purchased
                case .unverified:
                    MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                        "source": "superwall_paywall",
                        "product_id": productId,
                        "reason": "unverified_transaction",
                    ])
                    return .failed(StoreKitPurchaseError.unverifiedTransaction)
                }
            case .userCancelled:
                MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                    "source": "superwall_paywall",
                    "product_id": productId,
                    "reason": "user_cancelled",
                ])
                return .cancelled
            case .pending:
                MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                    "source": "superwall_paywall",
                    "product_id": productId,
                    "reason": "pending",
                ])
                return .pending
            @unknown default:
                MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                    "source": "superwall_paywall",
                    "product_id": productId,
                    "reason": "unknown_purchase_result",
                ])
                return .failed(StoreKitPurchaseError.unknownResult)
            }
        } catch {
            MixpanelManager.shared.track(event: .purchaseFailed, properties: [
                "source": "superwall_paywall",
                "product_id": productId,
                "reason": (error as NSError).localizedDescription,
            ])
            return .failed(error)
        }
    }

    // MARK: Handle Restores

    /// Triggers Apple's transaction sync, then re-walks current entitlements
    /// to update Superwall's status. PurchaseAttributionForwarder will see
    /// any newly-surfaced transactions via Transaction.updates and emit
    /// restored events on its own.
    func restorePurchases() async -> RestorationResult {
        do {
            try await AppStore.sync()
            await refreshSuperwallEntitlement()
            return .restored
        } catch {
            return .failed(error)
        }
    }
}
