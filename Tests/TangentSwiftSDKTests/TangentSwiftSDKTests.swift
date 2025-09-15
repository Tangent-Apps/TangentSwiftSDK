import XCTest
@testable import TangentSwiftSDK

final class TangentSwiftSDKTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSDKInitialization() throws {
        let config = TangentSwiftSDK.Configuration(
            mixpanelToken: "test-token",
            adjustAppToken: "test-adjust-token",
            revenueCatAPIKey: "test-rc-key",
            superwallAPIKey: "test-sw-key"
        )
        
        // This would normally initialize the SDK
        // TangentSwiftSDK.shared.initialize(with: config)
        
        // For testing, we just verify the configuration is created properly
        XCTAssertEqual(config.mixpanelToken, "test-token")
        XCTAssertEqual(config.adjustAppToken, "test-adjust-token")
        XCTAssertEqual(config.revenueCatAPIKey, "test-rc-key")
        XCTAssertEqual(config.superwallAPIKey, "test-sw-key")
    }
    
    func testAnalyticsEventNames() throws {
        XCTAssertEqual(AnalyticsEvent.appLaunched.rawValue, "App Launched")
        XCTAssertEqual(AnalyticsEvent.sessionStart.rawValue, "Session Start")
        XCTAssertEqual(AnalyticsEvent.purchaseCompleted.rawValue, "Purchase Completed")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
}