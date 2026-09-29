import Foundation

enum RelayError: LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "Relay answered \(status)\(body.isEmpty ? "" : ": \(body)")"
        }
    }
}

/// Device registration with the push relay. The relay verifies the Keystone ID token
/// against the same JWKS Grafana trusts and files the APNs token under that user.
struct RelayClient {
    let baseURL: URL

    struct Registration: Encodable {
        let token: String
        let platform: String
        let environment: String
        let name: String
    }

    func register(token: String, environment: String, name: String, idToken: String) async throws {
        let body = Registration(token: token, platform: "ios", environment: environment, name: name)
        var request = URLRequest(url: baseURL.appending(path: "devices"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        try await send(request)
    }

    func deregister(token: String, idToken: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "devices/\(token)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        try await send(request)
    }

    private func send(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RelayError.http(status, String(data: data.prefix(160), encoding: .utf8) ?? "")
        }
    }
}
