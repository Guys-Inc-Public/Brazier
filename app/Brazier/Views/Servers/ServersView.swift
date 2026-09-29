import SwiftUI

/// The rack: one unit per server. Name over host, lamp for mounted state, the auth word.
struct ServersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.store.servers) { server in
                    NavigationLink(value: server) {
                        HStack(spacing: Brand.Space.label) {
                            Lamp(signal: server.id == model.selectedServerID ? (model.bay == .mounted ? .ok : .wait) : .none)
                            Nameplate(name: server.name, host: server.host)
                            Spacer()
                            StateChip(word: server.authWord, signal: .none)
                        }
                        .frame(minHeight: Brand.hitTarget)
                    }
                    .listRowBackground(Brand.Tone.ink)
                    .listRowSeparatorTint(Brand.Tone.line)
                }
                NavigationLink {
                    AddServerView()
                } label: {
                    HStack(spacing: Brand.Space.label) {
                        Image(systemName: "plus").foregroundStyle(Brand.Tone.hot)
                        Text("Add a server").font(BrandFont.label).foregroundStyle(Brand.Tone.hot)
                    }
                    .frame(minHeight: Brand.hitTarget)
                }
                .listRowBackground(Brand.Tone.ink)
                .listRowSeparatorTint(Brand.Tone.line)
            } header: {
                Eyebrow("servers").textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.Tone.ink)
        .navigationTitle("Servers")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Server.self) { ServerDetailView(serverID: $0.id) }
    }
}
