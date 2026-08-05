# TangentSwiftSDK

A comprehensive iOS SDK for analytics, attribution, and monetization. Wraps Mixpanel, Adjust, and Superwall behind a single unified interface, with built-in support for App Tracking Transparency, Stripe web checkout, and subscription lifecycle management.

## Features

- **Analytics** — Mixpanel event tracking, user identification, revenue tracking
- **Attribution** — Adjust SDK with IDFA/IDFV forwarding to Superwall
- **Paywall** — Superwall with multi-placement support (IAP + Stripe web checkout)
- **Subscription lifecycle** — `onSubscriptionComplete`, `subscriptionStatusDidChange`, link redemption delegates
- **ATT** — App Tracking Transparency with a customizable pre-permission screen

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

```
https://github.com/Tangent-Apps/TangentSwiftSDK
```

In Xcode: **File → Add Package Dependencies**, paste the URL above, and add to your target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Tangent-Apps/TangentSwiftSDK", branch: "feature/adjust-superwall-connection")
]
```

---

## Quick Start

### 1. Initialize

Call this in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` before anything else:

```swift
import TangentSwiftSDK

let config = TangentSwiftSDK.Configuration(
    mixpanelToken: "your-mixpanel-token",
    adjustAppToken: "your-adjust-token",
    adjustPurchaseEventToken: "your-adjust-purchase-event-token",
    superwallAPIKey: "your-superwall-key",
    enableATT: true,
    attConfiguration: TangentSwiftSDK.ATTConfiguration(
        title: "Track Your Progress",
        description: "We use this to personalize your experience.",
        benefits: [
            TangentSwiftSDK.ATTBenefit(icon: "chart.bar", text: "Personalized insights"),
            TangentSwiftSDK.ATTBenefit(icon: "sparkles",  text: "Better recommendations")
        ]
    )
)

TangentSwiftSDK.shared.initialize(with: config)
```

---

## Analytics

```swift
// Predefined events
TangentSwiftSDK.shared.analytics.track(event: .paywallViewed)
TangentSwiftSDK.shared.analytics.track(event: .subscriptionActivated)

// Custom events
TangentSwiftSDK.shared.analytics.trackCustomEvent("onboarding_step_completed", properties: [
    "step": "goal_selection"
])

// Screen views
TangentSwiftSDK.shared.analytics.trackScreenView("Dashboard")

// Button taps
TangentSwiftSDK.shared.analytics.trackButtonTap("start_workout", screen: "Home")

// User identity
TangentSwiftSDK.shared.analytics.identify(userId: "user-123")
TangentSwiftSDK.shared.analytics.setUserProfile(properties: [
    "plan": "premium",
    "onboarding_complete": true
])

// Revenue
TangentSwiftSDK.shared.analytics.trackRevenue(
    amount: 9.99,
    productId: "com.app.yearly",
    transactionId: transaction.id
)
```

---

## ATT (App Tracking Transparency)

```swift
// Request permission
TangentSwiftSDK.shared.tracking.requestTrackingPermission { granted in
    print("ATT granted: \(granted)")
    // Fetch Adjust ADID now that status is known
}

// Query status
let isAllowed = TangentSwiftSDK.shared.tracking.isTrackingAllowed
let status   = TangentSwiftSDK.shared.tracking.statusDescription
let idfa     = TangentSwiftSDK.shared.tracking.advertisingIdentifier
```

---

## Paywall (Superwall)

### Show a paywall

```swift
// Default IAP campaign
TangentSwiftSDK.shared.superwall.showPaywall()

// Specific placement (e.g. Stripe web checkout campaign)
TangentSwiftSDK.shared.superwall.showPaywall(placement: "stripe-triggered")

// With discount paywall shown on dismiss
TangentSwiftSDK.shared.superwall.showPaywall(
    placement: "campaign_trigger",
    showDiscountAfterDismiss: true
)
```

### Handle subscription completion

Set `onSubscriptionComplete` before showing a paywall. It fires on both IAP (`transactionComplete` event) and Stripe (`subscriptionStatusDidChange` → active):

```swift
TangentSwiftSDK.shared.superwall.onSubscriptionComplete = {
    Task { @MainActor in
        // Update your local subscription state
        SubscriptionManager.shared.setSubscribed(true)
    }
}
TangentSwiftSDK.shared.superwall.showPaywall(placement: "stripe-triggered")
```

### Check subscription status

```swift
let isActive = TangentSwiftSDK.shared.superwall.isSubscribed
```

### Other paywall actions

