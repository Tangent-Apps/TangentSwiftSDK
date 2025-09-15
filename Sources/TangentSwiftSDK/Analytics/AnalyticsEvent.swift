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
    case birthDateEntered = "Birth Date Entered"
    case birthTimeEntered = "Birth Time Entered"
    case birthLocationEntered = "Birth Location Entered"
    case zodiacSignShown = "Zodiac Sign Shown"
    
    // Dashboard
    case dashboardViewed = "Dashboard Viewed"
    case horoscopeViewed = "Horoscope Viewed"
    case timeFrameChanged = "Time Frame Changed"
    case quickActionTapped = "Quick Action Tapped"
    case awareSectionViewed = "Aware Section Viewed"
    
    // Chat
    case chatStarted = "Chat Started"
    case chatMessageSent = "Chat Message Sent"
    case chatMessageReceived = "Chat Message Received"
    case chatLimitReached = "Chat Limit Reached"
    
    // Tasks
    case tasksViewed = "Tasks Viewed"
    case taskCompleted = "Task Completed"
    case allTasksCompleted = "All Tasks Completed"
    case missionAccomplished = "Mission Accomplished"
    
    // Subscription
    case paywallViewed = "Paywall Viewed"
    case paywallDismissed = "Paywall Dismissed"
    case discountViewShown = "Discount View Shown"
    case purchaseStarted = "Purchase Started"
    case purchaseCompleted = "Purchase Completed"
    case purchaseFailed = "Purchase Failed"
    case purchaseRestored = "Purchase Restored"
    case subscriptionActivated = "Subscription Activated"
    case subscriptionCancelled = "Subscription Cancelled"
    
    // User Actions
    case buttonTapped = "Button Tapped"
    case screenViewed = "Screen Viewed"
    case featureUsed = "Feature Used"
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