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

/// One GET each, before a server exists: is there a Grafana at this address, and who am I on it.
enum ServerProbe {
    enum Outcome: Equatable {
        case ok(version: String, database: String)
        case failed(String)

        var isOK: Bool {
            if case .ok = self { return true }
            return false
        }
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

    static func health(_ url: URL) async -> Outcome {
        var request = URLRequest(url: url.appending(path: "api/health"))
        request.httpMethod = "GET"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            return .failed(explain(error))
        } catch {
            return .failed(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            if let health = try? JSONDecoder().decode(GrafanaHealth.self, from: data) {
                return .ok(version: health.version, database: health.database)
            }
            return .failed("Something answered at that address, but not like Grafana. Use Grafana's root address; a sign-in proxy in front of it will not do.")
        case 401, 403:
            return .failed("That address wants a sign-in before Grafana even answers. Brazier needs Grafana's API reachable; a proxy in front of it will not do.")
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

    /// Who this credential is on that Grafana. A 401 means it is not accepted.
    static func user(_ url: URL, credential: Credential) async throws -> GrafanaUser {
        var request = URLRequest(url: url.appending(path: "api/user"))
        request.httpMethod = "GET"
        credential.apply(to: &request)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError { throw GrafanaError.transport(explain(error)) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw AuthError.signedOut }
        guard status == 200 else { throw GrafanaError.http(status, "") }
        do { return try JSONDecoder().decode(GrafanaUser.self, from: data) }
        catch { throw GrafanaError.decoding("no user in the answer") }
    }
}
