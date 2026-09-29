import Foundation

/// Finds the admin's settings for a Grafana from a signpost the admin owns, so the first run needs
/// only the Grafana address. Three places, in order; each lookup has five seconds and fails silently:
/// 1. `GET <grafana origin>/.well-known/brazier`, the relay's document served on the Grafana host.
/// 2. A DNS TXT record at `_brazier.<grafana host>`, read over DNS-over-HTTPS (Cloudflare, then Google).
/// 3. When only a relay is known, that relay's own `/.well-known/brazier` names the sign-in.
enum Discovery {
    struct Result: Equatable {
        enum Source: Equatable { case wellKnown, dns }
        var relayURL: URL?
        var signIn: RelayDirectory.SignIn?
        var source: Source
        var isEmpty: Bool { relayURL == nil && signIn == nil }
    }

    static let timeout: TimeInterval = 5

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    /// Nil when no signpost names anything for this Grafana.
    static func find(for grafana: URL) async -> Result? {
        let origin = ServerAddress.origin(of: grafana)
        var found: Result?
        if let signpost = await wellKnown(at: grafana, origin: origin) {
            found = signpost
        } else if let host = grafana.host, let record = await txtRecord(host: host) {
            found = record
        }
        guard var result = found, !result.isEmpty else { return nil }
        if result.signIn == nil, let relay = result.relayURL,
           let document = await document(at: relay.appending(path: ".well-known/brazier")) {
            result.signIn = document.signIn(for: origin)
        }
        return result
    }

    // MARK: Well-known document

    /// The document on the Grafana host counts only when it is JSON of the relay's shape and its
    /// `grafana` map names this origin: a Grafana answers 200 with its own page for unknown paths.
    private static func wellKnown(at grafana: URL, origin: String) async -> Result? {
        var base = URLComponents()
        base.scheme = grafana.scheme
        base.host = grafana.host
        base.port = grafana.port
        base.path = "/.well-known/brazier"
        guard let url = base.url, let document = await document(at: url), document.entry(for: origin) != nil else { return nil }
        return Result(relayURL: document.relay?.url, signIn: document.signIn(for: origin), source: .wellKnown)
    }

    private static func document(at url: URL) async -> RelayDirectory? {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let data = await fetch(request) else { return nil }
        return try? JSONDecoder().decode(RelayDirectory.self, from: data)
    }

    // MARK: DNS TXT

    private static func txtRecord(host: String) async -> Result? {
        let name = "_brazier.\(host)"
        guard let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let resolvers: [(String, String)] = [
            ("https://cloudflare-dns.com/dns-query?name=\(escaped)&type=TXT", "application/dns-json"),
            ("https://dns.google/resolve?name=\(escaped)&type=TXT", "application/json"),
        ]
        for (address, accept) in resolvers {
            guard let url = URL(string: address) else { continue }
            var request = URLRequest(url: url)
            request.setValue(accept, forHTTPHeaderField: "Accept")
            guard let data = await fetch(request), let answer = try? JSONDecoder().decode(DNSAnswer.self, from: data) else { continue }
            if let result = answer.records.lazy.compactMap({ parse(record: $0) }).first { return result }
            if answer.status == 0 || answer.status == 3 { return nil }
        }
        return nil
    }

    private struct DNSAnswer: Decodable {
        struct Item: Decodable { let data: String? }
        let status: Int?
        let answer: [Item]?
        enum CodingKeys: String, CodingKey { case status = "Status", answer = "Answer" }
        var records: [String] { (answer ?? []).compactMap { $0.data }.map(unquote) }
    }

    /// TXT data arrives as one or more quoted chunks (`"v=brazier1 relay=…" "issuer=…"`); join them.
    static func unquote(_ data: String) -> String {
        guard data.contains("\"") else { return data }
        var out = ""
        var inside = false
        var escaped = false
        for ch in data {
            if escaped { out.append(ch); escaped = false; continue }
            switch ch {
            case "\\" where inside: escaped = true
            case "\"": inside.toggle()
            default: if inside { out.append(ch) }
            }
        }
        return out
    }

