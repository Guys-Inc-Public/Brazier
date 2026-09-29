import Foundation

/// The `brazier` object the relay puts beside `aps` in every push.
struct BrazierPush: Decodable {
    let fingerprint: String
    let status: String
    let alertname: String
    let labels: [String: String]
    let annotations: [String: String]
    let startsAt: String?
    let endsAt: String?
    let generatorURL: String?
    let silenceURL: String?
    let externalURL: String?
    let folder: String?
    /// The organization the alert fired in, when the relay knew it.
    let orgId: Int?
    let org: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let object = userInfo["brazier"],
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(BrazierPush.self, from: data)
        else { return nil }
        self = decoded
    }

    /// The alert as the list would show it, so a tapped push opens the same detail view.
    var asAlert: GrafanaAlert {
        var labels = self.labels
        if labels["alertname"] == nil { labels["alertname"] = alertname }
        if let folder, labels["grafana_folder"] == nil { labels["grafana_folder"] = folder }
        return GrafanaAlert(
            labels: labels,
            annotations: annotations,
            state: status == "firing" ? "Alerting" : "Normal",
            activeAt: startsAt,
            value: nil,
            orgId: orgId,
            orgName: org
        )
    }

    var externalHost: String? { externalURL.flatMap { URL(string: $0)?.host } }
}
