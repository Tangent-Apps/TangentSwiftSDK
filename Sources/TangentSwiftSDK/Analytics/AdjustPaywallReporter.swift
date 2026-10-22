import Foundation
import StoreKit
@preconcurrency import AdjustSdk
import SuperwallKit

/// Sends Superwall paywall views and purchases to Adjust from the device, so the SDK can update the
/// SKAdNetwork conversion value straight away (server events can't reach the device's SKAN value).
///
/// Only first purchases are reported here; renewals, trial conversions and refunds stay with
/// Superwall's server integration, which also sees the ones that happen while the app is closed.
/// Sandbox / TestFlight / Xcode builds only log what they would send.
final class AdjustPaywallReporter {
    // MARK: - Properties
    private let tracking: AdjustPaywallTracking

    // MARK: - Initializer(s)
    init(tracking: AdjustPaywallTracking) {
        self.tracking = tracking
    }

    // MARK: - Reporting
    func reportPaywallView() async {
        let token = tracking.paywallViewedToken
        guard let event = ADJEvent(eventToken: token) else {
            print("❌ Adjust: Failed to create paywall view event with token: \(token)")
            return
        }
        guard await isProduction(nil) else {
            print("🧪 Adjust: Skipped non-production paywall view")
            return
        }
        Adjust.trackEvent(event)
        print("👀 Adjust: Sent paywall view")
    }

    func reportPurchase(transaction: StoreTransaction?, product: StoreProduct, type: TransactionType) async {
        let skTransaction = transaction?.sk2Transaction
        let productId = product.productIdentifier

        let token = token(for: type)
        guard let event = ADJEvent(eventToken: token) else {
            print("❌ Adjust: Failed to create purchase event with token: \(token)")
            return
        }

        event.setProductId(productId)
        if let transactionId = skTransaction.map({ String($0.id) }) ?? transaction?.storeTransactionId {
            event.setDeduplicationId(transactionId)
        }

        // A free trial carries no money; sending 0 revenue would land the user in a revenue range.
        var summary = "trial"
        if type != .freeTrialStart {
            let price = NSDecimalNumber(decimal: skTransaction?.price ?? product.price).doubleValue
            let currency = currencyCode(of: skTransaction) ?? product.currencyCode ?? "USD"
            let country = await storefrontCountryCode(of: skTransaction)
            let share = tracking.share(for: country)
            let proceeds = (price * share * 100).rounded() / 100
            event.setRevenue(proceeds, currency: currency)
            summary = "price \(price) → proceeds \(proceeds) \(currency) (share \(share), \(country ?? "unknown storefront"))"
        }

        // Sandbox / TestFlight / Xcode purchases would pollute production revenue (Apple also
        // speeds sandbox renewals up), so they're only logged.
        guard await isProduction(skTransaction) else {
            print("🧪 Adjust: Skipped non-production \(type) \(productId) — would send \(summary)")
            return
        }

        Adjust.trackEvent(event)
        print("💰 Adjust: Sent \(type) \(productId) — \(summary)")
    }

    // MARK: - Helpers
    private func token(for type: TransactionType) -> String {
        switch type {
        case .freeTrialStart:
            return tracking.trialStartedToken

        case .subscriptionStart:
            return tracking.subscriptionStartedToken

        case .nonRecurringProductPurchase:
            return tracking.oneTimePurchaseToken
        }
    }

    private func currencyCode(of transaction: StoreKit.Transaction?) -> String? {
        transaction?.currency?.identifier
    }

    /// The buyer's App Store country (ISO 3166-1 alpha-3), which decides the tax removed.
    private func storefrontCountryCode(of transaction: StoreKit.Transaction?) async -> String? {
        if let transaction {
            if #available(iOS 17.0, *) {
                return transaction.storefront.countryCode
            }
            return transaction.storefrontCountryCode
        }
        return await Storefront.current?.countryCode
    }

    /// The purchase's own environment, or the app install's when there is no transaction (paywall
    /// views). Unknown environments count as non-production, so nothing doubtful reaches Adjust.
    private func isProduction(_ transaction: StoreKit.Transaction?) async -> Bool {
        if let transaction {
            return transaction.environment == .production
        }
        guard let appTransaction = try? await AppTransaction.shared.payloadValue else {
            return false
        }
        return appTransaction.environment == .production
    }
}
