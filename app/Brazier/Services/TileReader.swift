import Foundation
import SwiftUI

/// One reading of a stat panel: its series reduced to a number each, formatted with the panel's unit,
/// coloured by its thresholds, with value mappings applied first, the way Grafana's stat panel does.
struct TileReading: Identifiable {
    let panel: Panel
    var series: [TileSeries] = []
    var fault: String?
    var id: String { panel.key }

    var title: String { panel.title?.isEmpty == false ? panel.title! : "Panel \(panel.id ?? 0)" }
    /// One tile per series when the panel names its series (`value_and_name`, or simply several).
    var showsNames: Bool { series.count > 1 || panel.options?.textMode == "value_and_name" || panel.options?.textMode == "name" }
}

struct TileSeries: Identifiable {
    let name: String
    /// True when the name is the series' own (its labels, or a display name the datasource gave it),
    /// false when it is only the frame or field name Grafana fell back to, which reads as noise.
    let named: Bool
    let text: String
    let color: Color
    var id: String { name }
}

enum TileReader {
    static let maxPanels = 12
    static let maxSeries = 12

    /// The body for /api/ds/query: the panel's targets as they are, plus the keys the endpoint wants.
    static func request(for panel: Panel) -> DataQueryRequest? {
        var queries: [JSONValue] = []
        for (i, target) in panel.targets.enumerated() {
            guard var q = target.object else { continue }
            if q["hide"]?.double == 1 { continue }
            if q["refId"] == nil { q["refId"] = .string(String(UnicodeScalar(UInt8(65 + min(i, 25))))) }
            if q["datasource"]?.object?["uid"] == nil {
                if let ds = panel.datasource, ds.uid != nil { q["datasource"] = ds.json } else { continue }
            }
            q["intervalMs"] = .number(60_000)
            q["maxDataPoints"] = .number(100)
            queries.append(.object(q))
        }
        guard !queries.isEmpty else { return nil }
        return DataQueryRequest(from: "now-6h", to: "now", queries: queries)
    }

    /// Frames in, series out: one per numeric field, reduced by the panel's calculation.
    static func series(from response: DataQueryResponse, panel: Panel) throws -> [TileSeries] {
        var out: [TileSeries] = []
        let calc = panel.options?.reduceOptions?.calcs?.first ?? "lastNotNull"
        for key in response.results.keys.sorted() {
            let result = response.results[key]!
            if let error = result.error, !error.isEmpty { throw GrafanaError.transport(error) }
            for frame in result.frames ?? [] {
                guard let data = frame.data else { continue }
                for (i, field) in frame.schema.fields.enumerated() where field.type == "number" {
                    guard i < data.values.count else { continue }
                    let numbers = data.values[i].compactMap { $0.isNull ? nil : $0.double }
                    guard let value = reduce(numbers, calc: calc) else { continue }
                    let (name, named) = seriesName(frame: frame, field: field)
                    out.append(render(value, name: name, named: named, panel: panel, fieldUnit: field.config?.unit))
                    if out.count >= maxSeries { return out }
                }
            }
        }
        return out
    }

    static func reduce(_ values: [Double], calc: String) -> Double? {
        guard !values.isEmpty else { return nil }
        switch calc {
        case "mean": return values.reduce(0, +) / Double(values.count)
        case "max": return values.max()
        case "min": return values.min()
        case "sum": return values.reduce(0, +)
        case "first", "firstNotNull": return values.first
        case "count": return Double(values.count)
        default: return values.last
        }
    }

    /// The series' name and whether it is really its own (labels or a datasource display name) rather
    /// than the frame or field name Grafana falls back to.
    static func seriesName(frame: DataFrame, field: FrameField) -> (String, Bool) {
        if let n = field.config?.displayNameFromDS, !n.isEmpty { return (n, true) }
        if let n = field.config?.displayName, !n.isEmpty { return (n, true) }
        if let labels = field.labels, !labels.isEmpty {
            return (labels.sorted { $0.key < $1.key }.map { $0.value }.joined(separator: " · "), true)
        }
        if let n = frame.schema.name, !n.isEmpty { return (n, false) }
        return (field.name ?? "Value", false)
    }

    static func render(_ value: Double, name: String, named: Bool, panel: Panel, fieldUnit: String?) -> TileSeries {
        let defaults = panel.fieldConfig?.defaults
        var text: String?
        var color: Color?
        for mapping in defaults?.mappings ?? [] {
            if let hit = mapping.result(for: value) {
                if let t = hit.text, !t.isEmpty { text = t }
                if let c = hit.color { color = Self.color(named: c) }
                break
            }
        }
        if text == nil { text = format(value, unit: defaults?.unit ?? fieldUnit, decimals: defaults?.decimals) }
        if color == nil {
            if panel.options?.colorMode == "none" { color = Brand.Tone.paper }
            else { color = thresholdColor(for: value, steps: defaults?.thresholds?.steps ?? []) }
        }
        return TileSeries(name: name, named: named, text: text ?? "", color: color ?? Brand.Tone.paper)
    }

