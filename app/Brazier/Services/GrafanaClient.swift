import Foundation

enum GrafanaError: LocalizedError {
    case http(Int, String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "HTTP \(status)\(body.isEmpty ? "" : ": \(body)")"
        case .transport(let why): return why
        case .decoding(let why): return "Unreadable answer: \(why)"
        }
    }
}

/// A thin client over Grafana's HTTP API. No caching, no local store: every screen reads the server.
/// Cookies are never stored by the session: the credential rides as one header, set on purpose,
/// and a rotated session cookie goes straight to the keychain. Redirects are followed inside the
/// server's origin only, so a credential never travels to a sign-in host.
struct GrafanaClient {
    let server: Server
    let credentials: CredentialProvider

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    // MARK: Endpoints

    /// Public on Grafana itself; behind an auth proxy it needs the cookie jar like everything else.
    func health() async throws -> GrafanaHealth {
        var withSession = false
        if server.isSession { withSession = await credentials.isSignedIn(server) }
        return try await get("api/health", authenticated: withSession)
    }

    func user() async throws -> GrafanaUser {
        try await get("api/user")
    }

    func alerts() async throws -> [GrafanaAlert] {
        let envelope: AlertsEnvelope = try await get("api/prometheus/grafana/api/v1/alerts")
        return envelope.data.alerts
    }

    func silences() async throws -> [Silence] {
        try await get("api/alertmanager/grafana/api/v2/silences")
    }

    func createSilence(_ silence: NewSilence) async throws -> SilenceCreated {
        try await post("api/alertmanager/grafana/api/v2/silences", body: silence)
    }

    func search(_ query: String) async throws -> [SearchHit] {
        var items = [URLQueryItem(name: "type", value: "dash-db"), URLQueryItem(name: "limit", value: "200")]
        if !query.isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        return try await get("api/search", query: items)
    }

    /// A request for a page in the web view, carrying the credential on the first load.
    func pageRequest(path: String) async throws -> URLRequest {
        var request = URLRequest(url: server.url.appending(path: path))
        try await credentials.credential(for: server).apply(to: &request)
        return request
    }

    // MARK: Transport

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> T {
        let data = try await send("GET", path, query: query, body: nil, authenticated: authenticated)
        return try decode(data)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let data = try await send("POST", path, query: [], body: try JSONEncoder().encode(body), authenticated: true)
        return try decode(data)
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, authenticated: Bool, retried: Bool = false) async throws -> Data {
        var components = URLComponents(url: server.url.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            try await credentials.credential(for: server, forceRefresh: retried).apply(to: &request)
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await Self.session.data(for: request, delegate: SameOriginRedirects(origin: server.origin)) }
        catch let error as URLError { throw GrafanaError.transport(ServerProbe.explain(error)) }
        catch { throw GrafanaError.transport(error.localizedDescription) }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if let http, server.isSession { await keepRotatedSession(from: http, url: request.url!) }
        if authenticated, server.isSession, let http, Self.wantsFreshSignIn(http, origin: server.origin) {
            // Sent to a sign-in page, or handed a page instead of JSON: an auth proxy's session lapsed.
            await credentials.endSession(server)
            throw AuthError.sessionEnded
        }
        if status == 401, authenticated {
            if server.isSession {
                await credentials.endSession(server)
                throw AuthError.sessionEnded
            }
            if !retried, server.isOIDC {
                return try await send(method, path, query: query, body: body, authenticated: authenticated, retried: true)
            }
        }
        guard (200..<300).contains(status) else {
            let snippet = String(data: data.prefix(160), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GrafanaError.http(status, snippet)
        }
        return data
    }

    /// A redirect away from Grafana's origin, or a 200 that is a page rather than JSON, is a gate in
    /// front of Grafana asking for a sign-in; Grafana's own API answers 401 instead.
    static func wantsFreshSignIn(_ http: HTTPURLResponse, origin: String) -> Bool {
        if let final = http.url, ServerAddress.origin(of: final) != origin { return true }
        if (300..<400).contains(http.statusCode) { return true }
        if http.statusCode == 200 {
            let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            return !type.isEmpty && !type.contains("json")
        }
        return false
    }

    /// Grafana answers with Set-Cookie when it rotates the session; the new value is kept at once.
    private func keepRotatedSession(from http: HTTPURLResponse, url: URL) async {
        let fields = ServerProbe.headerFields(http)
        guard fields.keys.contains(where: { $0.lowercased() == "set-cookie" }) else { return }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard let session = cookies.first(where: { $0.name == "grafana_session" }), !session.value.isEmpty else { return }
        let expiry = cookies.first { $0.name == "grafana_session_expiry" }?.value
        await credentials.rotateSession(cookie: session.value, expiry: expiry, for: server)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GrafanaError.decoding(String(describing: error).prefix(120).description) }
    }
}
