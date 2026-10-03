import Foundation

enum RecipeShareLink {
    static let host = "oui-chef-dev-20260914.web.app"
    static func id(from url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.port == nil else { return nil }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        let id: String
        if parts.scheme == "https", parts.host == host, path.count == 3, path[1] == "r" {
            id = String(path[2])
        } else if parts.scheme == "ouichef", parts.host == "recipe", path.count == 2 {
            id = String(path[1])
        } else { return nil }
        return id.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) == nil ? nil : id
    }
}
