import SwiftUI
import WebKit

/// Grafana's own page in kiosk mode. The credential rides on the first request only;
/// milestone 3 decides how the page's own requests carry the session (auth.jwt url_login).
struct DashboardWebView: View {
    @Environment(AppModel.self) private var model
    let hit: SearchHit
    @State private var request: URLRequest?
    @State private var fault: String?

    var body: some View {
        Group {
            if let request {
                WebPage(request: request)
            } else if let fault {
                FaultCard(fault: Fault(at: Date(), call: "credential", reason: fault)).padding(Brand.Space.card)
            } else {
                WarmingBay(name: hit.title)
            }
        }
        .background(Brand.Tone.ink)
        .navigationTitle(hit.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let server = model.selectedServer else { return }
            do {
                var r = try await model.client(for: server).pageRequest(path: "d/\(hit.uid)")
                var comps = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!
                comps.queryItems = [URLQueryItem(name: "kiosk", value: nil), URLQueryItem(name: "theme", value: "dark")]
                r.url = comps.url
                request = r
            } catch {
                fault = error.localizedDescription
            }
        }
    }
}

private struct WebPage: UIViewRepresentable {
    let request: URLRequest

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = UIColor(Brand.Tone.ink)
        view.scrollView.backgroundColor = UIColor(Brand.Tone.ink)
        view.load(request)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
