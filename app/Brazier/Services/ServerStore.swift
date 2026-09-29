import Foundation
import Observation

/// The list of servers and the relay URL. Plain state in UserDefaults; secrets in the keychain.
@MainActor
@Observable
final class ServerStore {
    private(set) var servers: [Server] = []

    /// The push relay, if the person has one. Nothing is preset: without it there is no push.
    var relayURL: URL? {
        didSet {
            if let relayURL { defaults.set(relayURL.absoluteString, forKey: Keys.relay) }
            else { defaults.removeObject(forKey: Keys.relay) }
        }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let servers = "servers"
        static let relay = "relayURL"
    }

    /// Read before any view exists, so the first screen is right without a flicker.
    static var hasStoredServers: Bool {
        guard let data = UserDefaults.standard.data(forKey: Keys.servers),
              let list = try? JSONDecoder().decode([Server].self, from: data) else { return false }
        return !list.isEmpty
    }

    init() {
        if let data = defaults.data(forKey: Keys.servers),
           let list = try? JSONDecoder().decode([Server].self, from: data) {
            servers = list
        }
        relayURL = defaults.string(forKey: Keys.relay).flatMap(URL.init(string:))
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
        SecretKey.all(server.id).forEach(Keychain.delete)
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
