import SwiftUI

struct AlertRow: View {
    let alert: GrafanaAlert
    /// Say which organization the row came from; only when more than one is on the screen.
    var showOrg = false

    private var metaLine: String {
        var parts: [String] = []
        if !alert.placeLine.isEmpty { parts.append(alert.placeLine) }
        if let since = alert.activeDate { parts.append("since \(GrafanaDates.age(since: since))") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Brand.Space.label) {
            Lamp(signal: alert.phase.signal).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.name).font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                if let summary = alert.summary, !summary.isEmpty {
                    Text(summary).font(BrandFont.small).foregroundStyle(Brand.Tone.muted).lineLimit(2)
                }
                HStack(spacing: Brand.Space.inline) {
                    if showOrg, let org = alert.orgName {
                        StateChip(word: Self.chipWord(org), signal: .none).fixedSize()
                    }
                    Text(metaLine).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let severity = alert.labels["severity"] {
                StateChip(word: severity, signal: severity == "page" ? .stop : .wait)
            }
        }
        .padding(.vertical, Brand.Space.hairline)
        .frame(minHeight: Brand.hitTarget)
    }

    /// At most fourteen characters, cut between words: "Guys Inc Public" reads "Guys Inc", not "Guys Inc Publi".
    static func chipWord(_ name: String) -> String {
        guard name.count > 14 else { return name }
        var kept = ""
        for word in name.split(separator: " ") {
            let next = kept.isEmpty ? String(word) : kept + " " + word
            if next.count > 14 { break }
            kept = next
        }
        return kept.isEmpty ? String(name.prefix(14)) : kept
    }
}
