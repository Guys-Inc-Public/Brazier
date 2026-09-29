import Foundation

/// What a request carries to prove who is asking. One header, the same to Grafana and to the relay.
enum Credential {
    case jwt(String)
    case bearer(String)
    case cookie(String)

    var header: (name: String, value: String) {
        switch self {
        case .jwt(let token): return ("X-JWT-Assertion", token)
        case .bearer(let token): return ("Authorization", "Bearer \(token)")
        case .cookie(let value): return ("Cookie", "grafana_session=\(value)")
        }
    }

    func apply(to request: inout URLRequest) {
        let (name, value) = header
        request.setValue(value, forHTTPHeaderField: name)
    }
}

enum AuthError: LocalizedError {
    case signedOut
    case sessionEnded
    case noIDToken

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Not signed in"
        case .sessionEnded: return "Signed out"
        case .noIDToken: return "The provider issued no ID token"
        }
    }
}

/// Hands out the credential a request needs: the session cookie, the pasted token, or an ID token
/// refreshed when it is about to lapse. Every secret goes through the keychain.
actor CredentialProvider {
    func credential(for server: Server, forceRefresh: Bool = false) async throws -> Credential {
        switch server.auth {
        case .session:
            guard let cookie = Keychain.get(SecretKey.sessionCookie(server.id)) else { throw AuthError.signedOut }
            return .cookie(cookie)
        case .token:
            guard let token = Keychain.get(SecretKey.apiToken(server.id)) else { throw AuthError.signedOut }
            return .bearer(token)
        case .oidc(let issuer, let clientID):
            if !forceRefresh,
               let idToken = Keychain.get(SecretKey.idToken(server.id)),
               let exp = JWT.expiry(of: idToken),
               exp > Date().addingTimeInterval(60) {
                return .jwt(idToken)
            }
            guard let refresh = Keychain.get(SecretKey.refreshToken(server.id)) else { throw AuthError.signedOut }
            let config = try await OIDC.discover(issuer: issuer)
            let tokens = try await OIDC.refresh(config: config, clientID: clientID, refreshToken: refresh)
            try store(tokens, for: server)
            guard let idToken = tokens.idToken else { throw AuthError.noIDToken }
            return .jwt(idToken)
        }
    }

    func store(_ tokens: TokenResponse, for server: Server) throws {
        guard let idToken = tokens.idToken else { throw AuthError.noIDToken }
        try Keychain.set(idToken, for: SecretKey.idToken(server.id))
        if let refresh = tokens.refreshToken {
            try Keychain.set(refresh, for: SecretKey.refreshToken(server.id))
        }
    }

    func storeAPIToken(_ token: String, for server: Server) throws {
        try Keychain.set(token, for: SecretKey.apiToken(server.id))
    }

    func storeSession(cookie: String, expiry: String?, for server: Server) throws {
        try Keychain.set(cookie, for: SecretKey.sessionCookie(server.id))
        if let expiry { try Keychain.set(expiry, for: SecretKey.sessionExpiry(server.id)) }
    }

    /// Grafana rotates the session once its token is ten minutes old: keep the new value at once.
    func rotateSession(cookie: String, expiry: String?, for server: Server) {
        if Keychain.get(SecretKey.sessionCookie(server.id)) != cookie {
            try? Keychain.set(cookie, for: SecretKey.sessionCookie(server.id))
        }
        if let expiry { try? Keychain.set(expiry, for: SecretKey.sessionExpiry(server.id)) }
    }

    /// Grafana said 401 to the session: it is over, the person signs in again.
    func endSession(_ server: Server) {
        Keychain.delete(SecretKey.sessionCookie(server.id))
        Keychain.delete(SecretKey.sessionExpiry(server.id))
    }

    func forget(_ server: Server) {
        SecretKey.all(server.id).forEach(Keychain.delete)
    }

    func isSignedIn(_ server: Server) -> Bool {
        switch server.auth {
        case .session: return Keychain.get(SecretKey.sessionCookie(server.id)) != nil
        case .token: return Keychain.get(SecretKey.apiToken(server.id)) != nil
        case .oidc: return Keychain.get(SecretKey.refreshToken(server.id)) != nil
        }
    }

    /// Who the ID token says we are; sessions and tokens learn it from /api/user instead.
    func subjectName(_ server: Server) -> String? {
        guard server.isOIDC, let idToken = Keychain.get(SecretKey.idToken(server.id)) else { return nil }
        return JWT.claim("preferred_username", in: idToken) ?? JWT.claim("email", in: idToken)
    }
}
