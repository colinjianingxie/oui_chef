import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn
import UserNotifications

@main
struct OuiChefApp: App {
    @UIApplicationDelegateAdaptor(AuthAppDelegate.self) private var delegate
    var body: some Scene { WindowGroup { CompanionRootView().onOpenURL { url in if !Auth.auth().canHandle(url) { _ = GIDSignIn.sharedInstance.handle(url) } } } }
}

final class AuthAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--auth-emulator"),
           let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"), let options = FirebaseOptions(contentsOfFile: path) {
            options.projectID = "demo-ouichef"
            options.storageBucket = "demo-ouichef.appspot.com"
            FirebaseApp.configure(options: options)
        } else { FirebaseApp.configure() }
        #else
        FirebaseApp.configure()
        #endif
        if let group = Bundle.main.object(forInfoDictionaryKey: "OuiChefSharedKeychainGroup") as? String {
            do { try Auth.auth().useUserAccessGroup(group) } catch { print("Shared sign-in unavailable for this build.") }
        }
        let firestoreSettings = Firestore.firestore().settings
        firestoreSettings.cacheSettings = MemoryCacheSettings()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--auth-emulator") {
            Storage.storage().useEmulator(withHost: "127.0.0.1", port: 9199)
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            try? Auth.auth().signOut()
            firestoreSettings.host = "127.0.0.1:8085"
            firestoreSettings.isSSLEnabled = false
        }
        #endif
        Firestore.firestore().settings = firestoreSettings
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
        completion(Auth.auth().canHandleNotification(userInfo) ? .noData : .failed)
    }
}
