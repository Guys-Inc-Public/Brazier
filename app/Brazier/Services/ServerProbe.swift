import Foundation

/// The address a person typed, made into the URL the app will use, or a plain reason it cannot be.
enum ServerAddress {
    enum Check: Equatable {
        case url(URL)
        case problem(String)
    }

    static func normalise(_ text: String) -> Check {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return .problem("Enter your Grafana's address.") }
        if !raw.contains("://") { raw = "https://" + raw }
        guard var components = URLComponents(string: raw), let host = components.host?.lowercased(), !host.isEmpty else {
            return .problem("That does not look like an address. Try https://grafana.example.com.")
        }
        let scheme = (components.scheme ?? "https").lowercased()
        let local = ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasSuffix(".local")
        if scheme == "http", !local {
            return .problem("Brazier talks to Grafana over https only; plain http is allowed for localhost.")
        }
        if scheme != "http", scheme != "https" {
            return .problem("The address must start with https://.")
        }
        components.scheme = scheme
        components.host = host
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/login") { path.removeLast("/login".count) }
        components.path = path
        guard let url = components.url else { return .problem("That does not look like an address.") }
        return .url(url)
    }
}

extension ServerAddress {
    /// scheme://host[:port], what a relay files a Grafana under.
    static func origin(of url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else { return url.absoluteString }
        if let port = url.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }
}

/// Follows redirects inside one origin only. A redirect that leaves it is handed back as the 3xx answer
/// itself, so a credential never travels to a sign-in host, and the caller can read where it was sent.
final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    let origin: String

    init(origin: String) { self.origin = origin }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, ServerAddress.origin(of: url) == origin { completionHandler(request) } else { completionHandler(nil) }
    }
}

/// One GET each, before a server exists: is there a Grafana at this address, how does it sign in,
/// and who am I on it.
enum ServerProbe {
    enum Outcome: Equatable {
        case ok(version: String, database: String)
        /// Reachable, but something in front of Grafana asks for a sign-in first (an auth proxy such as
        /// Authelia, oauth2-proxy or Cloudflare Access). Carries the host it sends people to, when known.
        case fronted(String)
        case failed(String)

        var isOK: Bool {
            if case .ok = self { return true }
            return false
        }

        var isFronted: Bool {
            if case .fronted = self { return true }
            return false
        }

        /// Something worth signing in to is there, with or without a gate in front.
        var isReachable: Bool { isOK || isFronted }
    }

    /// What the Grafana's own sign-in page offers, read from the page nobody needs a session to see.
    /// Every field is a best effort; unknown is `passwordForm == nil` and nothing else set.
    struct SignInShape: Equatable {
        /// True when Grafana shows its username-and-password form; false when it is turned off or a
        /// proxy answers instead; nil when the page could not be read.
        var passwordForm: Bool?
        /// The display names of the single sign-on providers Grafana lists, sorted.
        var providers: [String] = []
        var anonymous = false
        /// Something in front of Grafana answered instead of Grafana.
        var fronted = false
        /// Where the sign-in page sent us when it left Grafana's origin.
        var ssoHost: String?
    }

