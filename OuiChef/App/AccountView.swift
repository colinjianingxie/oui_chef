import AuthenticationServices
import GoogleSignIn
import SwiftUI

struct AccountView: View {
    @Bindable var account = AccountSession.shared
    @State private var method: String?
    @State private var intent: AccountSession.Intent = .signIn
    @State private var createAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var phone = "+1"
    @State private var code = ""
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(intent == .deleteAccount ? "Confirm it’s you." : intent == .link ? "One kitchen.\nMore ways in." : "Your kitchen.\nYour way.")
                        .font(Theme.serif(36)).accessibilityAddTraits(.isHeader)
                    if intent == .deleteAccount {
                        Text("Sign in again to delete this account, its private completed dishes and photos, and its cooking data on this iPhone. Voice usage and security records are retained in this development preview.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if intent == .link {
                        Text("The method you choose will be linked to this account, including any email or phone number it shares. Your existing sign-in methods will keep working.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Save recipes from anywhere and make them your own. Your cookbook and cooking memories stay private.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let method {
                        if method == "Email" { emailForm } else { phoneForm }
                    } else if account.accountID != nil && intent == .signIn {
                        signedIn
                    } else {
                        providerChoices
                    }
                    if account.busy { ProgressView().frame(maxWidth: .infinity) }
                    if let error = account.error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("account-error") }
                    if let notice = account.notice { Text(notice).font(.subheadline).foregroundStyle(Theme.green).accessibilityIdentifier("account-notice") }
                }.padding(24)
            }
            .scrollBounceBehavior(.basedOnSize).background(Theme.cream).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Oui Chef").font(Theme.serif(24)) }
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.disabled(account.busy) }
                ToolbarItem(placement: .topBarLeading) {
                    if method != nil || intent != .signIn {
                        Button("Back") { method = nil; intent = .signIn; password = ""; account.error = nil }.disabled(account.busy)
                    }
                }
            }
            .interactiveDismissDisabled(account.busy)
            .onChange(of: account.accountID) { _, id in
                if id != nil && intent == .signIn { method = nil; password = "" }
                if id == nil { method = nil; intent = .signIn; password = "" }
            }
            .alert("Delete your account?", isPresented: $confirmDelete) {
                Button("Continue", role: .destructive) { intent = .deleteAccount }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You’ll verify your sign-in before anything is deleted. This cannot be undone.") }
        }
    }
    private func offers(_ provider: String) -> Bool {
        if intent == .deleteAccount {
            if account.providers.contains("apple.com") { return provider == "apple.com" }
            return account.providers.contains(provider)
        }
        return intent != .link || !account.providers.contains(provider)
    }
    private var providerChoices: some View {
        VStack(spacing: 16) {
            if offers("apple.com") {
                SignInWithAppleButton(.continue) { request in account.prepareApple(request) } onCompletion: { result in
                    Task { await account.completeApple(result, intent: intent) }
                }.signInWithAppleButtonStyle(.black).frame(height: 50)
                    .disabled(account.busy || !account.appleConfigured)
                if !account.appleConfigured { Text("Apple sign-in is coming soon.").font(.caption).foregroundStyle(.secondary) }
            }
            if offers("google.com") {
                GoogleLoginButton { Task { await account.google(intent: intent) } }
                    .frame(height: 50).disabled(account.busy || !account.googleConfigured)
                    .accessibilityLabel("Continue with Google")
                if !account.googleConfigured { Text("Google sign-in is coming soon.").font(.caption).foregroundStyle(.secondary) }
            }
            if offers("password") {
                Button { method = "Email"; email = account.email; createAccount = false } label: { Label("Continue with email", systemImage: "envelope") }
                    .buttonStyle(FilledButton()).disabled(account.busy)
            }
            if offers("phone") {
                Button { method = "Phone" } label: { Label("Continue with phone", systemImage: "phone") }
                    .buttonStyle(FilledButton()).disabled(account.busy)
            }
        }
    }
    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(account.name, systemImage: "person.crop.circle.fill").font(.headline)
            Text("Signed in with \(account.providers.map { ["google.com": "Google", "apple.com": "Apple", "password": "email", "phone": "phone"][$0] ?? $0 }.joined(separator: ", ")).")
                .font(.subheadline).foregroundStyle(.secondary)
            if account.providers.contains("password") && !account.emailVerified {
                Button("Send verification email") { Task { await account.verifyEmail() } }.disabled(account.busy)
            }
            Button("Add a sign-in method") { intent = .link }.disabled(account.busy)
            Text("Your cookbook, cooking preferences, completed dishes and photos belong to this account. Cooking progress is also saved on this iPhone.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Sign out") { Task { await account.signOut() } }.disabled(account.busy)
            Button("Delete account", role: .destructive) { confirmDelete = true }.disabled(account.busy)
        }.kitchenCard()
    }
    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            if intent == .signIn {
                Picker("Email access", selection: $createAccount) {
                    Text("Sign in").tag(false); Text("Create account").tag(true)
                }.pickerStyle(.segmented)
            }
            TextField("Email address", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            if createAccount { Text("Use at least 8 characters.").font(.caption).foregroundStyle(.secondary) }
            Button(intent == .deleteAccount ? "Verify and delete account" : intent == .link ? "Link email" : createAccount ? "Create account" : "Sign in") {
                Task { await account.emailSignIn(email: email, password: password, create: createAccount && intent == .signIn, intent: intent) }
            }.buttonStyle(FilledButton()).disabled(account.busy || email.isEmpty || password.isEmpty).accessibilityIdentifier("email-submit")
            if !createAccount {
                Button("Forgot password?") { Task { await account.resetPassword(email: email) } }.disabled(account.busy)
            }
        }
    }
    private var phoneForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            if account.phoneCodeSent {
                TextField("Six-digit code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).textFieldStyle(.roundedBorder)
                Button(intent == .deleteAccount ? "Verify and delete account" : "Verify code") {
                    Task { await account.confirmPhoneCode(code, intent: intent) }
                }.buttonStyle(FilledButton()).disabled(account.busy || code.count != 6)
                Button("Use a different number") { account.resetPhoneCode(); code = "" }.disabled(account.busy)
            } else {
                TextField("Phone number with country code", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).textFieldStyle(.roundedBorder)
                Text("Phone sign-in currently supports US numbers. Google processes your number for verification and abuse prevention. A verification text will be sent; standard SMS rates may apply.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Send verification code") { Task { await account.sendPhoneCode(phone) } }
                    .buttonStyle(FilledButton()).disabled(account.busy)
            }
        }
    }
}

private struct GoogleLoginButton: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> GIDSignInButton {
        let button = GIDSignInButton()
        button.style = .wide
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }
    func updateUIView(_ view: GIDSignInButton, context: Context) {
        view.isEnabled = context.environment.isEnabled
        context.coordinator.action = action
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
