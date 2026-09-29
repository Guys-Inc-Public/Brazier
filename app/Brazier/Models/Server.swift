import Foundation

/// One Grafana a person watches. Secrets are never here: the refresh token, ID token
/// and service-account token live in the keychain under the server's id.
struct Server: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var url: URL
    var auth: AuthMode

    enum AuthMode: Codable, Hashable {
        /// Sign in at the instance's own identity provider; Grafana trusts the ID token (auth.jwt).
        case oidc(issuer: URL, clientID: String)
        /// A Grafana service-account token the person pastes, for instances without SSO.
        case token
    }

    init(id: UUID = UUID(), name: String, url: URL, auth: AuthMode) {
        self.id = id
        self.name = name
        self.url = url
        self.auth = auth
    }

    var host: String { url.host ?? url.absoluteString }

    var authWord: String {
        switch auth {
        case .oidc: return "OIDC"
        case .token: return "TOKEN"
        }
    }

    var isOIDC: Bool {
        if case .oidc = auth { return true }
        return false
    }
}

/// The Guys Inc estate, offered as a one-tap preset. Any other Grafana is typed in.
enum EstatePreset {
    static let name = "Guys Inc estate"
    static let grafana = URL(string: "https://grafana.gicloud.org")!
    static let issuer = URL(string: "https://keystone.gicloud.org/application/o/brazier/")!
    static let clientID = "vgG1mB1fiCSYrsS2Y7zK7CMd5GdlE5USYP5tIqJh"
    static let relay = URL(string: "https://brazier.gicloud.org")!
}
