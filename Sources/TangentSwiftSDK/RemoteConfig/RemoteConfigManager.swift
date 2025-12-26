//
//  RemoteConfigManager.swift
//  TangentSwiftSDK
//
//  Firebase Remote Config Manager for controlling feature flags
//

import Foundation
import FirebaseRemoteConfig

// MARK: - Remote Config Manager

@MainActor
public final class RemoteConfigManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = RemoteConfigManager()

    // MARK: - Published Properties

    /// Whether Superwall is enabled based on remote config and environment
    @Published public private(set) var superwallEnabled: Bool = false

    /// Whether the config has been fetched and loaded
    @Published public private(set) var isConfigLoaded: Bool = false

    // MARK: - Dependencies

    private var remoteConfig: RemoteConfig?

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    /// Configures the Remote Config manager. Call this after FirebaseApp.configure()
    public func configure() {
        self.remoteConfig = RemoteConfig.remoteConfig()
        configureSettings()
        print("✅ RemoteConfigManager: Configured")
    }

    private func configureSettings() {
        guard let remoteConfig = remoteConfig else { return }

        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0 // No caching in debug
        #else
        settings.minimumFetchInterval = 3600 // 1 hour in production
        #endif
        remoteConfig.configSettings = settings
    }

    // MARK: - Public API

    /// Fetches remote config from Firebase and updates superwallEnabled
    public func fetchConfig() async {
        guard let remoteConfig = remoteConfig else {
            print("❌ RemoteConfigManager: Not configured. Call configure() first.")
            return
        }

        print("📡 RemoteConfigManager: Starting fetch and activate...")

        do {
            let status = try await remoteConfig.fetchAndActivate()

            switch status {
            case .successFetchedFromRemote:
                print("✅ RemoteConfigManager: Fetched new values from remote")
            case .successUsingPreFetchedData:
                print("✅ RemoteConfigManager: Using pre-fetched cached data")
            case .error:
                print("❌ RemoteConfigManager: Error fetching config")
            @unknown default:
                print("⚠️ RemoteConfigManager: Unknown status")
            }

            await updateSuperwallEnabled()
            isConfigLoaded = true

        } catch {
            print("❌ RemoteConfigManager: Fetch failed - \(error.localizedDescription)")
            isConfigLoaded = true // Mark as loaded even on failure to prevent blocking
        }
    }

    /// Gets a boolean value from remote config
    /// - Parameter key: The key to fetch
    /// - Returns: The boolean value for the key
    public func getBool(forKey key: String) -> Bool {
        return remoteConfig?.configValue(forKey: key).boolValue ?? false
    }

    /// Gets a string value from remote config
    /// - Parameter key: The key to fetch
    /// - Returns: The string value for the key
    public func getString(forKey key: String) -> String? {
        return remoteConfig?.configValue(forKey: key).stringValue
    }

    /// Gets a number value from remote config
    /// - Parameter key: The key to fetch
    /// - Returns: The number value for the key
    public func getNumber(forKey key: String) -> NSNumber? {
        return remoteConfig?.configValue(forKey: key).numberValue
    }

    // MARK: - Private Methods

    private func updateSuperwallEnabled() async {
        guard let remoteConfig = remoteConfig else { return }

        let liveEnabled = remoteConfig.configValue(forKey: RemoteConfigKeys.superwallLiveEnabled).boolValue
        let testingEnabled = remoteConfig.configValue(forKey: RemoteConfigKeys.superwallTestingEnabled).boolValue

        // Log raw string values for debugging
        let liveRaw = remoteConfig.configValue(forKey: RemoteConfigKeys.superwallLiveEnabled).stringValue ?? "nil"
        let testingRaw = remoteConfig.configValue(forKey: RemoteConfigKeys.superwallTestingEnabled).stringValue ?? "nil"

        print("📊 RemoteConfigManager: Raw values - live: '\(liveRaw)', testing: '\(testingRaw)'")
        print("📊 RemoteConfigManager: Bool values - live: \(liveEnabled), testing: \(testingEnabled)")

        // Check if running in testing environment (version newer than App Store)
        let isTestingEnvironment = await checkIsTestingEnvironment()

        // Use testing flag if in testing environment, otherwise use live flag
        let newEnabled = isTestingEnvironment ? testingEnabled : liveEnabled

        if isTestingEnvironment {
            print("🧪 RemoteConfigManager: Testing mode → using superwall_testing_enabled = \(testingEnabled)")
        } else {
            print("🌍 RemoteConfigManager: Live mode → using superwall_live_enabled = \(liveEnabled)")
        }

        superwallEnabled = newEnabled
        print("🎯 RemoteConfigManager: superwallEnabled = \(superwallEnabled)")
    }

    private func checkIsTestingEnvironment() async -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        guard let storeVersion = await AppStoreVersionService.shared.fetchLatestVersion(for: bundleId) else {
            print("⚠️ RemoteConfigManager: Could not fetch App Store version, defaulting to live mode")
            return false
        }

        let isNewer = AppStoreVersionService.shared.isCurrentVersionNewer(than: storeVersion, currentVersion: currentVersion)
        print("📱 RemoteConfigManager: Current version: \(currentVersion), Store version: \(storeVersion), isTestingEnv: \(isNewer)")

        return isNewer
    }
}

// MARK: - Remote Config Keys

public enum RemoteConfigKeys {
    public static let superwallLiveEnabled = "superwall_live_enabled"
    public static let superwallTestingEnabled = "superwall_testing_enabled"
}
