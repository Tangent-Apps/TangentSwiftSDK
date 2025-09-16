import Foundation
import SuperwallKit

// MARK: - Superwall Manager
@MainActor
public final class SuperwallManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    public static let shared = SuperwallManager()
    
    // MARK: - Properties
    @Published public private(set) var isInitialized = false
    
    // MARK: - Initialization
    private override init() {
        super.init()
    }
    
    // MARK: - Configuration
    public func initialize(apiKey: String) {
        Superwall.configure(apiKey: apiKey)
        Superwall.shared.delegate = self
        
        isInitialized = true
        print("✅ Superwall: Configured successfully with API key")
    }
    
    // MARK: - Paywall Management
    public func register(event: String, params: [String: Any] = [:]) {
        Superwall.shared.register(event: event, params: params)
        print("📱 Superwall: Registered event - \(event)")
    }
    
    public func setUserAttributes(_ attributes: [String: Any]) {
        Superwall.shared.setUserAttributes(attributes)
        print("👤 Superwall: User attributes set")
    }
    
    public func identify(userId: String) {
        Superwall.shared.identify(userId: userId)
        print("👤 Superwall: User identified - \(userId)")
    }
    
    public func reset() {
        Superwall.shared.reset()
        print("🔄 Superwall: User reset")
    }
}

// MARK: - SuperwallDelegate
extension SuperwallManager: SuperwallDelegate {
    nonisolated public func handleSuperwallEvent(withInfo eventInfo: SuperwallEventInfo) {
        print("📱 Superwall Event: \(eventInfo.event)")
    }
    
    nonisolated public func handleLog(level: String, scope: String, message: String?, info: [String : Any]?, error: Error?) {
        #if DEBUG
        print("📱 Superwall Log [\(level)]: \(message ?? "")")
        #endif
    }
}