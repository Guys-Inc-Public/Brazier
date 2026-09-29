import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct OIDCConfiguration: Decodable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let endSessionEndpoint: URL?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case endSessionEndpoint = "end_session_endpoint"
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let idToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum OIDCError: LocalizedError {
    case discovery(String)
    case couldNotStart
    case cancelled
    case badCallback
    case stateMismatch
    case token(Int, String)
    case noIDToken

    var errorDescription: String? {
        switch self {
        case .discovery(let why): return "Discovery failed: \(why)"
        case .couldNotStart: return "The sign-in window could not open"
        case .cancelled: return "Sign-in cancelled"
        case .badCallback: return "The provider sent no code back"
        case .stateMismatch: return "The provider answered a different request"
        case .token(let status, let body): return "Token endpoint answered \(status): \(body)"
        case .noIDToken: return "The provider issued no ID token; check the openid scope"
        }
    }
}

/// Authorization code with PKCE as a public client. The provider is any OIDC issuer.
enum OIDC {
    static let redirectURI = "brazier://auth/callback"
    static let callbackScheme = "brazier"
    static let scopes = "openid profile email offline_access"

    static func discover(issuer: URL) async throws -> OIDCConfiguration {
        let url = issuer.appending(path: ".well-known/openid-configuration")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OIDCError.discovery("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) from \(url.host ?? "")")
        }
        do { return try JSONDecoder().decode(OIDCConfiguration.self, from: data) }
        catch { throw OIDCError.discovery("unreadable document") }
    }

    @MainActor
    static func signIn(issuer: URL, clientID: String) async throws -> TokenResponse {
        let config = try await discover(issuer: issuer)
        let verifier = PKCE.verifier()
        let state = PKCE.verifier()
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        let callback = try await WebAuth.run(url: components.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw OIDCError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw OIDCError.badCallback }
        return try await tokenRequest(config.tokenEndpoint, form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    static func refresh(config: OIDCConfiguration, clientID: String, refreshToken: String) async throws -> TokenResponse {
        try await tokenRequest(config.tokenEndpoint, form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
    }

    private static func tokenRequest(_ endpoint: URL, form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\(PKCE.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw OIDCError.token(status, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// Wraps ASWebAuthenticationSession in async/await and keeps it alive while it runs.
@MainActor
final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let shared = WebAuth()
    private var session: ASWebAuthenticationSession?

    static func run(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: OIDC.callbackScheme) { callback, error in
                if let error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    continuation.resume(throwing: code == .canceledLogin ? OIDCError.cancelled : error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: OIDCError.badCallback)
                }
            }
            session.presentationContextProvider = shared
            session.prefersEphemeralWebBrowserSession = false
            shared.session = session
            if !session.start() {
                continuation.resume(throwing: OIDCError.couldNotStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

enum JWT {
    /// The `exp` claim, without verifying anything: the server verifies, the app only schedules refreshes.
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func claim(_ name: String, in token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object[name] as? String
    }
}