    /// No cookies are stored or sent by themselves; a credential is a header, set on purpose.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    /// The same, for the one page read: Grafana's sign-in page.
    static let pageSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["Accept": "text/html"]
        return URLSession(configuration: config)
    }()

    // MARK: Health

    static func health(_ url: URL) async -> Outcome {
        let origin = ServerAddress.origin(of: url)
        var request = URLRequest(url: url.appending(path: "api/health"))
        request.httpMethod = "GET"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: SameOriginRedirects(origin: origin))
        } catch let error as URLError {
            return .failed(explain(error))
        } catch {
            return .failed(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        return classify(status: http?.statusCode ?? 0, headers: http.map(headerFields) ?? [:], finalURL: http?.url, data: data, origin: origin)
    }

    /// What an answer to /api/health means. Pure, so the fixtures below can exercise every branch.
    static func classify(status: Int, headers: [String: String], finalURL: URL?, data: Data, origin: String) -> Outcome {
        if let finalURL, ServerAddress.origin(of: finalURL) != origin {
            return .fronted(finalURL.host ?? "")
        }
        if (300..<400).contains(status) {
            let location = headers.first { $0.key.lowercased() == "location" }?.value ?? ""
            let host = URL(string: location)?.host ?? ""
            return .fronted(host)
        }
        switch status {
        case 200:
            if let health = try? JSONDecoder().decode(GrafanaHealth.self, from: data) {
                return .ok(version: health.version, database: health.database)
            }
            // A page where the API should be: a sign-in in front of Grafana, most likely.
            return .fronted("")
        case 401, 403:
            return .fronted("")
        case 404:
            return .failed("Nothing at /api/health there. The address must be Grafana's root, like https://grafana.example.com.")
        case 502, 503, 504:
            return .failed("Grafana is not answering behind that address (HTTP \(status)). Is it running?")
        default:
            return .failed("Unexpected answer from that address: HTTP \(status).")
        }
    }

    static func explain(_ error: URLError) -> String {
        switch error.code {
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed, .clientCertificateRejected:
            return "The certificate is not trusted on this phone. A self-signed certificate needs its profile installed and trusted in Settings first."
        case .cannotFindHost, .dnsLookupFailed:
            return "Nothing by that name. Check the address, or whether it only resolves on your VPN."
        case .cannotConnectToHost, .timedOut, .networkConnectionLost, .notConnectedToInternet:
            return "Not reachable from here. Check the address, and whether it needs your VPN or tunnel."
        case .appTransportSecurityRequiresSecureConnection:
            return "Plain http is only allowed for localhost; use https."
        default:
            return error.localizedDescription
        }
    }

    // MARK: Sign-in shape

    /// Reads Grafana's sign-in page (`/login?disableAutoLogin=true`, which shows the page even when
    /// Grafana would otherwise bounce straight to its provider) for the settings the page itself uses:
    /// whether the password form is on, which providers it lists, whether anonymous viewing is on.
    /// Never throws; a page that cannot be read leaves the shape unknown.
    static func shape(_ url: URL, fronted: Bool) async -> SignInShape {
        let origin = ServerAddress.origin(of: url)
        var unknown = SignInShape()
        unknown.fronted = fronted
        guard var components = URLComponents(url: url.appending(path: "login"), resolvingAgainstBaseURL: false) else { return unknown }
        components.queryItems = [URLQueryItem(name: "disableAutoLogin", value: "true")]
        guard let pageURL = components.url else { return unknown }
        var request = URLRequest(url: pageURL)
        request.httpMethod = "GET"
        guard let (data, response) = try? await pageSession.data(for: request, delegate: SameOriginRedirects(origin: origin)),
              let http = response as? HTTPURLResponse else { return unknown }
        if let finalURL = http.url, ServerAddress.origin(of: finalURL) != origin {
            return SignInShape(passwordForm: false, fronted: fronted, ssoHost: finalURL.host)
        }
        if (300..<400).contains(http.statusCode) {
            let location = headerFields(http).first { $0.key.lowercased() == "location" }?.value ?? ""
            return SignInShape(passwordForm: false, fronted: fronted, ssoHost: URL(string: location)?.host)
        }
        guard http.statusCode == 200 else { return unknown }
        let html = String(decoding: data, as: UTF8.self)
        if let settings = bootSettings(in: html), settings.disableLoginForm != nil {
            return SignInShape(settings, fronted: fronted)
        }
        // Grafana 13's slimmer page leaves the flags to /api/frontend/settings, public only when it lets anyone view.
        if let settings = await frontendSettings(url, origin: origin), settings.disableLoginForm != nil {
            return SignInShape(settings, fronted: fronted)
        }
        if let disabled = flag("disableLoginForm", in: html) {
            var shape = SignInShape(passwordForm: !disabled, fronted: fronted)
            shape.anonymous = flag("anonymousEnabled", in: html) ?? false
            return shape
        }
        return unknown
    }

    private static func frontendSettings(_ url: URL, origin: String) async -> BootSettings? {
        var request = URLRequest(url: url.appending(path: "api/frontend/settings"))
        request.httpMethod = "GET"
        guard let (data, response) = try? await session.data(for: request, delegate: SameOriginRedirects(origin: origin)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(BootSettings.self, from: data)
    }

    /// The `settings` the sign-in page carries in `window.grafanaBootData`. The page writes the object
    /// with bare JavaScript keys (`user: {…}, settings: {…}`) and JSON values, so the value is cut out
    /// by hand and decoded on its own.
    struct BootSettings: Decodable {
        struct Provider: Decodable { let name: String? }
        var disableLoginForm: Bool?
        var anonymousEnabled: Bool?
        var authProxyEnabled: Bool?
        var ldapEnabled: Bool?
        var passwordlessEnabled: Bool?
        var oauth: [String: Provider]?

        enum CodingKeys: String, CodingKey { case disableLoginForm, anonymousEnabled, authProxyEnabled, ldapEnabled, passwordlessEnabled, oauth }

        /// Grafana writes `""` for a flag it has no value for; that reads as unknown, not as an error.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            disableLoginForm = try? c.decodeIfPresent(Bool.self, forKey: .disableLoginForm)
            anonymousEnabled = try? c.decodeIfPresent(Bool.self, forKey: .anonymousEnabled)
            authProxyEnabled = try? c.decodeIfPresent(Bool.self, forKey: .authProxyEnabled)
            ldapEnabled = try? c.decodeIfPresent(Bool.self, forKey: .ldapEnabled)
            passwordlessEnabled = try? c.decodeIfPresent(Bool.self, forKey: .passwordlessEnabled)
            oauth = try? c.decodeIfPresent([String: Provider].self, forKey: .oauth)
        }
    }

    static func bootSettings(in html: String) -> BootSettings? {
        let bytes = Array(html.utf8)
        guard let anchor = range(of: "grafanaBootData", in: bytes),
              let open = bytes[anchor...].firstIndex(of: 0x7b),
              let raw = topLevelValue(named: "settings", in: bytes, objectAt: open) else { return nil }
        return try? JSONDecoder().decode(BootSettings.self, from: raw)
    }

    private static func range(of needle: String, in bytes: [UInt8]) -> Int? {
        let n = Array(needle.utf8)
        guard n.count <= bytes.count else { return nil }
        for i in 0...(bytes.count - n.count) where bytes[i] == n[0] {
            if Array(bytes[i..<(i + n.count)]) == n { return i + n.count }
        }
        return nil
    }

    /// Walks the top-level entries of a JavaScript object literal whose values are JSON and returns
    /// the raw bytes of the value under `wanted`. Strings are skipped whole, braces are balanced.
    static func topLevelValue(named wanted: String, in bytes: [UInt8], objectAt open: Int) -> Data? {
        let n = bytes.count
        var i = open + 1
        let space: Set<UInt8> = [0x20, 0x09, 0x0a, 0x0d]
        func skipSpace() { while i < n, space.contains(bytes[i]) { i += 1 } }
        func skipString() {
            i += 1
            while i < n {
                if bytes[i] == 0x5c { i += 2; continue }
                if bytes[i] == 0x22 { i += 1; return }
                i += 1
            }
        }
        func skipValue() -> Range<Int> {
            let from = i
            guard i < n else { return from..<from }
            if bytes[i] == 0x22 { skipString(); return from..<i }
            if bytes[i] == 0x7b || bytes[i] == 0x5b {
                var depth = 0
                while i < n {
                    let b = bytes[i]
                    if b == 0x22 { skipString(); continue }
                    if b == 0x7b || b == 0x5b { depth += 1 }
                    if b == 0x7d || b == 0x5d {
                        depth -= 1
                        if depth == 0 { i += 1; return from..<i }
                    }
                    i += 1
                }
                return from..<i
            }
            while i < n, bytes[i] != 0x2c, bytes[i] != 0x7d { i += 1 }
            return from..<i
        }
        while i < n {
            skipSpace()
            guard i < n, bytes[i] != 0x7d else { return nil }
            let key: String
            if bytes[i] == 0x22 {
                let start = i + 1
                skipString()
                key = String(decoding: bytes[start..<max(start, i - 1)], as: UTF8.self)
            } else {
                let start = i
                while i < n, bytes[i] != 0x3a, !space.contains(bytes[i]) { i += 1 }
                key = String(decoding: bytes[start..<i], as: UTF8.self)
            }
            skipSpace()
            guard i < n, bytes[i] == 0x3a else { return nil }
            i += 1
            skipSpace()
            let value = skipValue()
            if key == wanted { return Data(bytes[value]) }
            skipSpace()
            if i < n, bytes[i] == 0x2c { i += 1 }
        }
        return nil
    }

    /// The last resort: `"name":true` or `"name":false` anywhere in the page.
    static func flag(_ name: String, in html: String) -> Bool? {
        if html.contains("\"\(name)\":true") { return true }
        if html.contains("\"\(name)\":false") { return false }
        return nil
    }

    // MARK: Who am I

    /// Who this credential is on that Grafana. A 401 means it is not accepted; being sent to a sign-in
    /// page, or handed a page instead of JSON, means the same.
    static func user(_ url: URL, credential: Credential) async throws -> GrafanaUser {
        let origin = ServerAddress.origin(of: url)
        var request = URLRequest(url: url.appending(path: "api/user"))
        request.httpMethod = "GET"
        credential.apply(to: &request)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request, delegate: SameOriginRedirects(origin: origin)) }
        catch let error as URLError { throw GrafanaError.transport(explain(error)) }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 || (300..<400).contains(status) { throw AuthError.signedOut }
        if let final = http?.url, ServerAddress.origin(of: final) != origin { throw AuthError.signedOut }
        guard status == 200 else { throw GrafanaError.http(status, "") }
        do { return try JSONDecoder().decode(GrafanaUser.self, from: data) }
        catch { throw AuthError.signedOut }
    }

    // MARK: Password sign-in

    /// Grafana's own username-and-password sign-in (its accounts, or LDAP through it): the same POST
    /// its page makes, answered with the session cookie. The cookie header comes back ready to store.
    static func passwordSignIn(_ url: URL, user: String, password: String) async throws -> (cookieHeader: String, expiry: String?, user: GrafanaUser) {
        let origin = ServerAddress.origin(of: url)
        var request = URLRequest(url: url.appending(path: "login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["user": user, "password": password])
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request, delegate: SameOriginRedirects(origin: origin)) }
        catch let error as URLError { throw GrafanaError.transport(explain(error)) }
        guard let http = response as? HTTPURLResponse else { throw GrafanaError.transport("No answer from Grafana.") }
        switch http.statusCode {
        case 200:
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields(http), for: url)
            guard let session = cookies.first(where: { $0.name == "grafana_session" }), !session.value.isEmpty else {
                throw AuthError.refused("Grafana said signed in, but sent no session cookie.")
            }
            let expiry = cookies.first { $0.name == "grafana_session_expiry" }?.value
            let header = "grafana_session=\(session.value)"
            let who = try await Self.user(url, credential: .cookie(header))
            return (header, expiry, who)
        case 401:
            throw AuthError.refused("Wrong username or password.")
        case 400 where (try? JSONDecoder().decode(GrafanaMessage.self, from: data))?.messageId == "auth.client.notConfigured":
            throw AuthError.refused("This Grafana has password sign-in turned off. Use its sign-in page or a service account token.")
        default:
            throw AuthError.refused("Grafana answered HTTP \(http.statusCode).")
        }
    }

    private struct GrafanaMessage: Decodable {
        let messageId: String?
        let message: String?
    }

    /// The response headers as plain strings, the shape HTTPCookie reads.
    static func headerFields(_ http: HTTPURLResponse) -> [String: String] {
        var fields: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        return fields
    }
}

