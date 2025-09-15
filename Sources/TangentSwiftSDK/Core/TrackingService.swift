import Foundation
import AppTrackingTransparency

// MARK: - Tracking Service
@MainActor
public final class TrackingService: ObservableObject {
    public static let shared = TrackingService()
    
    private init() {}
    
    // MARK: - App Tracking Transparency
    
    /// Request ATT permission
    public func requestTrackingPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        ATTManager.shared.requestTrackingPermission(completion: completion)
    }
    
    /// Check if tracking is allowed
    public var isTrackingAllowed: Bool {
        return ATTManager.shared.isTrackingAllowed
    }
    
    /// Check if we can request tracking
    public var canRequestTracking: Bool {
        return ATTManager.shared.canRequestTracking
    }
    
    /// Get current tracking status
    public var trackingStatus: ATTrackingManager.AuthorizationStatus {
        return ATTManager.shared.trackingStatus
    }
    
    /// Get tracking status description
    public var statusDescription: String {
        return ATTManager.shared.statusDescription
    }
    
    /// Get IDFA if available
    public var advertisingIdentifier: String? {
        return ATTManager.shared.advertisingIdentifier
    }
    
    /// Update analytics services with tracking permission
    public func updateAnalyticsWithTrackingPermission() {
        ATTManager.shared.updateAnalyticsWithTrackingPermission()
    }
}