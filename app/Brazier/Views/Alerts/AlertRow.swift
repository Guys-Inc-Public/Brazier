import SwiftUI

struct AlertRow: View {
    let alert: GrafanaAlert

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
                Text(metaLine).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let severity = alert.labels["severity"] {
                StateChip(word: severity, signal: severity == "page" ? .stop : .wait)
            }
        }
        .padding(.vertical, Brand.Space.hairline)
        .frame(minHeight: Brand.hitTarget)
    }
}
