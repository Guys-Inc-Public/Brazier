import Foundation

/// What a request carries to prove who is asking. One header, the same to Grafana and to the relay.
enum Credential {
    case jwt(String)
    case bearer(String)
    /// A complete Cookie header value for the Grafana's host (`grafana_session=…; other=…`): Grafana's
    /// own session, and beside it whatever an auth proxy in front of Grafana set.
    case cookie(String)
    /// Nothing: the Grafana lets anyone read it (anonymous access on).
    case none

    var header: (name: String, value: String)? {
        switch self {
        case .jwt(let token): return ("X-JWT-Assertion", token)
        case .bearer(let token): return ("Authorization", "Bearer \(token)")
        case .cookie(let value): return ("Cookie", value)
        case .none: return nil
        }
    }

    func apply(to request: inout URLRequest) {
        guard let header else { return }
        request.setValue(header.value, forHTTPHeaderField: header.name)
    }
}

enum AuthError: LocalizedError {
    case signedOut
    case sessionEnded
    case noIDToken
    /// Grafana turned a sign-in down, with the reason in plain words.
    case refused(String)
    /// A Grafana read without signing in now wants a sign-in: its anonymous access was turned off.
    case anonymousOff

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Not signed in"
        case .sessionEnded: return "Signed out"
        case .noIDToken: return "The provider issued no ID token"
        case .refused(let why): return why
        case .anonymousOff: return "Anonymous access is off"
        }
    }
}

/// Hands out the credential a request needs: the cookie jar, the pasted token, or an ID token
/// refreshed when it is about to lapse. Every secret goes through the keychain.
actor CredentialProvider {
    /// The refresh in flight per server, so a dozen concurrent requests share one round trip to the
    /// provider. Providers rotate refresh tokens on use; a second refresh with the old one is refused.
    private var refreshing: [UUID: Task<String, Error>] = [:]

    func credential(for server: Server, forceRefresh: Bool = false) async throws -> Credential {
        switch server.auth {
        case .session:
            guard let cookie = Keychain.get(SecretKey.sessionCookie(server.id)) else { throw AuthError.signedOut }
            return .cookie(cookie)
        case .token:
            guard let token = Keychain.get(SecretKey.apiToken(server.id)) else { throw AuthError.signedOut }
            return .bearer(token)
        case .anonymous:
            return .none
        case .oidc(let issuer, let clientID):
            if !forceRefresh,
               let idToken = Keychain.get(SecretKey.idToken(server.id)),
               let exp = JWT.expiry(of: idToken),
               exp > Date().addingTimeInterval(60) {
                return .jwt(idToken)
            }
            if let inFlight = refreshing[server.id] {
                return .jwt(try await inFlight.value)
            }
            // The token may have been refreshed while this caller waited for the actor.
            if !forceRefresh,
               let idToken = Keychain.get(SecretKey.idToken(server.id)),
               let exp = JWT.expiry(of: idToken),
               exp > Date().addingTimeInterval(60) {
                return .jwt(idToken)
            }
            let task = Task<String, Error> { try await self.refreshIDToken(server: server, issuer: issuer, clientID: clientID) }
            refreshing[server.id] = task
            defer { refreshing[server.id] = nil }
            return .jwt(try await task.value)
        }
    }

    private func refreshIDToken(server: Server, issuer: URL, clientID: String) async throws -> String {
        guard let refresh = Keychain.get(SecretKey.refreshToken(server.id)) else { throw AuthError.signedOut }
        let config = try await OIDC.discover(issuer: issuer)
        let tokens: TokenResponse
        do {
            tokens = try await OIDC.refresh(config: config, clientID: clientID, refreshToken: refresh)
        } catch OIDCError.token(let status, _) where status == 400 || status == 401 {
            // invalid_grant: the refresh token lapsed or was revoked at the provider. The sign-in is
            // over; the bay then offers the provider again rather than "read again".
            Keychain.delete(SecretKey.refreshToken(server.id))
            Keychain.delete(SecretKey.idToken(server.id))
            throw AuthError.sessionEnded
        }
        try store(tokens, for: server)
        guard let idToken = tokens.idToken else { throw AuthError.noIDToken }
        return idToken
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

    /// Keeps the whole Cookie header a sign-in produced, not only Grafana's own cookie.
    func storeSession(cookie: String, expiry: String?, for server: Server) throws {
        try Keychain.set(cookie, for: SecretKey.sessionCookie(server.id))
        if let expiry { try Keychain.set(expiry, for: SecretKey.sessionExpiry(server.id)) }
    }

    /// Grafana rotates the session once its token is ten minutes old: the new grafana_session value
    /// goes into the stored header at once, and every other cookie in it stays as it was.
    func rotateSession(cookie: String, expiry: String?, for server: Server) {
        let stored = Keychain.get(SecretKey.sessionCookie(server.id))
        let merged = Self.merging(session: cookie, expiry: expiry, into: stored)
        if merged != stored {
            try? Keychain.set(merged, for: SecretKey.sessionCookie(server.id))
        }
        if let expiry { try? Keychain.set(expiry, for: SecretKey.sessionExpiry(server.id)) }
    }

    /// A fresh grafana_session (and expiry, when Grafana sent one) put into a Cookie header, leaving
    /// any other pair in it, an auth proxy's say, exactly as it was.
    static func merging(session: String, expiry: String?, into header: String?) -> String {
        var pairs = (header ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var replaced = false
        for i in pairs.indices {
            if pairs[i].hasPrefix("grafana_session=") {
                pairs[i] = "grafana_session=\(session)"
                replaced = true
            } else if let expiry, pairs[i].hasPrefix("grafana_session_expiry=") {
                pairs[i] = "grafana_session_expiry=\(expiry)"
            }
        }
        if !replaced { pairs.append("grafana_session=\(session)") }
        return pairs.joined(separator: "; ")
    }

    /// Grafana said 401 to the session, or something in front of it wants a fresh sign-in: it is over.
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
        case .anonymous: return true
        }
    }

    /// Who the ID token says we are; sessions and tokens learn it from /api/user instead.
    func subjectName(_ server: Server) -> String? {
        guard server.isOIDC, let idToken = Keychain.get(SecretKey.idToken(server.id)) else { return nil }
        return JWT.claim("preferred_username", in: idToken) ?? JWT.claim("email", in: idToken)
    }
}
