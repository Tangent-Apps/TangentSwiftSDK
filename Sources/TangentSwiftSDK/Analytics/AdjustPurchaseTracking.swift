import Foundation

/// Opt-in configuration for reporting first purchases to Adjust from the device.
///
/// Superwall's server integration should keep reporting renewals, trial conversions and refunds,
/// but its trial-start / subscription-start / non-recurring tokens must be cleared in the Superwall
/// dashboard when an app turns this on — otherwise every first purchase is counted twice.
public struct AdjustPurchaseTracking {
    /// The share of the customer price kept when the storefront is unknown or the provider returns
    /// an invalid value: Apple's 15% Small Business Program commission, no tax removed.
    public static let defaultTakeHomeShare = 0.85

    let trialStartedToken: String?
    let subscriptionStartedToken: String?
    let oneTimePurchaseToken: String?
    let takeHomeShare: (_ storefrontCountryCode: String?) -> Double

    /// - Parameters:
    ///   - trialStartedToken: Adjust event for a free trial start (sent without revenue).
    ///   - subscriptionStartedToken: Adjust event for a paid subscription start.
    ///   - oneTimePurchaseToken: Adjust event for a consumable / non-consumable purchase.
    ///   - takeHomeShare: Called at purchase time with the App Store country (ISO 3166-1 alpha-3,
    ///     e.g. "GBR") and returns the share of the price the developer keeps after tax and
    ///     Apple's commission (App Store Connect proceeds ÷ price). Read remote values here.
    public init(
        trialStartedToken: String? = nil,
        subscriptionStartedToken: String? = nil,
        oneTimePurchaseToken: String? = nil,
        takeHomeShare: @escaping (_ storefrontCountryCode: String?) -> Double = { _ in AdjustPurchaseTracking.defaultTakeHomeShare }
    ) {
        self.trialStartedToken = trialStartedToken
        self.subscriptionStartedToken = subscriptionStartedToken
        self.oneTimePurchaseToken = oneTimePurchaseToken
        self.takeHomeShare = takeHomeShare
    }
}
