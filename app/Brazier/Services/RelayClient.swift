import Foundation

enum RelayError: LocalizedError {
    case http(Int, String)
    case rejected
    case notServed(String)
    case unreachable(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "Relay answered \(status)\(body.isEmpty ? "" : ": \(body)")"
        case .rejected: return "Your Grafana rejected the credential the relay checked; sign in again."
        case .notServed(let origin): return "This relay doesn't serve your Grafana; ask its owner to add \(origin)."
        case .unreachable(let why): return "The relay is not reachable: \(why)"
        case .unreadable: return "The relay answered, but not like a Brazier relay."
        }
    }
}

struct RelayHealth: Decodable, Equatable {
    let ok: Bool
    let version: String?
    let apns: Bool?
}

struct RelayRegistration: Decodable {
    let ok: Bool
    let user: String?
    let devices: Int?
}

/// What a relay publishes at /.well-known/brazier: for each Grafana it serves, how its people sign in,
/// if the admin said. The app uses it to offer the right first button.
struct RelayDirectory: Decodable {
    struct Relay: Decodable { let version: String? }
    struct SignIn: Decodable, Equatable {
        let issuer: URL
        let clientId: String
        let name: String?
        var displayName: String { name ?? issuer.host ?? "your provider" }
    }
    struct Entry: Decodable { let signIn: SignIn? }
    let relay: Relay?
    let grafana: [String: Entry]?

    /// The entry for a Grafana origin (scheme://host[:port]), if the relay has one.
    func signIn(for origin: String) -> SignIn? {
        guard let grafana else { return nil }
        let wanted = origin.lowercased()
        let trim = CharacterSet(charactersIn: "/")
        return grafana.first { $0.key.lowercased().trimmingCharacters(in: trim) == wanted }?.value.signIn
    }
}

/// Device registration with the push relay. The relay verifies the caller against their own
/// Grafana: it gets the Grafana's origin and the same credential the app uses, as headers, and
/// files the APNs token under that Grafana login.
struct RelayClient {
    let baseURL: URL

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    private struct Body: Encodable {
        let token: String
        let platform: String
        let environment: String
        let name: String
    }

    func health() async throws -> RelayHealth {
        let request = URLRequest(url: baseURL.appending(path: "health"))
        let data = try await send(request, origin: nil)
        guard let health = try? JSONDecoder().decode(RelayHealth.self, from: data) else { throw RelayError.unreadable }
        return health
    }

    /// The relay's directory; a relay without one (or an older relay) answers 404, which reads as empty.
    func directory() async throws -> RelayDirectory {
        var request = URLRequest(url: baseURL.appending(path: ".well-known/brazier"))
        request.httpMethod = "GET"
        let data: Data
        do { data = try await send(request, origin: nil) }
        catch RelayError.http(404, _) { return RelayDirectory(relay: nil, grafana: nil) }
        guard let directory = try? JSONDecoder().decode(RelayDirectory.self, from: data) else { throw RelayError.unreadable }
        return directory
    }

    func register(token: String, environment: String, name: String, server: Server, credential: Credential) async throws -> RelayRegistration {
        var request = authed("POST", path: "devices", server: server, credential: credential)
        request.httpBody = try JSONEncoder().encode(Body(token: token, platform: "ios", environment: environment, name: name))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await send(request, origin: server.origin)
        guard let result = try? JSONDecoder().decode(RelayRegistration.self, from: data) else { throw RelayError.unreadable }
        return result
    }

    func deregister(token: String, server: Server, credential: Credential) async throws {
        let request = authed("DELETE", path: "devices/\(token)", server: server, credential: credential)
        _ = try await send(request, origin: server.origin)
    }

    private func authed(_ method: String, path: String, server: Server, credential: Credential) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue(server.origin, forHTTPHeaderField: "X-Grafana-Url")
        credential.apply(to: &request)
        return request
    }

    private func send(_ request: URLRequest, origin: String?) async throws -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await Self.session.data(for: request) }
        catch let error as URLError { throw RelayError.unreachable(ServerProbe.explain(error)) }
        catch { throw RelayError.unreachable(error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401: throw RelayError.rejected
        case 403: throw RelayError.notServed(origin ?? baseURL.host ?? "this Grafana")
        default: throw RelayError.http(status, String(data: data.prefix(160), encoding: .utf8) ?? "")
        }
    }
}