extension ServerProbe.SignInShape {
    init(_ settings: ServerProbe.BootSettings, fronted: Bool) {
        self.init()
        passwordForm = settings.disableLoginForm.map { !$0 }
        providers = (settings.oauth ?? [:]).values.compactMap(\.name).sorted()
        anonymous = settings.anonymousEnabled ?? false
        self.fronted = fronted
    }
}

#if DEBUG
extension ServerProbe {
    /// Exercises the page parser and the health classification on fixtures shaped like real answers.
    /// Development builds run it once; a failure trips the assert, and the log line says it passed.
    static func selfCheck() {
        let origin = "https://grafana.example.com"
        let page = """
        <script>
        window.grafanaBootData = {
            user: {"isSignedIn":false,"login":"","name":"a } brace in a string"},
            settings: {"disableLoginForm":true,"anonymousEnabled":false,"authProxyEnabled":false,"ldapEnabled":false,"passwordlessEnabled":"","oauth":{"generic_oauth":{"icon":"signin","name":"Keystone"},"github":{"name":"GitHub"}},"buildInfo":{"version":"13.2.1"}},
            navTree: [{"id":"x","text":"{not json here}"}]
        };
        </script>
        """
        let settings = bootSettings(in: page)
        assert(settings?.disableLoginForm == true && settings?.passwordlessEnabled == nil, "bare-key object with JSON values; an empty-string flag reads as unknown")
        let sso = SignInShape(settings!, fronted: false)
        assert(sso.passwordForm == false && sso.providers == ["GitHub", "Keystone"] && !sso.anonymous, "SSO-only shape with sorted provider names")
        let slim = "window.grafanaBootData = {\n  _femt: true, \n  assets: {\"cdn\":\"https://x/settings/\"},\n  settings: {\"buildInfo\":{\"version\":\"13.3.0\"}},\n  user: {}\n};"
        let trimmed = bootSettings(in: slim)
        assert(trimmed != nil && trimmed?.disableLoginForm == nil && trimmed?.oauth == nil, "a slimmer page decodes with every flag unknown")
        let form = SignInShape(bootSettings(in: "grafanaBootData = {settings: {\"disableLoginForm\":false,\"oauth\":{}}}")!, fronted: false)
        assert(form.passwordForm == true && form.providers.isEmpty, "the default Grafana shows its form")
        assert(flag("disableLoginForm", in: "x\"disableLoginForm\":false,y") == false && flag("anonymousEnabled", in: "") == nil, "flag fallback")
        let healthy = Data(#"{"database":"ok","version":"11.6.0","commit":"abc"}"#.utf8)
        assert(classify(status: 200, headers: [:], finalURL: URL(string: origin + "/api/health"), data: healthy, origin: origin) == .ok(version: "11.6.0", database: "ok"), "healthy JSON")
        let access = ["Location": "https://team.cloudflareaccess.com/cdn-cgi/access/login/grafana.example.com?kid=x"]
        assert(classify(status: 302, headers: access, finalURL: nil, data: Data(), origin: origin) == .fronted("team.cloudflareaccess.com"), "off-origin redirect names the gate")
        assert(classify(status: 401, headers: [:], finalURL: nil, data: Data(), origin: origin) == .fronted(""), "401 before Grafana is a gate")
        assert(classify(status: 200, headers: [:], finalURL: nil, data: Data("<html>sign in</html>".utf8), origin: origin) == .fronted(""), "a page where the API should be is a gate")
        assert(classify(status: 200, headers: [:], finalURL: URL(string: "https://auth.example.com/?rd=x"), data: healthy, origin: origin) == .fronted("auth.example.com"), "an answer from another origin is a gate")
        if case .failed = classify(status: 404, headers: [:], finalURL: nil, data: Data(), origin: origin) {} else { assertionFailure("404 is not Grafana") }
        if case .failed = classify(status: 503, headers: [:], finalURL: nil, data: Data(), origin: origin) {} else { assertionFailure("503 is down") }
        assert(Outcome.fronted("x").isReachable && !Outcome.fronted("x").isOK && Outcome.failed("x").isReachable == false, "reachable covers ok and fronted")
        NSLog("Brazier probe self-check passed")
    }
}
#endif