    /// The last step whose value the number reaches; the base step (nil value) when none does.
    static func thresholdColor(for value: Double, steps: [ThresholdStep]) -> Color {
        var chosen: String?
        for step in steps.sorted(by: { ($0.value ?? -.infinity) < ($1.value ?? -.infinity) }) {
            if let v = step.value {
                if value >= v { chosen = step.color }
            } else {
                chosen = step.color
            }
        }
        return chosen.map(color(named:)) ?? Brand.Tone.paper
    }

    /// Grafana's colour words (with their light/dark prefixes) and hex, onto the brand's tones.
    static func color(named raw: String) -> Color {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#"), let hex = UInt32(s.dropFirst().prefix(6), radix: 16), s.count >= 7 { return Color(hex: hex) }
        let base = s.replacingOccurrences(of: "super-light-", with: "").replacingOccurrences(of: "semi-dark-", with: "")
            .replacingOccurrences(of: "light-", with: "").replacingOccurrences(of: "dark-", with: "")
        switch base {
        case "green": return Brand.Tone.ok
        case "red": return Brand.Tone.stop
        case "orange", "yellow": return Brand.Tone.wait
        case "blue", "purple": return Brand.Tone.lilac
        case "transparent", "text", "": return Brand.Tone.paper
        default: return Brand.Tone.paper
        }
    }

    // MARK: Units

    static func format(_ value: Double, unit: String?, decimals: Int?) -> String {
        switch unit ?? "" {
        case "percentunit": return plain(value * 100, decimals: decimals ?? (value * 100 >= 100 ? 0 : 1)) + "%"
        case "percent": return plain(value, decimals: decimals ?? (value >= 100 ? 0 : 1)) + "%"
        case "s": return duration(seconds: value)
        case "ms": return duration(seconds: value / 1000)
        case "µs", "us": return duration(seconds: value / 1_000_000)
        case "ns": return duration(seconds: value / 1_000_000_000)
        case "m": return duration(seconds: value * 60)
        case "h": return duration(seconds: value * 3600)
        case "d": return duration(seconds: value * 86400)
        case "bytes": return bytes(value, base: 1024, units: ["B", "KiB", "MiB", "GiB", "TiB", "PiB"])
        case "decbytes": return bytes(value, base: 1000, units: ["B", "kB", "MB", "GB", "TB", "PB"])
        case "short": return short(value, decimals: decimals)
        case "dateTimeFromNow": return fromNow(epochMillis: value)
        case "dateTimeAsIso", "dateTimeAsUS", "dateTimeAsLocal":
            return Date(timeIntervalSince1970: value / 1000).formatted(date: .abbreviated, time: .shortened)
        default: return plain(value, decimals: decimals)
        }
    }

    static func plain(_ value: Double, decimals: Int?) -> String {
        guard value.isFinite else { return "–" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = abs(value) >= 10_000
        if let decimals {
            f.minimumFractionDigits = decimals
            f.maximumFractionDigits = decimals
        } else {
            f.minimumFractionDigits = 0
            f.maximumFractionDigits = abs(value) >= 100 ? 0 : 2
        }
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func short(_ value: Double, decimals: Int?) -> String {
        let a = abs(value)
        if a >= 1e9 { return plain(value / 1e9, decimals: decimals ?? 1) + " B" }
        if a >= 1e6 { return plain(value / 1e6, decimals: decimals ?? 1) + " M" }
        if a >= 1e3 { return plain(value / 1e3, decimals: decimals ?? 1) + " k" }
        return plain(value, decimals: decimals)
    }

    static func bytes(_ value: Double, base: Double, units: [String]) -> String {
        var v = value
        var i = 0
        while abs(v) >= base, i < units.count - 1 {
            v /= base
            i += 1
        }
        return plain(v, decimals: i == 0 ? 0 : 1) + " " + units[i]
    }

    static func duration(seconds: Double) -> String {
        let a = abs(seconds)
        if a >= 86400 { return plain(seconds / 86400, decimals: 1) + " d" }
        if a >= 3600 { return plain(seconds / 3600, decimals: 1) + " h" }
        if a >= 60 { return plain(seconds / 60, decimals: 1) + " min" }
        if a >= 1 { return plain(seconds, decimals: 2) + " s" }
        if a >= 0.001 { return plain(seconds * 1000, decimals: 0) + " ms" }
        return plain(seconds * 1_000_000, decimals: 0) + " µs"
    }

    static func fromNow(epochMillis: Double) -> String {
        let date = Date(timeIntervalSince1970: epochMillis / 1000)
        let seconds = Date().timeIntervalSince(date)
        if seconds < 0 { return "in " + GrafanaDates.age(since: Date(), now: date) }
        if seconds < 60 { return "just now" }
        return GrafanaDates.age(since: date) + " ago"
    }
}
