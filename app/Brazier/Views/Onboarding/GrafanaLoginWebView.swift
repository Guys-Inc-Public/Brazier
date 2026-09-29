import SwiftUI
import WebKit

/// Grafana's own sign-in page, full screen, in a web view with its own throwaway cookie jar.
/// Password or single sign-on, the page decides; the sheet only watches for the session cookie.
struct GrafanaLoginSheet: View {
    let server: URL
    let onSignedIn: (_ cookie: String, _ expiry: String?, _ user: GrafanaUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Opening the sign-in page"
    @State private var location = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Brand.Space.label) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(MomentaryButtonStyle())
                    .padding(.leading, -Brand.Space.inline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Eyebrow(location.isEmpty ? (server.host ?? "") : location)
                    Text(status).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, Brand.Space.card)
            .padding(.vertical, Brand.Space.inline)
            Hairline()
            GrafanaLoginWebView(server: server, status: $status, location: $location, onSignedIn: onSignedIn)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Brand.Tone.ink.ignoresSafeArea())
    }
}

struct GrafanaLoginWebView: UIViewRepresentable {
    let server: URL
    @Binding var status: String
    @Binding var location: String
    let onSignedIn: (String, String?, GrafanaUser) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(Brand.Tone.ink)
        view.scrollView.backgroundColor = UIColor(Brand.Tone.ink)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: server.appending(path: "login")))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: GrafanaLoginWebView
        private var verifying = false
        private var done = false

        init(_ parent: GrafanaLoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let host = webView.url?.host { parent.location = host }
            if !done { parent.status = "Loading" }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let host = webView.url?.host { parent.location = host }
            if !done { parent.status = "Waiting for you to sign in" }
            check(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }

        private func report(_ error: Error) {
            let nsError = error as NSError
            // -999 is a cancelled load; WebKit's 102 is a frame load interrupted by a redirect. Neither is news.
            if nsError.code == NSURLErrorCancelled || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) { return }
            parent.status = error.localizedDescription
        }

        /// A grafana_session cookie for the server's host means the page thinks we are in; /api/user decides.
        private func check(_ webView: WKWebView) {
            guard !done, !verifying, let host = parent.server.host?.lowercased() else { return }
            let server = parent.server
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.done, !self.verifying else { return }
                let mine = cookies.filter { Self.domain($0.domain, covers: host) }
                guard let session = mine.first(where: { $0.name == "grafana_session" }), !session.value.isEmpty else { return }
                let expiry = mine.first { $0.name == "grafana_session_expiry" }?.value
                self.verifying = true
                self.parent.status = "Checking the session"
                Task { @MainActor in
                    do {
                        let user = try await ServerProbe.user(server, credential: .cookie(session.value))
                        self.done = true
                        self.parent.status = "Signed in as \(user.login)"
                        self.parent.onSignedIn(session.value, expiry, user)
                    } catch {
                        self.verifying = false
                        self.parent.status = "Not signed in yet"
                    }
                }
            }
        }

        static func domain(_ domain: String, covers host: String) -> Bool {
            let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !d.isEmpty && (host == d || host.hasSuffix("." + d))
        }
    }
}