```swift
// Discount offer
TangentSwiftSDK.shared.superwall.showDiscountPayWall()

// Register an event without showing a paywall (for analytics/targeting)
TangentSwiftSDK.shared.superwall.register(event: "feature_gate_hit", params: ["screen": "workouts"])

// User attributes (for Superwall targeting rules)
TangentSwiftSDK.shared.superwall.setUserAttributes(["has_completed_onboarding": true])

// Identify user
TangentSwiftSDK.shared.superwall.identify(userId: "user-123")

// Reset (on logout)
TangentSwiftSDK.shared.superwall.reset()
```

---

## Stripe Web Checkout

Superwall can drive a Stripe-based web checkout instead of (or alongside) Apple IAP. The checkout opens in an in-app `SFSafariViewController` sheet, and the SDK verifies the payment via a deep link on return.

### App-side setup (one-time)

**1. Intercept Stripe URLs (keeps checkout in-app)**

Add this to your `AppDelegate` and call `_ = UIApplication.swizzleStripeCheckout` in `didFinishLaunchingWithOptions`:

```swift
import SafariServices

extension UIApplication {
    private static weak var _stripeCheckoutVC: SFSafariViewController?

    static let swizzleStripeCheckout: Void = {
        guard
            let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.open(_:options:completionHandler:))),
            let swizzled = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.gw_open(_:options:completionHandler:)))
        else { return }
        method_exchangeImplementations(original, swizzled)
    }()

    static func dismissStripeCheckout() {
        _stripeCheckoutVC?.dismiss(animated: true)
        _stripeCheckoutVC = nil
    }

    @objc func gw_open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any] = [:], completionHandler completion: ((Bool) -> Void)? = nil) {
        guard url.host?.contains("checkout.stripe.com") == true else {
            gw_open(url, options: options, completionHandler: completion)
            return
        }
        DispatchQueue.main.async {
            let safariVC = SFSafariViewController(url: url)
            safariVC.modalPresentationStyle = .pageSheet
            if let sheet = safariVC.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
            UIApplication._stripeCheckoutVC = safariVC
            self.gwTopViewController?.present(safariVC, animated: true)
            completion?(true)
        }
    }

    private var gwTopViewController: UIViewController? {
        guard let scene = connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
```

**2. Register a URL scheme in `Info.plist`**

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourapp</string>
        </array>
    </dict>
</array>
```

Configure the same scheme as the Stripe success/cancel redirect URL in the Superwall dashboard.

**3. Handle the return deep link**

In your SwiftUI `App` (or `SceneDelegate`):

```swift
.onOpenURL { url in
    UIApplication.dismissStripeCheckout()
    TangentSwiftSDK.shared.superwall.handleDeepLink(url)
    // your own deep link routing...
}
```

### Stripe payment result — navigating to dashboard

Listen for `superwallSubscriptionStatusDidChange` in the view that shows the paywall. It fires when Superwall verifies the Stripe payment:

```swift
.onReceive(NotificationCenter.default.publisher(for: .superwallSubscriptionStatusDidChange)) { notification in
    guard let isActive = notification.userInfo?["isActive"] as? Bool, isActive else { return }
    // Navigate to dashboard / finish onboarding
}
```

---

## Notifications

| Name | When it fires |
|------|---------------|
| `.superwallPaywallDismissed` | Superwall paywall dismissed (IAP path) |
| `.superwallSubscriptionStatusDidChange` | Superwall subscription status changed — `userInfo["isActive"]: Bool` |

```swift
NotificationCenter.default.publisher(for: .superwallPaywallDismissed)
NotificationCenter.default.publisher(for: .superwallSubscriptionStatusDidChange)
```

---

## Delegate Callbacks (SuperwallDelegate)

These fire automatically — no setup needed beyond initializing the SDK:

| Callback | When |
|----------|------|
| `onSubscriptionComplete` | IAP `transactionComplete` **or** Stripe `subscriptionStatusDidChange → active` |
| `willRedeemLink()` | App opened via Superwall deep link (Stripe return URL received) |
| `didRedeemLink(result:)` | Redemption verified by Superwall backend |
| `subscriptionStatusDidChange(from:to:)` | Any subscription state transition |

---

## Architecture

```
TangentSwiftSDK
├── Analytics/
│   ├── MixpanelManager   — event tracking, user profiles, revenue
│   ├── AdjustManager     — attribution, ADID forwarding to Superwall
│   └── AnalyticsEvent    — predefined event enum
├── Paywall/
│   └── SuperwallManager  — paywall display, Stripe web checkout, delegate
├── Tracking/
│   └── ATTManager        — App Tracking Transparency
└── Core/
    ├── AnalyticsService  — unified analytics facade
    └── TrackingService   — ATT status queries
```

---

## Info.plist Requirements

```xml
<!-- ATT (required if enableATT: true) -->
<key>NSUserTrackingUsageDescription</key>
<string>We'd like your permission to track your activity to provide personalized insights.</string>
```

---

## Support

For questions, contact the Tangent Apps team.
