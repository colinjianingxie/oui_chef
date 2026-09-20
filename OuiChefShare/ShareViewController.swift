import UIKit
import SwiftUI
import UniformTypeIdentifiers
import FirebaseCore
import FirebaseAuth

@MainActor final class ShareViewController: UIViewController {
    private let model = ShareImportModel()
    override func viewDidLoad() {
        super.viewDidLoad()
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        if let group = Bundle.main.object(forInfoDictionaryKey: "OuiChefSharedKeychainGroup") as? String { try? Auth.auth().useUserAccessGroup(group) }
        model.close = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        let host = UIHostingController(rootView: ShareImportView(model: model))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),host.view.topAnchor.constraint(equalTo: view.topAnchor),host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
        Task {
            for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
                for provider in item.attachments ?? [] {
                    for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                        if let value = try? await provider.loadItem(forTypeIdentifier: type, options: nil) {
                            let text = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
                            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue), let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let url = match.url, ["http","https"].contains(url.scheme ?? "") {
                                model.url = url.absoluteString; return
                            }
                        }
                    }
                }
            }
            model.message = "No recipe link was shared. Try sharing the post’s link, or paste it inside Oui Chef."
        }
    }
}
@MainActor @Observable final class ShareImportModel {
    var url = ""
    var busy = false
    var saved = false
    var message = "Your chef will find the ingredients and turn them into steps you can cook."
    var close: (() -> Void)?
    func submit() async {
        guard !busy, !url.isEmpty else { return }; busy = true; defer { busy = false }
        do {
            guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.xie.ouichef") else { throw NSError(domain: "Share", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sharing needs to be configured for this build. Open Oui Chef and paste this link."]) }
            let directory = group.appendingPathComponent("imports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(UUID().uuidString + ".json")
            try JSONSerialization.data(withJSONObject: ["url": url, "ownerUID": Auth.auth().currentUser?.uid ?? ""]).write(to: file, options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            saved = true
            guard let user = Auth.auth().currentUser, !user.isAnonymous else { message = "Link saved on this iPhone. Open Oui Chef and sign in to finish importing."; return }
            do {
                guard let endpoint = Bundle.main.object(forInfoDictionaryKey: "OuiChefImportURL") as? String, let endpointURL = URL(string: endpoint) else { throw URLError(.badURL) }
                var request = URLRequest(url: endpointURL); request.httpMethod = "POST"; request.timeoutInterval = 12
                request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["url": url])
                let (_,response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try FileManager.default.removeItem(at: file)
                message = "Added to your kitchen. Your chef is working on it—you can find it in Oui Chef."
            } catch { message = "Link saved on this iPhone. Open Oui Chef to finish importing when connected." }
        } catch { message = error.localizedDescription }
    }
}
private struct ShareImportView: View {
    @Bindable var model: ShareImportModel
    let olive = Color(red: 0.27, green: 0.31, blue: 0.20)
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { Text("OUI CHEF").font(.system(size: 11, weight: .semibold)).tracking(3); Spacer(); Button { model.close?() } label: { Image(systemName: "xmark").frame(width: 44,height: 44) }.accessibilityLabel("Close") }
            Image(systemName: model.saved ? "checkmark.circle" : "fork.knife.circle").font(.system(size: 50, weight: .ultraLight))
            Text(model.saved ? "In your kitchen." : "Something delicious\nis coming.").font(.system(size: 34, design: .serif))
            Text(model.url).font(.caption).lineLimit(2).foregroundStyle(.secondary)
            Text(model.message).font(.subheadline).lineSpacing(5)
            Spacer(minLength: 15)
            Button { if model.saved { model.close?() } else { Task { await model.submit() } } } label: {
                HStack { if model.busy { ProgressView().tint(.white) }; Text(model.saved ? "Done" : "Add to my cookbook") }.frame(maxWidth: .infinity).padding(17).foregroundStyle(.white).background(olive,in: Capsule())
            }.disabled(model.busy || (!model.saved && model.url.isEmpty))
        }.padding(28).background(Color(red: 0.97, green: 0.953, blue: 0.918)).foregroundStyle(olive).tint(olive)
    }
}
