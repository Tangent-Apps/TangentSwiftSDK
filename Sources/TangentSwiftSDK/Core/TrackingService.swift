import Foundation
import AppTrackingTransparency

// MARK: - Tracking Service
public final class TrackingService: ObservableObject {
    public static let shared = TrackingService()

    private init() {}

    // MARK: - App Tracking Transparency

    /// Check if ATT is enabled in the SDK
    public var isATTEnabled: Bool {
        return ATTManager.shared.isEnabled
    }

    /// Request ATT permission
    public func requestTrackingPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        guard isATTEnabled else {
            print("⚠️ TrackingService: ATT is not enabled in SDK configuration")
            completion(false)
            return
        }
        ATTManager.shared.requestTrackingPermission(completion: completion)
    }

    /// Check if tracking is allowed
    public var isTrackingAllowed: Bool {
        guard isATTEnabled else { return false }
        return ATTManager.shared.isTrackingAllowed
    }

    /// Check if we can request tracking
    public var canRequestTracking: Bool {
        guard isATTEnabled else { return false }
        return ATTManager.shared.canRequestTracking
    }

    /// Get current tracking status
    public var trackingStatus: ATTrackingManager.AuthorizationStatus {
        guard isATTEnabled else { return .notDetermined }
        return ATTManager.shared.trackingStatus
    }

    /// Get tracking status description
    public var statusDescription: String {
        guard isATTEnabled else { return "ATT Not Enabled" }
        return ATTManager.shared.statusDescription
    }

    /// Get IDFA if available
    public var advertisingIdentifier: String? {
        guard isATTEnabled else { return nil }
        return ATTManager.shared.advertisingIdentifier
    }

    /// Update analytics services with tracking permission
    public func updateAnalyticsWithTrackingPermission() {
        guard isATTEnabled else {
            print("⚠️ TrackingService: ATT is not enabled in SDK configuration")
            return
        }
        ATTManager.shared.updateAnalyticsWithTrackingPermission()
    }
}