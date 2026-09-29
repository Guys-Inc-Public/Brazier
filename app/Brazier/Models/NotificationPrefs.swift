import Foundation

/// The floor a push must clear. Grafana has no severity of its own; this is the `severity` label
/// convention (info, warning, critical, page), with the estate's `warn` read as warning.
enum MinSeverity: String, Codable, CaseIterable, Identifiable {
    case info, warning, critical, page

    var id: String { rawValue }

    var word: String {
        switch self {
        case .info: return "Everything"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .page: return "Page"
        }
    }
}

/// What this phone wants pushed, kept beside its device record on the relay so the relay filters
/// before it sends. Stored locally per server too, so the screen reads the same after a relaunch.
struct NotificationPrefs: Codable, Equatable {
    struct Quiet: Codable, Equatable {
        /// "HH:mm" in `tz`.
        var start: String
        var end: String
        var tz: String
        /// Pages still ring through quiet hours.
        var allowPage: Bool
    }

    /// Organizations to push for; nil means every one.
    var orgs: [Int]?
    var minSeverity: MinSeverity
    var quiet: Quiet?

    init(orgs: [Int]? = nil, minSeverity: MinSeverity = .info, quiet: Quiet? = nil) {
        self.orgs = orgs
        self.minSeverity = minSeverity
        self.quiet = quiet
    }

    private enum CodingKeys: String, CodingKey { case orgs, minSeverity, quiet }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orgs = try c.decodeIfPresent([Int].self, forKey: .orgs)
        minSeverity = try c.decodeIfPresent(MinSeverity.self, forKey: .minSeverity) ?? .info
        quiet = try c.decodeIfPresent(Quiet.self, forKey: .quiet)
    }

    /// `orgs` and `quiet` go out as explicit null when unset: the relay reads null as "clear it".
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(orgs, forKey: .orgs)
        try c.encode(minSeverity, forKey: .minSeverity)
        try c.encode(quiet, forKey: .quiet)
    }
}
