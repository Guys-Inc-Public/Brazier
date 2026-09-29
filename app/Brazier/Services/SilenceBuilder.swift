import Foundation

enum SilenceDuration: Int, CaseIterable, Identifiable {
    case h1 = 1, h8 = 8, h24 = 24

    var id: Int { rawValue }
    var word: String { "\(rawValue) h" }
    var seconds: TimeInterval { TimeInterval(rawValue) * 3600 }
}

/// Builds the silence Grafana's Alertmanager accepts: every label of the alert, matched exactly,
/// except the folder Grafana adds for itself. That silences this instance and nothing wider.
enum SilenceBuilder {
    static let createdBy = "Brazier"

    static func matchers(for labels: [String: String]) -> [Matcher] {
        labels
            .filter { $0.key != "grafana_folder" && !$0.key.hasPrefix("__") }
            .sorted { $0.key == "alertname" ? true : ($1.key == "alertname" ? false : $0.key < $1.key) }
            .map { Matcher(name: $0.key, value: $0.value, isRegex: false, isEqual: true) }
    }

    static func silence(labels: [String: String], duration: SilenceDuration, comment: String, now: Date = Date()) -> NewSilence {
        NewSilence(
            matchers: matchers(for: labels),
            startsAt: GrafanaDates.format(now),
            endsAt: GrafanaDates.format(now.addingTimeInterval(duration.seconds)),
            createdBy: createdBy,
            comment: comment.isEmpty ? "Silenced from Brazier" : comment
        )
    }
}
