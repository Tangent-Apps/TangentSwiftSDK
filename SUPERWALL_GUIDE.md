# TangentSwiftSDK - Superwall Integration Guide

## Overview

TangentSwiftSDK uses **Superwall** as the sole paywall and subscription management solution. Superwall handles purchases natively via StoreKit — no RevenueCat or other billing SDK is needed.

---

## 1. SDK Setup

### Initialize the SDK

```swift
import TangentSwiftSDK

// In your App struct or AppDelegate
let config = TangentSwiftSDK.Configuration(
    mixpanelToken: "your-mixpanel-token",
    adjustAppToken: "your-adjust-token",
    adjustPurchaseEventToken: "your-adjust-purchase-event-token",
    superwallAPIKey: "your-superwall-api-key",
    enableATT: true
)

TangentSwiftSDK.shared.initialize(with: config)
```

### SwiftUI App Example

```swift
import SwiftUI
import TangentSwiftSDK

@main
struct MyApp: App {
    init() {
        let config = TangentSwiftSDK.Configuration(
            mixpanelToken: "your-mixpanel-token",
            superwallAPIKey: "your-superwall-api-key"
        )
        TangentSwiftSDK.shared.initialize(with: config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

## 2. Showing Paywalls

### Show Default Paywall

The simplest way to show your paywall (configured in the Superwall dashboard under the `campaign_trigger` placement):

```swift
TangentSwiftSDK.shared.superwall.showPaywall()
```

### Show Paywall with Discount Follow-Up

If the user dismisses the paywall, automatically show a discount paywall 2 seconds later (uses the `discount_offer` placement):

```swift
TangentSwiftSDK.shared.superwall.showPaywall(showDiscountAfterDismiss: true)
```

### Show Discount Paywall Directly

```swift
TangentSwiftSDK.shared.superwall.showDiscountPayWall()
```

### Register Custom Placements

Trigger any placement you've configured in the Superwall dashboard:

```swift
// Simple placement
TangentSwiftSDK.shared.superwall.register(event: "feature_gate")

// Placement with parameters
TangentSwiftSDK.shared.superwall.register(event: "feature_gate", params: [
    "feature_name": "premium_chat",
    "source": "home_screen"
])
```

### Gate Features Behind a Paywall

Use `register` to gate a feature. If the user is subscribed, the handler runs immediately. If not, Superwall shows the paywall first:

```swift
// In Superwall dashboard, create a placement called "premium_feature"
// and attach a paywall campaign to it
TangentSwiftSDK.shared.superwall.register(event: "premium_feature")
```

---

## 3. Checking Subscription Status

### Check if User is Subscribed

```swift
let subscribed = TangentSwiftSDK.shared.superwall.isSubscribed

if subscribed {
    // Show premium content
} else {
    // Show free content or paywall
}
```

### Use in SwiftUI Views

`SuperwallManager` is an `ObservableObject`, so you can observe changes:

```swift
import SwiftUI
import TangentSwiftSDK

struct ContentView: View {
    @ObservedObject var superwall = SuperwallManager.shared

    var body: some View {
        VStack {
            if superwall.isSubscribed {
                Text("Welcome, Premium User!")
            } else {
                Button("Upgrade to Pro") {
                    superwall.showPaywall()
                }
            }
        }
    }
}
```

---

## 4. Handling Subscription Events

### Listen for Successful Purchases

```swift
TangentSwiftSDK.shared.superwall.onSubscriptionComplete = {
    // Called when a transaction completes successfully
    print("User subscribed!")
    // Navigate to premium content, dismiss onboarding, etc.
}
```

### Listen for Paywall Dismissal (NotificationCenter)

```swift
NotificationCenter.default.addObserver(
    forName: .superwallPaywallDismissed,
    object: nil,
    queue: .main
) { _ in
    print("Paywall was dismissed")
}
```

### Listen for Paywall Dismissal (Combine / SwiftUI)

```swift
struct MyView: View {
    @ObservedObject var superwall = SuperwallManager.shared

    var body: some View {
        Text("Hello")
            .onChange(of: superwall.paywallDismissed) { dismissed in
                if dismissed {
                    // Handle paywall dismissal
                }
            }
    }
}
```

---

## 5. User Identity

### Identify User

Link the Superwall user to your own user ID (important for cross-device subscription restore):

```swift
TangentSwiftSDK.shared.superwall.identify(userId: "user_123")
```

### Set User Attributes

Pass custom attributes for targeting and segmentation in the Superwall dashboard:

```swift
TangentSwiftSDK.shared.superwall.setUserAttributes([
    "name": "John",
    "plan": "free",
    "signup_date": "2025-01-15",
    "total_sessions": 42
])
```

### Update Onboarding Status

Convenience method to track whether the user completed onboarding (useful for paywall targeting):

```swift
TangentSwiftSDK.shared.superwall.updateOnboardingStatus(true)
```

### Reset User (Logout)

Call this when the user logs out to clear Superwall's user state:

```swift
TangentSwiftSDK.shared.superwall.reset()
```

---

## 6. Building a Custom Paywall (Code-Based)

If you want a fully custom SwiftUI paywall instead of using Superwall's visual editor, you can build one and use the SDK to check status and trigger purchases.

### Option A: Use Superwall Placements with Custom UI Logic

```swift
struct CustomPaywallView: View {
    @ObservedObject var superwall = SuperwallManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Unlock Premium")
                .font(.largeTitle.bold())

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "star.fill", text: "Unlimited access")
                FeatureRow(icon: "bolt.fill", text: "Faster responses")
                FeatureRow(icon: "crown.fill", text: "Exclusive content")
            }

            Spacer()

            // This triggers a Superwall placement which handles the purchase
            Button("Subscribe Now") {
                superwall.register(event: "campaign_trigger")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.blue)
            .cornerRadius(16)

            Button("Restore Purchases") {
                superwall.register(event: "restore")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.yellow)
            Text(text)
                .font(.body)
        }
    }
}
```

### Option B: Fully Custom Paywall with StoreKit + Superwall Status

If you want complete control over the purchase flow while still using Superwall for subscription status:

```swift
import StoreKit
import TangentSwiftSDK

