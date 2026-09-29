import SwiftUI

/// A dashboard's stat panels as native tiles: a grid of readings, each in the colour its thresholds
/// give it. Reads every panel at once, again on pull and every minute while on the screen.
struct TilesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let hit: SearchHit
    let document: DashboardDocument
    @State private var readings: [TileReading] = []
    @State private var asOf: Date?
    @State private var reading = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Brand.Space.label, alignment: .top), count: sizeClass == .regular ? 4 : 2)
    }

    var body: some View {
        Group {
            if document.statPanels.isEmpty {
                BlankBay(title: "No stat panels", text: "Tiles come from a dashboard's stat panels; this one has none. The page shows everything.")
            } else if readings.isEmpty && reading {
                WarmingBay(name: document.title)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Space.card) {
                        ForEach(runs) { run in
                            if let title = run.title {
                                Eyebrow(title).padding(.top, Brand.Space.inline)
                            }
                            LazyVGrid(columns: columns, alignment: .leading, spacing: Brand.Space.label) {
                                ForEach(run.tiles) { tile in
                                    TileView(tile: tile)
                                }
                            }
                        }
                    }
                    .padding(Brand.Space.card)
                }
                .refreshable { await read() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Hairline()
                HStack {
                    AsOfStamp(asOf: asOf, failedAt: nil)
                    Spacer()
                    Eyebrow("\(document.statPanels.count) panels · last 6 h")
                }
                .padding(.horizontal, Brand.Space.card).padding(.vertical, Brand.Space.inline)
            }
            .background(Brand.Tone.ink)
        }
        .task(id: hit.id) {
            await read()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { await read() }
            }
        }
    }

    // MARK: Runs

    /// Consecutive single-reading panels share one grid; a panel with several series gets its own, titled.
    private struct Run: Identifiable {
        let id: String
        let title: String?
        let tiles: [Tile]
    }

    struct Tile: Identifiable {
        let id: String
        let eyebrow: String
        let series: TileSeries?
        let fault: String?
        let showsName: Bool
    }

    private var runs: [Run] {
        var runs: [Run] = []
        var pending: [Tile] = []
        func flush() {
            if !pending.isEmpty { runs.append(Run(id: "run\(runs.count)", title: nil, tiles: pending)); pending = [] }
        }
        for r in readings {
            if let fault = r.fault {
                pending.append(Tile(id: r.id, eyebrow: r.title, series: nil, fault: fault, showsName: false))
            } else if r.showsNames, r.series.count > 1 {
                flush()
                runs.append(Run(id: r.id, title: r.title, tiles: r.series.map {
                    Tile(id: "\(r.id):\($0.id)", eyebrow: $0.name, series: $0, fault: nil, showsName: false)
                }))
            } else if let first = r.series.first {
                // One series: the label line only when it is the series' own name and the panel asked for it;
                // a frame name like "A-series" or the query text is noise under a number.
                let asked = r.panel.options?.textMode == "value_and_name" || r.panel.options?.textMode == "name"
                pending.append(Tile(id: r.id, eyebrow: r.title, series: first, fault: nil, showsName: asked && first.named))
            } else {
                pending.append(Tile(id: r.id, eyebrow: r.title, series: nil, fault: "No data", showsName: false))
            }
        }
        flush()
        return runs
    }

    // MARK: Reading

    private func read() async {
        guard let server = model.selectedServer, !reading else { return }
        reading = true
        defer { reading = false }
        let client = model.client(for: server)
        let panels = Array(document.statPanels.prefix(TileReader.maxPanels))
        let results = await withTaskGroup(of: (Int, TileReading).self) { group in
            for (i, panel) in panels.enumerated() {
                group.addTask {
                    var r = TileReading(panel: panel)
                    guard let request = TileReader.request(for: panel) else {
                        r.fault = "No query the app can run"
                        return (i, r)
                    }
                    do {
                        let response = try await client.query(request, org: hit.orgId)
                        r.series = try TileReader.series(from: response, panel: panel)
                    } catch {
                        r.fault = error.localizedDescription
                    }
                    return (i, r)
                }
            }
            var out: [(Int, TileReading)] = []
            for await item in group { out.append(item) }
            return out.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        readings = results
        asOf = Date()
    }
}

/// One reading: the panel's name in mono, the number large in its colour, the series under it.
struct TileView: View {
    let tile: TilesView.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Space.inline) {
            Eyebrow(tile.eyebrow).lineLimit(1)
            if let series = tile.series {
                Text(series.text)
                    .font(BrandFont.archivo(28, weight: 800))
                    .foregroundStyle(series.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if tile.showsName {
                    Text(series.name).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(1)
                }
            } else if let fault = tile.fault {
                HStack(spacing: Brand.Space.inline) {
                    Lamp(signal: .stop, size: 7)
                    Text(fault).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(Brand.Space.label)
        .background(Brand.Tone.surface)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))
    }
}
