import SwiftUI

/// The mark and the product name, top left of every surface. The mark is artwork from
/// assets/brand; under 48px the small cut keeps its light.
struct HeaderMark: View {
    var body: some View {
        HStack(spacing: Brand.Space.inline) {
            Image("MarkSmall")
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text("BRAZIER")
                .font(BrandFont.archivo(16, weight: 900))
                .tracking(-0.6)
                .foregroundStyle(Brand.Tone.paper)
        }
        .accessibilityLabel("Brazier")
    }
}

/// Account, top right: the mounted server and who we are on it. Opens the server list.
struct ServerMenu: View {
    @Environment(AppModel.self) private var model

    private var signal: Signal {
        switch model.bay {
        case .mounted: return .ok
        case .warming: return .wait
        case .faulted: return .stop
        case .blank: return .none
        }
    }

    var body: some View {
        Menu {
            ForEach(model.store.servers) { server in
                Button {
                    model.select(server)
                } label: {
                    if server.id == model.selectedServerID {
                        Label(server.name, systemImage: "checkmark")
                    } else {
                        Text(server.name)
                    }
                }
            }
            if model.store.servers.isEmpty {
                Text("No servers yet")
            }
        } label: {
            HStack(spacing: Brand.Space.inline) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(model.selectedServer?.name ?? "No server")
                        .font(BrandFont.label)
                        .foregroundStyle(Brand.Tone.paper)
                        .lineLimit(1)
                    Text(model.accountName ?? (model.selectedServer == nil ? "add one in settings" : "not signed in"))
                        .font(BrandFont.mono(10))
                        .foregroundStyle(Brand.Tone.muted)
                        .lineLimit(1)
                }
                Lamp(signal: signal)
            }
            .frame(minHeight: Brand.hitTarget)
        }
        .accessibilityLabel("Server: \(model.selectedServer?.name ?? "none")")
    }
}
