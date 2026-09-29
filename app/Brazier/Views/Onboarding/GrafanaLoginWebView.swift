import SwiftUI
import WebKit

/// Grafana's own sign-in page, full screen, in a web view with its own throwaway cookie jar.
/// Password or single sign-on, the page decides; a gate in front of Grafana gets its turn first. The
/// sheet watches for Grafana's session cookie and hands back every cookie the host ended up with.
struct GrafanaLoginSheet: View {
    let server: URL
    let onSignedIn: (_ cookie: String, _ expiry: String?, _ user: GrafanaUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Opening the sign-in page"
    @State private var location = ""

    /// The page left the Grafana's host: single sign-on is happening inside a web view, where passkeys cannot.
    private var bounced: Bool {
        guard let host = server.host?.lowercased(), !location.isEmpty else { return false }
        return location.lowercased() != host
    }

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
            if bounced {
                HStack(alignment: .top, spacing: Brand.Space.inline) {
                    Lamp(signal: .wait).padding(.top, 5)
                    Text("This sign-on may need a passkey, which does not work here. If it fails, use a token, or ask your admin to publish Brazier's sign-in for this Grafana.")
                        .font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                }
                .padding(.horizontal, Brand.Space.card)
                .padding(.vertical, Brand.Space.inline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.Tone.surface)
                Hairline()
            }
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

        /// A grafana_session cookie for the server's host means the page thinks we are in; /api/user decides,
        /// asked with every cookie the host holds, so an auth proxy's cookie travels with Grafana's.
        private func check(_ webView: WKWebView) {
            guard !done, !verifying, let host = parent.server.host?.lowercased() else { return }
            let server = parent.server
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.done, !self.verifying else { return }
                let mine = cookies.filter { Self.domain($0.domain, covers: host) }
                guard let session = mine.first(where: { $0.name == "grafana_session" }), !session.value.isEmpty else { return }
                let expiry = mine.first { $0.name == "grafana_session_expiry" }?.value
                let header = Self.header(from: mine)
                self.verifying = true
                self.parent.status = "Checking the session"
                Task { @MainActor in
                    do {
                        let user = try await ServerProbe.user(server, credential: .cookie(header))
                        self.done = true
                        self.parent.status = "Signed in as \(user.login)"
                        self.parent.onSignedIn(header, expiry, user)
                    } catch {
                        self.verifying = false
                        self.parent.status = "Not signed in yet"
                    }
                }
            }
        }

        /// One Cookie header from the jar: the most specific domain wins when a name repeats.
        static func header(from cookies: [HTTPCookie]) -> String {
            var seen = Set<String>()
            var pairs: [String] = []
            for cookie in cookies.sorted(by: { $0.domain.count > $1.domain.count }) where !seen.contains(cookie.name) {
                seen.insert(cookie.name)
                pairs.append("\(cookie.name)=\(cookie.value)")
            }
            return pairs.joined(separator: "; ")
        }

        static func domain(_ domain: String, covers host: String) -> Bool {
            let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !d.isEmpty && (host == d || host.hasSuffix("." + d))
        }
    }
}