struct FullCustomPaywallView: View {
    @ObservedObject var superwall = SuperwallManager.shared
    @State private var products: [Product] = []
    @State private var isPurchasing = false

    let productIds = ["com.yourapp.monthly", "com.yourapp.yearly"]

    var body: some View {
        VStack(spacing: 24) {
            Text("Go Premium")
                .font(.largeTitle.bold())

            ForEach(products, id: \.id) { product in
                ProductCard(product: product) {
                    await purchase(product)
                }
            }

            if isPurchasing {
                ProgressView("Processing...")
            }
        }
        .padding()
        .task {
            await loadProducts()
        }
    }

    private func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()

                // Track with analytics
                TangentSwiftSDK.shared.analytics.track(event: .purchaseCompleted, properties: [
                    "product_id": product.id,
                    "price": product.displayPrice
                ])

            case .pending:
                print("Purchase pending")
            case .userCancelled:
                TangentSwiftSDK.shared.analytics.track(event: .purchaseCancelled, properties: [
                    "product_id": product.id
                ])
            @unknown default:
                break
            }
        } catch {
            TangentSwiftSDK.shared.analytics.track(event: .purchaseFailed, properties: [
                "product_id": product.id,
                "error": error.localizedDescription
            ])
        }
    }
}

struct ProductCard: View {
    let product: Product
    let onPurchase: () async -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(product.displayName)
                    .font(.headline)
                Text(product.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(product.displayPrice) {
                Task { await onPurchase() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
```

---

## 7. Common Patterns

### Show Paywall on App Launch (After Onboarding)

```swift
struct HomeView: View {
    @ObservedObject var superwall = SuperwallManager.shared

    var body: some View {
        VStack {
            // Your main content
        }
        .onAppear {
            if !superwall.isSubscribed {
                superwall.showPaywall(showDiscountAfterDismiss: true)
            }
        }
    }
}
```

### Gate a Feature

```swift
func openPremiumFeature() {
    if TangentSwiftSDK.shared.superwall.isSubscribed {
        // Go directly to the feature
        navigateToPremiumFeature()
    } else {
        // Show paywall, then navigate on success
        TangentSwiftSDK.shared.superwall.onSubscriptionComplete = {
            navigateToPremiumFeature()
        }
        TangentSwiftSDK.shared.superwall.showPaywall()
    }
}
```

### Track Paywall Analytics

Paywall events are tracked automatically by the SDK via `SuperwallDelegate`:

| Event | Tracked Automatically |
|-------|----------------------|
| Paywall Viewed | Yes |
| Paywall Dismissed | Yes |
| Transaction Complete | Yes |

For custom tracking, use the analytics service:

```swift
TangentSwiftSDK.shared.analytics.track(event: .purchaseStarted, properties: [
    "source": "custom_paywall",
    "product_id": "com.yourapp.monthly"
])
```

---

## 8. Superwall Dashboard Setup

1. **Create Placements** - At minimum, create these placements in your Superwall dashboard:
   - `campaign_trigger` - Your main paywall
   - `discount_offer` - Discount paywall shown after dismissal

2. **Create Products** - Add your App Store Connect subscription products in the Superwall dashboard

3. **Design Paywalls** - Use the Superwall visual editor to design your paywalls, or use code-based paywalls as shown above

4. **Set Up Campaigns** - Link placements to paywalls with targeting rules

---

## API Reference

### SuperwallManager

| Property / Method | Type | Description |
|---|---|---|
| `isSubscribed` | `Bool` | Whether the user has an active subscription |
| `isInitialized` | `Bool` | Whether Superwall has been initialized |
| `paywallDismissed` | `Bool` | Whether the paywall was just dismissed |
| `onSubscriptionComplete` | `(() -> Void)?` | Callback fired on successful purchase |
| `showPaywall(showDiscountAfterDismiss:)` | Method | Show the main paywall |
| `showDiscountPayWall()` | Method | Show the discount paywall |
| `register(event:params:)` | Method | Trigger a Superwall placement |
| `identify(userId:)` | Method | Link user identity |
| `setUserAttributes(_:)` | Method | Set targeting attributes |
| `updateOnboardingStatus(_:)` | Method | Set onboarding completion status |
| `reset()` | Method | Clear user state (logout) |
