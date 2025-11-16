import Foundation
import AppTrackingTransparency
import AdSupport
import Combine
import SwiftUI
import UIKit

// MARK: - ATT Manager
@MainActor
public final class ATTManager: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = ATTManager()
    
    // MARK: - Published Properties
    @Published public var trackingStatus: ATTrackingManager.AuthorizationStatus = .notDetermined
    @Published public var hasRequestedPermission = false
    @Published public var isShowingATTAlert = false
    @Published public private(set) var isEnabled = false

    // MARK: - Private Properties
    private var permissionRequestCompletion: ((Bool) -> Void)?
    private var attConfiguration: TangentSwiftSDK.ATTConfiguration?
    
    // MARK: - Initialization
    private init() {
        updateTrackingStatus()
        observeStatusChanges()
    }
    
    // MARK: - Configuration
    internal func configure(with attConfiguration: TangentSwiftSDK.ATTConfiguration?) {
        self.attConfiguration = attConfiguration
        self.isEnabled = true
        print("✅ ATT: Enabled and configured")
    }
    
    // MARK: - Public Methods
    
    /// Request App Tracking Transparency permission
    /// - Parameter completion: Callback with the result (true if granted, false if denied/restricted)
    public func requestTrackingPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        // Check if ATT is enabled
        guard isEnabled else {
            print("⚠️ ATT: Not enabled, skipping permission request")
            completion(false)
            return
        }

        // Store completion for later use
        permissionRequestCompletion = completion

        // Check if we should request permission
        guard shouldRequestPermission() else {
            completion(isTrackingAllowed)
            return
        }

        // Mark that we're about to request permission
        hasRequestedPermission = true
        isShowingATTAlert = true

        // Request permission
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.handlePermissionResult(status)
            }
        }
    }
    
    /// Check if tracking is currently allowed
    public var isTrackingAllowed: Bool {
        return trackingStatus == .authorized
    }
    
    /// Check if we can request tracking permission
    public var canRequestTracking: Bool {
        return trackingStatus == .notDetermined
    }
    
    /// Get the current tracking status as a readable string
    public var statusDescription: String {
        switch trackingStatus {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }
    
    /// Get IDFA if available
    public var advertisingIdentifier: String? {
        guard isTrackingAllowed else { return nil }
        let identifier = ASIdentifierManager.shared().advertisingIdentifier
        return identifier.uuidString != "00000000-0000-0000-0000-000000000000" ? identifier.uuidString : nil
    }
    
    // MARK: - Analytics Integration

    /// Update analytics services with tracking permission
    public func updateAnalyticsWithTrackingPermission() {
        guard isEnabled else {
            print("⚠️ ATT: Not enabled, skipping analytics update")
            return
        }

        let isAllowed = isTrackingAllowed

        // Update Mixpanel
        MixpanelManager.shared.updateTrackingPermission(isAllowed)

        // Update Adjust
        AdjustManager.shared.updateTrackingPermission(isAllowed)

        // Track the permission result
        trackPermissionResult(isAllowed)
    }
    
    // MARK: - Private Methods
    
    private func shouldRequestPermission() -> Bool {
        // Don't request if already determined
        guard trackingStatus == .notDetermined else { return false }
        
        // Check if the app version supports ATT (iOS 14.5+)
        guard #available(iOS 14.5, *) else { return false }
        
        return true
    }
    
    private func updateTrackingStatus() {
        if #available(iOS 14.5, *) {
            trackingStatus = ATTrackingManager.trackingAuthorizationStatus
        } else {
            // For older iOS versions, assume tracking is allowed
            trackingStatus = .authorized
        }
    }
    
    private func observeStatusChanges() {
        // Observe app state changes to update tracking status
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateTrackingStatus()
            }
        }
    }
    
    private func handlePermissionResult(_ status: ATTrackingManager.AuthorizationStatus) {
        // Update tracking status
        trackingStatus = status
        isShowingATTAlert = false
        
        // Update analytics services
        updateAnalyticsWithTrackingPermission()
        
        // Call completion
        let granted = status == .authorized
        permissionRequestCompletion?(granted)
        permissionRequestCompletion = nil
        
        // Store that we've requested permission
        UserDefaults.standard.set(true, forKey: "ATTPermissionRequested")
        
        print("📊 ATT Permission Result: \(statusDescription)")
    }
    
    private func trackPermissionResult(_ granted: Bool) {
        // Track permission result with analytics
        MixpanelManager.shared.track(
            event: .attPermissionRequested,
            properties: [
                "granted": granted,
                "status": statusDescription,
                "idfa_available": advertisingIdentifier != nil
            ]
        )
        
        // Track with Adjust
        AdjustManager.shared.trackATTPermission(granted: granted, status: statusDescription)
    }
}

// MARK: - SwiftUI Integration
public struct ATTPermissionView: View {
    @StateObject private var attManager = ATTManager.shared
    let onCompletion: (Bool) -> Void
    private let configuration: TangentSwiftSDK.ATTConfiguration
    
    public init(onCompletion: @escaping (Bool) -> Void, configuration: TangentSwiftSDK.ATTConfiguration? = nil) {
        self.onCompletion = onCompletion
        self.configuration = configuration ?? TangentSwiftSDK.ATTConfiguration()
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "shield.checkered")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.blue)
            
            // Title
            Text(configuration.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            // Description
            Text(configuration.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            // Benefits
            VStack(alignment: .leading, spacing: 12) {
                ForEach(configuration.benefits.indices, id: \.self) { index in
                    let benefit = configuration.benefits[index]
                    benefitRow(icon: benefit.icon, text: benefit.text)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    attManager.requestTrackingPermission { granted in
                        onCompletion(granted)
                    }
                }) {
                    Text(configuration.allowButtonText)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    onCompletion(false)
                }) {
                    Text(configuration.denyButtonText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Preview
#if DEBUG
public struct ATTPermissionView_Previews: PreviewProvider {
    public static var previews: some View {
        ATTPermissionView { granted in
            print("Permission result: \(granted)")
        }
        .preferredColorScheme(.dark)
    }
}
#endif