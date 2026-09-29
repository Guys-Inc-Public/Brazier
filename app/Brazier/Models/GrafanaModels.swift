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

/// One organization the signed-in user belongs to, from /api/user/orgs.
struct GrafanaOrg: Decodable, Identifiable, Hashable {
    let orgId: Int
    let name: String
    let role: String?

    var id: Int { orgId }
}

/// Which of a server's organizations the tabs read: every one, or one of them.
enum OrgSelection: Equatable, Hashable {
    case all
    case one(Int)

    var stored: String {
        switch self {
        case .all: return "all"
        case .one(let id): return String(id)
        }
    }

    init(stored: String?) {
        if let stored, let id = Int(stored) { self = .one(id) } else { self = .all }
    }
}

struct AlertsEnvelope: Decodable {
    let status: String
    let data: AlertsData
}

struct AlertsData: Decodable {
    let alerts: [GrafanaAlert]
}

/// One alert instance from /api/prometheus/grafana/api/v1/alerts, tagged with the organization it
/// was read from (Grafana never writes that into the instance itself).
struct GrafanaAlert: Decodable, Identifiable, Hashable {
    let labels: [String: String]
    let annotations: [String: String]
    let state: String
    let activeAt: String?
    let value: String?
    /// The organization the read was scoped to; nil when the server was read without one.
    var orgId: Int?
    var orgName: String?

    private enum CodingKeys: String, CodingKey { case labels, annotations, state, activeAt, value }

    init(labels: [String: String], annotations: [String: String], state: String, activeAt: String?, value: String?, orgId: Int? = nil, orgName: String? = nil) {
        self.labels = labels
        self.annotations = annotations
        self.state = state
        self.activeAt = activeAt
        self.value = value
        self.orgId = orgId
        self.orgName = orgName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        annotations = try c.decodeIfPresent([String: String].self, forKey: .annotations) ?? [:]
        state = try c.decode(String.self, forKey: .state)
        activeAt = try c.decodeIfPresent(String.self, forKey: .activeAt)
        value = try c.decodeIfPresent(String.self, forKey: .value)
    }

    /// The same instance, marked as read from an organization.
    func tagged(_ org: GrafanaOrg) -> GrafanaAlert {
        var copy = self
        copy.orgId = org.orgId
        copy.orgName = org.name
        return copy
    }

    var id: String {
        "\(orgId ?? 0):" + labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
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
    /// The organization the silence was read from; silences never cross organizations.
    var orgId: Int?

    struct SilenceStatus: Decodable { let state: String }

    private enum CodingKeys: String, CodingKey { case id, matchers, startsAt, endsAt, comment, createdBy, status }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        matchers = try c.decodeIfPresent([Matcher].self, forKey: .matchers) ?? []
        startsAt = try c.decode(String.self, forKey: .startsAt)
        endsAt = try c.decode(String.self, forKey: .endsAt)
        comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        status = try c.decode(SilenceStatus.self, forKey: .status)
    }

    func tagged(_ org: GrafanaOrg) -> Silence {
        var copy = self
        copy.orgId = org.orgId
        return copy
    }

    var endDate: Date? { GrafanaDates.parse(endsAt) }
    var startDate: Date? { GrafanaDates.parse(startsAt) }
    var isActive: Bool { status.state == "active" }

    /// True when every matcher holds for the alert's labels, in the alert's own organization. Regex and
    /// negative matchers are honoured the way Alertmanager reads them.
    func covers(_ alert: GrafanaAlert) -> Bool {
        guard orgId == nil || alert.orgId == nil || orgId == alert.orgId else { return false }
        return matchers.allSatisfy { m in
            let actual = alert.labels[m.name] ?? ""
            let hit: Bool
            if m.isRegex {
                hit = actual.range(of: "^(?:\(m.value))$", options: .regularExpression) != nil
            } else {
                hit = actual == m.value
            }
            return m.isEqual ? hit : !hit
        }
    }

    /// The rule the silence is for, when its matchers name one.
    var alertName: String? { matchers.first { $0.name == "alertname" && $0.isEqual && !$0.isRegex }?.value }

    /// The matchers as one line, `alertname` first: `alertname=Disk above 85 percent · host=ovh`.
    var matcherLine: String {
        matchers
            .sorted { $0.name == "alertname" ? true : ($1.name == "alertname" ? false : $0.name < $1.name) }
            .map { "\($0.name)\($0.isEqual ? "" : "!")\($0.isRegex ? "~" : "=")\($0.value)" }
            .joined(separator: " · ")
    }
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
    /// The organization the search ran in; a dashboard uid is only unique within one.
    var orgId: Int?
    var orgName: String?

    private enum CodingKeys: String, CodingKey { case uid, title, url, type, tags, isStarred, folderTitle }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "dash-db"
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred)
        folderTitle = try c.decodeIfPresent(String.self, forKey: .folderTitle)
    }

    func tagged(_ org: GrafanaOrg) -> SearchHit {
        var copy = self
        copy.orgId = org.orgId
        copy.orgName = org.name
        return copy
    }

    var id: String { "\(orgId ?? 0):\(uid)" }
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
