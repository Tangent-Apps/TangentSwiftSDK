# TangentSwiftSDK

A comprehensive iOS SDK for analytics, tracking, and monetization that integrates Mixpanel, Adjust, RevenueCat, Superwall, and App Tracking Transparency.

## Features

- 📊 **Analytics**: Mixpanel integration for event tracking and user analytics
- 📈 **Attribution**: Adjust integration for attribution tracking and campaign analysis
- 💰 **Monetization**: RevenueCat integration for subscription management
- 🎯 **Paywall**: Superwall integration for dynamic paywalls
- 🔒 **Privacy**: App Tracking Transparency (ATT) support
- 🎨 **SwiftUI**: Ready-to-use SwiftUI components

## Requirements

- iOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add TangentSwiftSDK to your project using Swift Package Manager:

1. In Xcode, go to File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/YourOrg/TangentSwiftSDK`
3. Choose the version requirements
4. Add to your target

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/YourOrg/TangentSwiftSDK", from: "1.0.0")
]
```

## Quick Start

### 1. Initialize the SDK

```swift
import TangentSwiftSDK

// In your AppDelegate or App struct
let config = TangentSwiftSDK.Configuration(
    mixpanelToken: "your-mixpanel-token",
    adjustAppToken: "your-adjust-token",
    revenueCatAPIKey: "your-revenuecat-key",
    superwallAPIKey: "your-superwall-key"
)

TangentSwiftSDK.shared.initialize(with: config)
```

### 2. Track Events

```swift
// Track predefined events
TangentSwiftSDK.shared.analytics.track(event: .appLaunched)

// Track custom events
TangentSwiftSDK.shared.analytics.trackCustomEvent("user_signup", properties: [
    "source": "email",
    "plan": "free"
])

// Track screen views
TangentSwiftSDK.shared.analytics.trackScreenView("Dashboard")
```

### 3. Request ATT Permission

```swift
// Request tracking permission
TangentSwiftSDK.shared.tracking.requestTrackingPermission { granted in
    print("Tracking permission: \(granted)")
}

// Or use the provided SwiftUI view
ATTPermissionView { granted in
    print("ATT result: \(granted)")
}
```

### 4. Handle Subscriptions

```swift
// Check subscription status
await TangentSwiftSDK.shared.monetization.checkSubscriptionStatus()

// Purchase a product
if let offerings = TangentSwiftSDK.shared.monetization.offerings,
   let package = offerings.current?.monthly {
    let success = await TangentSwiftSDK.shared.monetization.purchaseProduct(package.storeProduct)
    print("Purchase success: \(success)")
}
```

## Advanced Usage

### Analytics

```swift
// Identify user
TangentSwiftSDK.shared.analytics.identify(userId: "user123")

// Set user properties
TangentSwiftSDK.shared.analytics.setUserProfile(properties: [
    "name": "John Doe",
    "email": "john@example.com",
    "plan": "premium"
])

// Track revenue
TangentSwiftSDK.shared.analytics.trackRevenue(
    amount: 9.99,
    productId: "premium_monthly"
)
```

### Tracking

```swift
// Check tracking status
let isAllowed = TangentSwiftSDK.shared.tracking.isTrackingAllowed
let canRequest = TangentSwiftSDK.shared.tracking.canRequestTracking
let status = TangentSwiftSDK.shared.tracking.statusDescription

// Get IDFA
let idfa = TangentSwiftSDK.shared.tracking.advertisingIdentifier
```

### SwiftUI Integration

```swift
import SwiftUI
import TangentSwiftSDK

struct ContentView: View {
    var body: some View {
        VStack {
            Button("Track Event") {
                TangentSwiftSDK.shared.analytics.trackButtonTap("content_button")
            }
            
            // Use ATT permission view
            ATTPermissionView { granted in
                print("Permission granted: \(granted)")
            }
        }
    }
}
```

## Info.plist Requirements

Add the following to your `Info.plist` for ATT support:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>We'd like your permission to track your activity across apps and websites to provide you with personalized insights and better app experience.</string>
```

## Architecture

The SDK is organized into several modules:

- **Analytics**: Mixpanel and Adjust integration
- **Tracking**: App Tracking Transparency management
- **Paywall**: RevenueCat and Superwall integration
- **Core**: Service layer abstractions

## Events

The SDK includes predefined events for common app actions:

- App lifecycle events
- Onboarding events
- Dashboard/UI events
- Chat/messaging events
- Task/gamification events
- Subscription events
- User actions
- Privacy & permissions

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions and support, please contact the Tangent team.