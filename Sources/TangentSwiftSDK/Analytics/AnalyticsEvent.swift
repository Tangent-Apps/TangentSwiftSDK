import Foundation

// MARK: - Analytics Events
public enum AnalyticsEvent: String, CaseIterable {
    // App Lifecycle
    case appLaunched = "App Launched"
    case sessionStart = "Session Start"
    case sessionEnd = "Session End"

    // Onboarding
    case onboardingStarted = "Onboarding Started"
    case onboardingCompleted = "Onboarding Completed"
    case onboardingStepCompleted = "Onboarding Step Completed"
    
    // Main App Content
    case homeViewed = "Home Viewed"
    case contentViewed = "Content Viewed"
    case featureAccessed = "Feature Accessed"

    // Streak
    case streakViewed = "Streak Viewed"
    
    // Communication/Chat (generic)
    case chatStarted = "Chat Started"
    case chatMessageSent = "Chat Message Sent"
    case chatMessageReceived = "Chat Message Received"
    case chatLimitReached = "Chat Limit Reached"
    
    
    // Subscription & Paywall
    case paywallViewed = "SuperWall Paywall Viewed"
    case paywallDismissed = "SuperWall Paywall Dismissed"
    case discountViewShown = "SuperWall Discount View Shown"

    // Purchase Flow
    case purchaseStarted = "Purchase Started"
    case purchaseCompleted = "Purchase Completed"
    case purchaseCancelled = "Purchase Cancelled"
    case purchaseFailed = "Purchase Failed"

    // Restore Purchase Flow
    case restorePurchaseStarted = "Restore Purchase Started"
    case restorePurchaseCompleted = "Restore Purchase Completed"
    case restorePurchaseFailed = "Restore Purchase Failed"

    // Subscription Status
    case subscriptionActivated = "Subscription Activated"
    case subscriptionCancelled = "Subscription Cancelled"
    case subscriptionStatus = "Subscription Status"

    // User Actions
    case buttonTapped = "Button Tapped"
    case screenViewed = "Screen Viewed"
    case errorOccurred = "Error Occurred"
    
    // Privacy & Permissions
    case attPermissionRequested = "ATT Permission Requested"
    
    // Custom Events (can be extended by apps)
    case customEvent = "Custom Event"
}

// MARK: - Analytics Event Extensions
public extension AnalyticsEvent {
    
    /// Get all event names as strings
    static var allEventNames: [String] {
        return AnalyticsEvent.allCases.map { $0.rawValue }
    }
    
    /// Create custom event with name
    static func custom(_ name: String) -> String {
        return name
    }
}
