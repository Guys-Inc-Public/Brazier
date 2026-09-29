import Foundation
import Observation

/// The list of servers and the relay URL. Plain state in UserDefaults; secrets in the keychain.
@MainActor
@Observable
final class ServerStore {
    private(set) var servers: [Server] = []
    var relayURL: URL {
        didSet { defaults.set(relayURL.absoluteString, forKey: Keys.relay) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let servers = "servers"
        static let relay = "relayURL"
    }

    init() {
        if let data = defaults.data(forKey: Keys.servers),
           let list = try? JSONDecoder().decode([Server].self, from: data) {
            servers = list
        }
        relayURL = defaults.string(forKey: Keys.relay).flatMap(URL.init(string:)) ?? EstatePreset.relay
    }

    func add(_ server: Server) {
        servers.append(server)
        save()
    }

    func update(_ server: Server) {
        guard let i = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[i] = server
        save()
    }

    func remove(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        Keychain.delete(SecretKey.refreshToken(server.id))
        Keychain.delete(SecretKey.idToken(server.id))
        Keychain.delete(SecretKey.apiToken(server.id))
        save()
    }

    func server(id: UUID?) -> Server? {
        servers.first { $0.id == id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: Keys.servers)
        }
    }
}
