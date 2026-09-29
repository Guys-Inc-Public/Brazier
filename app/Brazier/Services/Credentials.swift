import Foundation

enum Credential {
    case jwt(String)
    case bearer(String)

    func apply(to request: inout URLRequest) {
        switch self {
        case .jwt(let token): request.setValue(token, forHTTPHeaderField: "X-JWT-Assertion")
        case .bearer(let token): request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

enum AuthError: LocalizedError {
    case signedOut
    case noIDToken

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Not signed in to this server"
        case .noIDToken: return "The provider issued no ID token"
        }
    }
}

/// Hands out the credential a request needs, refreshing an OIDC session when its ID token is about to lapse.
actor CredentialProvider {
    func credential(for server: Server, forceRefresh: Bool = false) async throws -> Credential {
        switch server.auth {
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

    func forget(_ server: Server) {
        Keychain.delete(SecretKey.refreshToken(server.id))
        Keychain.delete(SecretKey.idToken(server.id))
        Keychain.delete(SecretKey.apiToken(server.id))
    }

    func isSignedIn(_ server: Server) -> Bool {
        switch server.auth {
        case .token: return Keychain.get(SecretKey.apiToken(server.id)) != nil
        case .oidc: return Keychain.get(SecretKey.refreshToken(server.id)) != nil
        }
    }

    /// Who the ID token says we are, for the account corner.
    func subjectName(_ server: Server) -> String? {
        guard server.isOIDC, let idToken = Keychain.get(SecretKey.idToken(server.id)) else { return nil }
        return JWT.claim("preferred_username", in: idToken) ?? JWT.claim("email", in: idToken)
    }
}