    /// `v=brazier1 relay=https://… issuer=https://… client_id=… name=…`, whitespace-separated pairs.
    /// Values may be percent-encoded (a name with a space is `name=Guys%20Inc`).
    static func parse(record: String) -> Result? {
        var pairs: [String: String] = [:]
        for word in record.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            guard let eq = word.firstIndex(of: "=") else { continue }
            let key = word[..<eq].lowercased()
            let value = String(word[word.index(after: eq)...])
            pairs[key] = value.removingPercentEncoding ?? value
        }
        guard pairs["v"] == "brazier1" else { return nil }
        var result = Result(source: .dns)
        if let relay = pairs["relay"], case .url(let url) = ServerAddress.normalise(relay) { result.relayURL = url }
        if let issuerText = pairs["issuer"], let issuer = URL(string: issuerText), issuer.scheme == "https",
           let clientID = pairs["client_id"], !clientID.isEmpty {
            result.signIn = RelayDirectory.SignIn(issuer: issuer, clientId: clientID, name: pairs["name"])
        }
        return result.isEmpty ? nil : result
    }

    // MARK: Transport

    private static func fetch(_ request: URLRequest) async -> Data? {
        guard let reply = try? await session.data(for: request),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return reply.0
    }
}

#if DEBUG
extension Discovery {
    /// Exercises the TXT parser on fixtures shaped like the resolvers' JSON; no record exists to ask DNS for.
    /// Development builds run it once; a failure trips the assert, and the log line says it passed.
    static func selfCheck() {
        let cloudflare = #"{"Status":0,"Answer":[{"name":"_brazier.grafana.example.com","type":16,"TTL":300,"data":"\"v=brazier1 relay=https://brazier.example.com issuer=https://idp.example.com/application/o/brazier/ \" \"client_id=abc name=Example\""}]}"#
        let google = #"{"Status":0,"Answer":[{"name":"_brazier.grafana.example.com.","type":16,"TTL":300,"data":"\"v=brazier1 relay=https://brazier.example.com\""}]}"#
        let foreign = #"{"Status":0,"Answer":[{"name":"_brazier.grafana.example.com.","type":16,"TTL":300,"data":"\"v=spf1 -all\""}]}"#
        let nxdomain = #"{"Status":3,"Answer":null}"#
        let decode = { (json: String) -> DNSAnswer? in try? JSONDecoder().decode(DNSAnswer.self, from: Data(json.utf8)) }
        let full = decode(cloudflare)?.records.compactMap(parse).first
        assert(full?.relayURL?.absoluteString == "https://brazier.example.com", "relay from joined chunks")
        assert(full?.signIn?.issuer.absoluteString == "https://idp.example.com/application/o/brazier/", "issuer from second chunk")
        assert(full?.signIn?.clientId == "abc" && full?.signIn?.name == "Example", "client id and name")
        let relayOnly = decode(google)?.records.compactMap(parse).first
        assert(relayOnly?.relayURL?.host == "brazier.example.com" && relayOnly?.signIn == nil, "relay without sign-in")
        assert(decode(foreign)?.records.compactMap(parse).first == nil, "a record without v=brazier1 is ignored")
        assert(decode(nxdomain)?.status == 3 && decode(nxdomain)?.records.isEmpty == true, "NXDOMAIN reads as empty")
        assert(parse(record: "v=brazier1 name=Guys%20Inc") == nil, "sign-in needs issuer and client_id; alone it is empty")
        assert(parse(record: "v=brazier1 issuer=https://idp.example.com/o/x/ client_id=k name=Guys%20Inc")?.signIn?.name == "Guys Inc", "percent-decoded name")
        NSLog("Brazier discovery self-check passed")
    }
}
#endif
