---
type: concept
owner: CJ
reviewed: 2026-09-29
review: each milestone
---

# How the pieces fit

## In one paragraph
The app on the phone signs in on Grafana's own login page (Keystone behind it, for the estate) and calls Grafana's API with that session. Grafana's alerting posts firing and resolved alerts to the relay, a Cloudflare Worker, which verifies the signature, routes by label, and pushes through APNs. The app registers its device token with the relay using the same Grafana credential, and the relay asks that Grafana who it is (decision 0004).

## The system
![The app, the relay and what they talk to](../diagrams/system.svg)

| Part | Where | Job |
|---|---|---|
| The app | iPhone, SwiftUI, iOS 17+ | Servers, alerts, silences, dashboards in a web view, push registration |
| Push relay | Cloudflare Worker, KV | Receives Grafana's webhook, routes by site label, pushes through APNs, keeps the device registry |
| Keystone | OVH, keystone.gicloud.org | The estate's single sign-on behind Grafana's login page; optional OIDC client for the advanced path |
| Grafana | mitochondria, 13.2.1 | Login page, alerting API, silences, search, dashboards; a webhook contact point; JWT auth for the advanced path |
| APNs | Apple | Delivers the push; needs a key from the developer account |

| From → to | What travels | How |
|---|---|---|
| App → Grafana | sign in | Grafana's `/login` in a web view (password or SSO); the `grafana_session` cookie kept and renewed; or a service-account token; or, advanced, OIDC with PKCE and Grafana's JWT auth |
| App → Grafana | alerts, silences, search, health | HTTPS through the tunnel with the session cookie, bearer token or `X-JWT-Assertion` |
| Grafana → relay | firing, resolved | Webhook contact point, HMAC-SHA256 over the body |
| App → relay | device token | HTTPS with the same Grafana credential in headers; the relay asks Grafana `/api/user` |
| Relay → APNs | notification | HTTP/2, provider token auth, collapse-id = alert fingerprint |
| Relay → KV | devices, dedupe | KV get and put, sent fingerprints expire after 7 days |

## The push grant and the demo

Two more Workers stand beside the relay since 2026-09-29. The push grant (`grant/`, decision 0005) holds
Brazier's APNs key: a self-hosted relay registers by its public address, is checked for the discovery
document a relay serves, gets a key, and asks for a fresh 50-minute provider token at most once a minute.
Pushes still go from that relay straight to Apple; the grant never sees an alert. The demo (`demo/`) is
a Grafana on synthetic data for Apple's reviewer and for anyone trying the app: a compose stack on the
OVH box behind a gate that wants a key, and a Worker on `demo.brazier.gicloud.org` that forwards to it
and answers the discovery document, so the address alone leads to the relay.

## The relay
![Inside the relay](../diagrams/relay.svg)

One Worker, two routes, one KV namespace, two secrets. Routes, settings and payload mapping: [Relay reference](../reference/relay.md). The boards are `docs/diagrams/*.board.json`, rendered with Branding-Standards' `scripts/render_board.js`.
