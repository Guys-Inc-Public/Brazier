import SwiftUI

/// A bay is always mounted, warming, blank or faulted. Never "loading".
struct BlankBay: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            Eyebrow("blank")
            Text(title).font(BrandFont.title).foregroundStyle(Brand.Tone.paper)
            Text(text).font(BrandFont.body).foregroundStyle(Brand.Tone.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Brand.Space.card)
    }
}

struct WarmingBay: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            HStack(spacing: Brand.Space.label) {
                MeterBridge()
                Eyebrow("warming")
            }
            Text(name).font(BrandFont.lead).foregroundStyle(Brand.Tone.paper)
            Text("Reading the server.").font(BrandFont.body).foregroundStyle(Brand.Tone.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Brand.Space.card)
    }
}

struct FaultedBay: View {
    @Environment(AppModel.self) private var model
    let reason: String
    @State private var latch: ThrowResult?
    @State private var signingIn = false
    @State private var showWeb = false

    private var notSignedIn: Bool { reason == "Not signed in" || reason == "Signed out" }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Space.card) {
            VStack(alignment: .leading, spacing: Brand.Space.label) {
                Eyebrow("faulted", tone: Brand.Tone.stop)
                Text(model.selectedServer?.name ?? "Server").font(BrandFont.title).foregroundStyle(Brand.Tone.paper)
                Text(reason == "Signed out" ? "Grafana ended the session. Sign in again to keep reading." : reason)
                    .font(BrandFont.body).foregroundStyle(Brand.Tone.paper)
            }
            if let latch {
                LatchView(result: latch) { self.latch = nil }
            }
            if notSignedIn, let server = model.selectedServer {
                if signingIn {
                    HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("signing in") }
                } else {
                    switch server.auth {
                    case .session:
                        Button("Sign in again") { showWeb = true }
                            .buttonStyle(ThrowButtonStyle())
                            .fullScreenCover(isPresented: $showWeb) {
                                GrafanaLoginSheet(server: server.url) { cookie, expiry, user in
                                    showWeb = false
                                    signingIn = true
                                    Task {
                                        latch = await model.completeSessionSignIn(server, cookie: cookie, expiry: expiry, user: user)
                                        signingIn = false
                                    }
                                }
                            }
                    case .oidc:
                        Button("Sign in to \(server.name)") {
                            signingIn = true
                            Task {
                                latch = await model.signIn(server)
                                signingIn = false
                            }
                        }
                        .buttonStyle(ThrowButtonStyle())
                    case .token:
                        Text("Paste a new service-account token under Settings › Servers › \(server.name).")
                            .font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
                    }
                }
            } else {
                Button("Read again") { Task { await model.refresh() } }
                    .buttonStyle(ThrowButtonStyle(primary: false))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Brand.Space.card)
    }
}
