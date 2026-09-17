import SwiftUI
import FirebaseCore
import FirebaseAuth
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
                .onAppear {
                    account.onDeleteLocalAccount = { [weak store] uid in try store?.eraseAccountKitchen(uid) }
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
                    if phase == .active { store.foreground = true }
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
        FirebaseApp.configure()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--auth-emulator") {
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            try? Auth.auth().signOut()
        }
        #endif
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
