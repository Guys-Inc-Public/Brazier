import Foundation

struct GrafanaHealth: Decodable {
    let database: String
    let version: String
}

struct GrafanaUser: Decodable {
    let login: String
    let email: String
    let name: String
    let isGrafanaAdmin: Bool?
}

struct AlertsEnvelope: Decodable {
    let status: String
    let data: AlertsData
}

struct AlertsData: Decodable {
    let alerts: [GrafanaAlert]
}

/// One alert instance from /api/prometheus/grafana/api/v1/alerts.
struct GrafanaAlert: Decodable, Identifiable, Hashable {
    let labels: [String: String]
    let annotations: [String: String]
    let state: String
    let activeAt: String?
    let value: String?

    var id: String {
        labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    var name: String { labels["alertname"] ?? "alert" }
    var folder: String { labels["grafana_folder"] ?? "" }
    var summary: String? { annotations["summary"] ?? annotations["description"] }

    var phase: AlertPhase {
        switch state.lowercased() {
        case "alerting", "firing": return .firing
        case "pending", "recovering": return .pending
        case "error", "nodata": return .fault
        default: return .normal
        }
    }

    var activeDate: Date? { activeAt.flatMap(GrafanaDates.parse) }

    /// Labels a person reads: everything Grafana did not add for itself.
    var visibleLabels: [(String, String)] {
        labels.filter { !$0.key.hasPrefix("__") }.sorted { $0.key < $1.key }
    }

    var placeLine: String {
        [labels["host"], labels["site"], labels["instance"]].compactMap { $0 }.joined(separator: " · ")
    }

    static func == (lhs: GrafanaAlert, rhs: GrafanaAlert) -> Bool { lhs.id == rhs.id && lhs.state == rhs.state }
    func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(state) }
}

enum AlertPhase: Int, CaseIterable, Hashable {
    case firing, pending, fault, normal

    var word: String {
        switch self {
        case .firing: return "FIRING"
        case .pending: return "PENDING"
        case .fault: return "FAULT"
        case .normal: return "NORMAL"
        }
    }

    var title: String {
        switch self {
        case .firing: return "Firing"
        case .pending: return "Pending"
        case .fault: return "Evaluation faults"
        case .normal: return "Normal"
        }
    }

    var signal: Signal {
        switch self {
        case .firing: return .stop
        case .pending: return .wait
        case .fault: return .wait
        case .normal: return .ok
        }
    }
}

struct Matcher: Codable, Hashable {
    let name: String
    let value: String
    let isRegex: Bool
    let isEqual: Bool
}

struct Silence: Decodable, Identifiable {
    let id: String
    let matchers: [Matcher]
    let startsAt: String
    let endsAt: String
    let comment: String
    let createdBy: String
    let status: SilenceStatus

    struct SilenceStatus: Decodable { let state: String }

    var endDate: Date? { GrafanaDates.parse(endsAt) }
}

struct NewSilence: Encodable {
    let matchers: [Matcher]
    let startsAt: String
    let endsAt: String
    let createdBy: String
    let comment: String
}

struct SilenceCreated: Decodable {
    let silenceID: String
}

struct SearchHit: Decodable, Identifiable, Hashable {
    let uid: String
    let title: String
    let url: String
    let type: String
    let tags: [String]
    let isStarred: Bool?
    let folderTitle: String?

    var id: String { uid }
}

enum GrafanaDates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }

    static func format(_ d: Date) -> String { plain.string(from: d) }

    /// "since 20m", "since 3h", "since 2d": the compact age a rack row has room for.
    static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}
