import Foundation

/// Opt-in configuration for reporting the paywall funnel (paywall views and first purchases) to
/// Adjust from the device, so the Adjust SDK can update the SKAdNetwork conversion value.
///
/// Superwall's server integration should keep reporting renewals, trial conversions and refunds,
/// but its trial-start / subscription-start / non-recurring tokens must be cleared in the Superwall
/// dashboard when an app turns this on — otherwise every first purchase is counted twice.
public struct AdjustPaywallTracking {
    /// The share of the customer price kept when no table lists the storefront, or a value can't be
    /// a share: Apple's 15% Small Business Program commission, no tax removed.
    public static let defaultTakeHomeShare = 0.85

    let paywallViewedToken: String
    let trialStartedToken: String
    let subscriptionStartedToken: String
    let oneTimePurchaseToken: String
    private let takeHomeShares: [String: Double]
    private let takeHomeShare: ((_ storefrontCountryCode: String?) -> Double?)?

    /// Pass neither `takeHomeShares` nor `takeHomeShare` to use the SDK's built-in table.
    ///
    /// - Parameters:
    ///   - paywallViewedToken: Adjust event for a Superwall paywall opening (sent without revenue).
    ///   - trialStartedToken: Adjust event for a free trial start (sent without revenue).
    ///   - subscriptionStartedToken: Adjust event for a paid subscription start.
    ///   - oneTimePurchaseToken: Adjust event for a consumable / non-consumable purchase.
    ///   - takeHomeShares: Shares (proceeds ÷ price) by App Store country, ISO 3166-1 alpha-3
    ///     (e.g. "GBR"), layered over the built-in table — for an app with different rates.
    ///   - takeHomeShare: Called at purchase time with the App Store country; return a share to use
    ///     it, or `nil` to fall back to the tables. Read remote values (e.g. Remote Config) here.
    public init(
        paywallViewedToken: String,
        trialStartedToken: String,
        subscriptionStartedToken: String,
        oneTimePurchaseToken: String,
        takeHomeShares: [String: Double] = [:],
        takeHomeShare: ((_ storefrontCountryCode: String?) -> Double?)? = nil
    ) {
        self.paywallViewedToken = paywallViewedToken
        self.trialStartedToken = trialStartedToken
        self.subscriptionStartedToken = subscriptionStartedToken
        self.oneTimePurchaseToken = oneTimePurchaseToken
        self.takeHomeShares = takeHomeShares
        self.takeHomeShare = takeHomeShare
    }

    /// Lookup → app table → built-in table → ``defaultTakeHomeShare``. A value that can't be a
    /// share (e.g. a typo like 85) is skipped, so a bad remote value can't zero or inflate revenue.
    func share(for countryCode: String?) -> Double {
        let candidates: [Double?] = [
            takeHomeShare?(countryCode),
            countryCode.flatMap { takeHomeShares[$0] },
            countryCode.flatMap { Self.builtInTakeHomeShares[$0] }
        ]
        return candidates.lazy.compactMap { $0 }.first(where: isValidShare) ?? Self.defaultTakeHomeShare
    }

    private func isValidShare(_ share: Double) -> Bool {
        share.isFinite && share > 0 && share <= 1
    }
}
