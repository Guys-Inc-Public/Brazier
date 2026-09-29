import SwiftUI
import WebKit

/// Grafana's own page in kiosk mode, with the sign-in carried over so the page's own requests are
/// signed in too, not only the first load.
///   · A session server writes its cookie jar into the web view's store before the load.
///   · A token or provider server loads the page with its header (`Authorization: Bearer`, or
///     `X-JWT-Assertion`): Grafana 11, 12 and 13 all render `/d/<uid>` signed in from that header. But
///     the header rides on that one request only, and Grafana's JWT `url_login` (`?auth_token=`) sets
///     no session cookie on any of the three, so a script patches `fetch` and `XMLHttpRequest` before
///     the page runs: every same-origin request the page makes then carries the same header.
///     An ID token that lapses while a dashboard stays open makes the page's requests 401 until the
///     dashboard is reopened; the app refreshes the token on the next open.
///   · A session the page rotates (Grafana does, every ten minutes of use) is read back into the
///     keychain after each load, once a minute, and when the page goes away.
///   · A visitor's page starts with no Grafana session for the host, whatever an earlier sign-in left.
struct DashboardWebView: View {
    @Environment(AppModel.self) private var model
    let hit: SearchHit
    @State private var page: Page?
    @State private var fault: String?

    fileprivate struct Page {
        var request: URLRequest
        var cookies: [HTTPCookie] = []
        var script: WKUserScript?
        /// A visitor's page: any Grafana session left in the web view's store for this host is removed first.
        var clearsSession = false
    }

    var body: some View {
        Group {
            if let fault {
                FaultCard(fault: Fault(at: Date(), call: "GET /d/\(hit.uid)", reason: fault)) {
                    self.fault = nil
                    page = nil
                    Task { await prepare() }
                }
                .padding(Brand.Space.card)
                .frame(maxHeight: .infinity, alignment: .top)
            } else if let page {
                WebPage(page: page, onFailure: { fault = $0 }, onCookies: { cookies in Task { await keep(cookies) } })
            } else {
                WarmingBay(name: hit.title)
            }
        }
        .background(Brand.Tone.ink)
        .navigationTitle(hit.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
    }

    private func prepare() async {
        guard let server = model.selectedServer else { return }
        var components = URLComponents(url: server.url.appending(path: "d/\(hit.uid)"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let org = hit.orgId { items.append(URLQueryItem(name: "orgId", value: String(org))) }
        items += [URLQueryItem(name: "kiosk", value: nil), URLQueryItem(name: "theme", value: "dark")]
        components.queryItems = items
        let request = URLRequest(url: components.url!)
        do {
            let credential = try await model.credentials.credential(for: server)
            switch credential {
            case .cookie(let header):
                page = Page(request: request, cookies: Self.cookies(from: header, for: server.url))
            case .bearer, .jwt:
                var signed = request
                credential.apply(to: &signed)
                if let header = credential.header {
                    page = Page(request: signed, script: Self.headerScript(header, origin: server.origin))
                } else {
                    page = Page(request: signed)
                }
            case .none:
                page = Page(request: request, clearsSession: true)
            }
        } catch {
            fault = error.localizedDescription
        }
    }

    /// Grafana rotates the session cookie every ten minutes of use, inside the page as much as in the
    /// API; whatever the page ends up holding goes back to the keychain so the next API call is signed in.
    private func keep(_ cookies: [HTTPCookie]) async {
        guard let server = model.selectedServer, server.isSession, let host = server.url.host?.lowercased() else { return }
        let mine = cookies.filter { $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host }
        guard let session = mine.first(where: { $0.name == "grafana_session" }), !session.value.isEmpty else { return }
        let expiry = mine.first { $0.name == "grafana_session_expiry" }?.value
        await model.credentials.rotateSession(cookie: session.value, expiry: expiry, for: server)
    }

    /// The stored Cookie header as cookies for the host: every pair, Grafana's and any gate's.
    static func cookies(from header: String, for url: URL) -> [HTTPCookie] {
        guard let host = url.host else { return [] }
        return header.split(separator: ";").compactMap { pair -> HTTPCookie? in
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { return nil }
            let name = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            guard !name.isEmpty else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: host,
                .path: "/",
            ]
            if url.scheme == "https" { properties[.secure] = "TRUE" }
            return HTTPCookie(properties: properties)
        }
    }

    /// Runs before the page: `fetch` and `XMLHttpRequest` get the header on every request to the
    /// server's origin, and no other. The name, value and origin go in as JSON string literals.
    static func headerScript(_ header: (name: String, value: String), origin: String) -> WKUserScript {
        let source = """
        (function () {
          var NAME = \(jsString(header.name)), VALUE = \(jsString(header.value)), ORIGIN = \(jsString(origin));
          function same(u) {
            try { return new URL(String(u), location.href).origin === ORIGIN; } catch (e) { return false; }
          }
          var fetch0 = window.fetch;
          window.fetch = function (input, init) {
            try {
              var url = typeof input === "string" ? input : (input && input.url) || "";
              if (same(url)) {
                init = init || {};
                var h = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
                h.set(NAME, VALUE);
                init.headers = h;
              }
            } catch (e) {}
            return fetch0.call(this, input, init);
          };
          var open0 = XMLHttpRequest.prototype.open, send0 = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (m, u) { this.__brazierSame = same(u); return open0.apply(this, arguments); };
          XMLHttpRequest.prototype.send = function () {
            try { if (this.__brazierSame) this.setRequestHeader(NAME, VALUE); } catch (e) {}
            return send0.apply(this, arguments);
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal
    }
}

private struct WebPage: UIViewRepresentable {
    let page: DashboardWebView.Page
    let onFailure: (String) -> Void
    /// The store's cookies as the page left them: after each load, once a minute while it stays open,
    /// and when the view goes away.
    let onCookies: ([HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure, onCookies: onCookies) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if let script = page.script { configuration.userContentController.addUserScript(script) }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(Brand.Tone.ink)
        view.scrollView.backgroundColor = UIColor(Brand.Tone.ink)
        let store = configuration.websiteDataStore.httpCookieStore
        let request = page.request
        let host = request.url?.host?.lowercased() ?? ""
        if page.clearsSession {
            // A visitor: whatever session an earlier sign-in left for this host must not sign the page in.
            store.getAllCookies { cookies in
                let stale = cookies.filter { $0.name.hasPrefix("grafana_session") && $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host }
                let pending = DispatchGroup()
                for cookie in stale {
                    pending.enter()
                    store.delete(cookie) { pending.leave() }
                }
                pending.notify(queue: .main) { view.load(request) }
            }
        } else if page.cookies.isEmpty {
            view.load(request)
        } else {
            // Every cookie is in the store before the first request leaves.
            let pending = DispatchGroup()
            for cookie in page.cookies {
                pending.enter()
                store.setCookie(cookie) { pending.leave() }
            }
            pending.notify(queue: .main) { view.load(request) }
        }
        context.coordinator.watch(view)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        coordinator.readCookies(from: uiView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onFailure: (String) -> Void
        let onCookies: ([HTTPCookie]) -> Void
        private var timer: Timer?

        init(onFailure: @escaping (String) -> Void, onCookies: @escaping ([HTTPCookie]) -> Void) {
            self.onFailure = onFailure
            self.onCookies = onCookies
        }

        func watch(_ webView: WKWebView) {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.readCookies(from: webView)
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        func readCookies(from webView: WKWebView) {
            let handler = onCookies
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { handler($0) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            readCookies(from: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            onFailure(error.localizedDescription)
        }
    }
}
