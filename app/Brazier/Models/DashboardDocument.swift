import Foundation

/// The parts of a dashboard's JSON the tiles read: its stat panels, their queries, units, thresholds
/// and value mappings. Rows are flattened; everything else in the document is left where it is.
struct DashboardResponse: Decodable {
    let dashboard: DashboardDocument
}

struct DashboardDocument: Decodable {
    let title: String
    let uid: String?
    let panels: [Panel]

    private enum CodingKeys: String, CodingKey { case title, uid, panels }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        uid = try c.decodeIfPresent(String.self, forKey: .uid)
        let raw = try c.decodeIfPresent([Panel].self, forKey: .panels) ?? []
        panels = raw.flatMap { $0.type == "row" ? ($0.panels ?? []) : [$0] }
    }

    /// The panels the tiles can render, in the dashboard's own order.
    var statPanels: [Panel] {
        panels.filter { $0.type == "stat" }.sorted { ($0.gridPos?.y ?? 0, $0.gridPos?.x ?? 0) < ($1.gridPos?.y ?? 0, $1.gridPos?.x ?? 0) }
    }
}

struct Panel: Decodable, Identifiable {
    let id: Int?
    let type: String
    let title: String?
    let gridPos: GridPos?
    let datasource: DataSourceRef?
    let targets: [JSONValue]
    let fieldConfig: FieldConfig?
    let options: PanelOptions?
    let panels: [Panel]?

    private enum CodingKeys: String, CodingKey { case id, type, title, gridPos, datasource, targets, fieldConfig, options, panels }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title)
        gridPos = try c.decodeIfPresent(GridPos.self, forKey: .gridPos)
        datasource = try? c.decodeIfPresent(DataSourceRef.self, forKey: .datasource)
        targets = (try? c.decodeIfPresent([JSONValue].self, forKey: .targets)) ?? []
        fieldConfig = try? c.decodeIfPresent(FieldConfig.self, forKey: .fieldConfig)
        options = try? c.decodeIfPresent(PanelOptions.self, forKey: .options)
        panels = try? c.decodeIfPresent([Panel].self, forKey: .panels)
    }

    var key: String { "\(id ?? -1):\(title ?? "")" }
}

struct GridPos: Decodable {
    let x: Int?
    let y: Int?
    let w: Int?
    let h: Int?
}

/// `{type, uid}` in new dashboards; a bare datasource name in old ones, which the tiles cannot resolve.
struct DataSourceRef: Decodable {
    let type: String?
    let uid: String?

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            type = try c.decodeIfPresent(String.self, forKey: .type)
            uid = try c.decodeIfPresent(String.self, forKey: .uid)
        } else {
            type = nil
            uid = nil
        }
    }

    private enum CodingKeys: String, CodingKey { case type, uid }

    var json: JSONValue {
        var o: [String: JSONValue] = [:]
        if let type { o["type"] = .string(type) }
        if let uid { o["uid"] = .string(uid) }
        return .object(o)
    }
}

struct FieldConfig: Decodable {
    let defaults: FieldDefaults?
}

struct FieldDefaults: Decodable {
    let unit: String?
    let decimals: Int?
    let thresholds: Thresholds?
    let mappings: [ValueMapping]?
    let displayName: String?
}

struct Thresholds: Decodable {
    let mode: String?
    let steps: [ThresholdStep]?
}

struct ThresholdStep: Decodable {
    let color: String?
    let value: Double?
}

/// Grafana's value mappings: `value` (exact matches keyed by text), `range` (from…to) and `special`
/// (null and friends). Each result may replace the text and the colour.
struct ValueMapping: Decodable {
    let type: String?
    let options: JSONValue?

    struct Result {
        let text: String?
        let color: String?
    }

    /// The first result that applies to a number, if this mapping has one.
    func result(for value: Double) -> Result? {
        guard let options else { return nil }
        switch type {
        case "value":
            guard let table = options.object else { return nil }
            for (key, entry) in table {
                if let k = Double(key), k == value { return Self.result(entry) }
            }
            return nil
        case "range":
            let from = options["from"]?.double ?? -.infinity
            let to = options["to"]?.double ?? .infinity
            guard value >= from, value <= to, let entry = options["result"] else { return nil }
            return Self.result(entry)
        default:
            return nil
        }
    }

    private static func result(_ entry: JSONValue) -> Result {
        Result(text: entry["text"]?.string, color: entry["color"]?.string)
    }
}

struct PanelOptions: Decodable {
    let reduceOptions: ReduceOptions?
    let textMode: String?
    let colorMode: String?
}

struct ReduceOptions: Decodable {
    let calcs: [String]?
    let fields: String?
    let values: Bool?
}

// MARK: /api/ds/query

struct DataQueryRequest: Encodable {
    let from: String
    let to: String
    let queries: [JSONValue]
}

struct DataQueryResponse: Decodable {
    let results: [String: QueryResult]
}

struct QueryResult: Decodable {
    let frames: [DataFrame]?
    let error: String?
    let status: Int?
}

struct DataFrame: Decodable {
    let schema: FrameSchema
    let data: FrameData?
}

struct FrameSchema: Decodable {
    let name: String?
    let fields: [FrameField]
}

struct FrameField: Decodable {
    let name: String?
    let type: String?
    let labels: [String: String]?
    let config: FrameFieldConfig?
}

struct FrameFieldConfig: Decodable {
    let displayName: String?
    let displayNameFromDS: String?
    let unit: String?
}

struct FrameData: Decodable {
    let values: [[JSONValue]]
}
