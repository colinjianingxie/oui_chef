import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn

@main
struct OuiChefApp: App {
    @UIApplicationDelegateAdaptor(AuthAppDelegate.self) private var delegate
    var body: some Scene { WindowGroup { ChefRootView() } }
}

private struct ChefRootView: View {
    @State private var store: ChefStore
    @State private var account: AccountSession

    init() {
        let account = AccountSession.shared
        let store = ChefStore(accountID: account.accountID)
        _account = State(initialValue: account)
        _store = State(initialValue: store)
    }
    @Environment(\.scenePhase) private var phase

    var body: some View {
            Group {
                if !store.preferences.onboardingComplete && store.catalog != nil {
                    OnboardingView(store: store)
                } else {
                    KitchenView(store: store)
                }
            }
                .task { await store.loadLibrary(); await store.loadDishes(); store.syncDishes() }
                .onAppear {
                    account.onDeleteLocalAccount = { [weak store] uid in try await store?.eraseAccountKitchen(uid) }
                }
                .onOpenURL { url in
                    if !Auth.auth().canHandle(url) { _ = GIDSignIn.sharedInstance.handle(url) }
                }
                .onChange(of: account.accountID) { _, uid in store.switchAccount(uid) }
                .onChange(of: account.identityID) { _, _ in store.voice.refreshTesterID() }
                .tint(Theme.green)
                .preferredColorScheme(.light)
                .alert("A little attention needed", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
                .onChange(of: phase) { _, phase in
                    if phase == .active { store.foreground = true; store.syncDishes() }
                    else if phase == .background { store.background() }
                    UIApplication.shared.isIdleTimerDisabled = phase == .active && store.session != nil && store.preferences.keepScreenAwake
                }
                .onChange(of: store.session?.id) { _, id in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active && id != nil && store.preferences.keepScreenAwake
                }
                .onChange(of: store.preferences.keepScreenAwake) { _, enabled in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active && store.session != nil && enabled
                }
    }
}

final class AuthAppDelegate: NSObject, UIApplicationDelegate {
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
        application.registerForRemoteNotifications()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
        completion(Auth.auth().canHandleNotification(userInfo) ? .noData : .failed)
    }
}
