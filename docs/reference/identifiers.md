---
type: reference
owner: CJ
reviewed: 2026-09-29
review: each milestone
---

# Identifiers

Decided 2026-09-28. Change here first, then everywhere the row names.

| Identifier | Value | Used by |
|---|---|---|
| Product name | Brazier | App Store, Xcode display name, Keystone application |
| Subtitle | Alerts and dashboards for self-hosted Grafana | App Store only |
| Bundle id | `org.guysinc.brazier` | Xcode, App Store Connect, APNs topic, relay `APNS_TOPIC` |
| URL scheme | `brazier://`, callback `brazier://auth/callback` | Keystone redirect URI, ASWebAuthenticationSession |
| Keystone application | slug `brazier`, provider 46, public client, PKCE S256, grants authorization_code + refresh_token, scopes openid profile email offline_access, redirect `brazier://auth/callback` | created 2026-09-28; client id `vgG1mB1fiCSYrsS2Y7zK7CMd5GdlE5USYP5tIqJh`; issuer `https://keystone.gicloud.org/application/o/brazier/`; JWKS `https://keystone.gicloud.org/application/o/brazier/jwks/` |
| Relay hostname | `brazier.gicloud.org` | Worker custom domain; Grafana contact point URL `https://brazier.gicloud.org/grafana`; also a Worker route `grafana.gicloud.org/.well-known/brazier*` (zone gicloud.org) serving the discovery document on Grafana's hostname |
| Worker | `brazier-relay`, KV binding `DEVICES` (namespace `66a331538cd347f1b026da1f61090bea`, title `brazier-relay-DEVICES`) | `relay/wrangler.jsonc`; deployed 2026-09-29 |
| Apple team | 7VM43528YK | signing, APNs provider token |
| Apple App ID | `org.guysinc.brazier`, id WFDZ9J88XU, universal, Push Notifications on | registered 2026-09-28 through the App Store Connect API |
| App Store Connect API key | 9258LNDGUM (Admin), on the Mac mini under the claude user | `make archive upload` in `app/` (cloud-managed distribution signing) |
| App Store Connect app record | id 6817156133, name Brazier, SKU `brazier`, created by CJ 2026-09-29 | TestFlight; first build 0.1.0 (1) uploaded 2026-09-29 |
| Development certificate | Xcode-managed, created on the Mac mini for the claude user 2026-09-29; key in `claude.keychain-db` | archive signing; distribution signing is cloud-managed at export |
| APNs key | id `PTDYNZWJJJ`, Brazier's own, created 2026-09-29, valid for sandbox and production (Apple caps team-scoped keys at two; the first attempt `S422GAVQ85` came out sandbox-only and is unused; Honeywick's team key `4B7QX469NS` carried the relay for an hour and is no longer used here). The .p8 is at `/root/.config/brazier/` on mitochondria and beside the App Store Connect key on the Mac mini (claude user), mode 600 | relay var `APNS_KEY_ID`, secret `APNS_KEY`; production push proven through the relay 2026-09-29 |
| Push grant | `grant.brazier.gicloud.org`, Worker `brazier-grant`, KV binding `RELAYS` (namespace `93ff6b4fff214ccf80a08f8f4d849256`), secret `APNS_KEY` = the key above; deployed 2026-09-29 | `grant/wrangler.jsonc`; decision 0005; a self-hosted relay sets `PUSH_GRANT_URL` + `PUSH_GRANT_KEY` |
| Our relay's grant key | registered 2026-09-29 as the first relay, key at `/root/.config/brazier/relay-grant-key` (mode 600) on mitochondria; unused by our relay, which signs with its own key | proof of the flow; `POST /grant` test |
| Grafana JWT auth | header `X-JWT-Assertion`, JWKS = the Keystone app above, expect_claims iss + aud, lookup by email, auto sign-up off | `/opt/monitoring/docker-compose.yml`, grafana service, since 2026-09-28 |
| Grafana contact point | `brazier`, webhook `https://brazier.gicloud.org/grafana`, HMAC secret `BRAZIER_WEBHOOK_SECRET` from `/opt/monitoring/.env` | `grafana/provisioning/alerting/contact-points.yml` |
| Demo Grafana | `https://demo.brazier.gicloud.org`, Grafana 13.2.3 on the OVH box under `/opt/brazier-demo` (Docker Compose, `127.0.0.1:3010`, nginx gate on `0.0.0.0:8880` that needs the `X-Demo-Key` header), provisioned from `demo/stack/` | Apple's reviewer and anyone trying the app; created 2026-09-29 |
| Demo Worker | `brazier-demo`, custom domain `demo.brazier.gicloud.org`, var `ORIGIN`, secret `DEMO_KEY`; answers `/.well-known/brazier` from the relay | `demo/wrangler.jsonc`; deployed 2026-09-29 |
| Demo credentials | login `reviewer` (org Editor); the password, the admin password and the gate key are in `/root/.config/brazier/demo-credentials` on mitochondria (mode 600) | App Store Connect review notes; never in the repository |
| Layout | `relay/` Worker (TypeScript) · `app/` Xcode project `Brazier.xcodeproj` · `docs/` · `assets/brand/` · `design/` | |
| Icon, favicon | `assets/brand/icon/brazier-icon-tonal-on-ink-1024.png`, `brazier-icon-tonal.ico` | Xcode asset catalog, docs site |
| Build guide | https://claude.ai/artifact/1sGCorNw9aoR5jXTEvzhjz | the page this repository mirrors |
