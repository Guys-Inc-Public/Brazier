import Foundation

/// One Grafana a person watches. Secrets are never here: the session cookie, refresh token,
/// ID token and service-account token live in the keychain under the server's id.
struct Server: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var url: URL
    var auth: AuthMode

    enum AuthMode: Codable, Hashable {
        /// Grafana's own sign-in page in a web view; the grafana_session cookie is kept in the keychain and rotated.
        case session
        /// A Grafana service-account token the person pastes, for instances without a browser sign-in.
        case token
        /// Sign in at the instance's identity provider; Grafana trusts the ID token (auth.jwt).
        case oidc(issuer: URL, clientID: String)
    }

    init(id: UUID = UUID(), name: String, url: URL, auth: AuthMode) {
        self.id = id
        self.name = name
        self.url = url
        self.auth = auth
    }

    var host: String { url.host ?? url.absoluteString }

    /// scheme://host[:port], the thing a relay checks against its allow list.
    var origin: String {
        guard let scheme = url.scheme, let host = url.host else { return url.absoluteString }
        if let port = url.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    var authWord: String {
        switch auth {
        case .session: return "SESSION"
        case .token: return "TOKEN"
        case .oidc: return "OIDC"
        }
    }

    var authMethodName: String {
        switch auth {
        case .session: return "Grafana sign-in"
        case .token: return "Service account token"
        case .oidc: return "Single sign-on"
        }
    }

    var isOIDC: Bool {
        if case .oidc = auth { return true }
        return false
    }

    var isSession: Bool {
        if case .session = auth { return true }
        return false
    }
}
