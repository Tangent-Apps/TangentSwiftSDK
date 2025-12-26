//
//  AppStoreVersionService.swift
//  TangentSwiftSDK
//
//  Service for fetching App Store version information
//

import Foundation

// MARK: - Models

struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreResult]
}

struct AppStoreResult: Decodable {
    let version: String
}

// MARK: - App Store Version Service

@MainActor
public final class AppStoreVersionService {

    // MARK: - Singleton

    public static let shared = AppStoreVersionService()

    private init() {}

    // MARK: - Public API

    /// Fetches the latest version from the App Store for the given bundle ID
    /// - Parameter bundleId: The bundle identifier of the app
    /// - Returns: The version string if found, nil otherwise
    public func fetchLatestVersion(for bundleId: String) async -> String? {
        let urlString = "https://itunes.apple.com/lookup?bundleId=\(bundleId)"
        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            return response.results.first?.version
        } catch {
            print("⚠️ AppStoreVersionService: Failed to fetch App Store version - \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Version Comparison

    /// Checks if the current version is newer than the App Store version
    /// - Parameters:
    ///   - storeVersion: The version from App Store
    ///   - currentVersion: The current app version
    /// - Returns: true if current version is newer (testing/review environment)
    public func isCurrentVersionNewer(than storeVersion: String, currentVersion: String) -> Bool {
        currentVersion.compare(storeVersion, options: .numeric) == .orderedDescending
    }
}
