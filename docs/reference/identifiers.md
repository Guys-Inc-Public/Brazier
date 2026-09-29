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
| Relay hostname | `brazier.gicloud.org` | Worker custom domain; Grafana contact point URL `https://brazier.gicloud.org/grafana` |
| Worker | `brazier-relay`, KV binding `DEVICES` (namespace `66a331538cd347f1b026da1f61090bea`, title `brazier-relay-DEVICES`) | `relay/wrangler.jsonc`; deployed 2026-09-29 |
| Apple team | 7VM43528YK | signing, APNs provider token |
| Apple App ID | `org.guysinc.brazier`, id WFDZ9J88XU, universal, Push Notifications on | registered 2026-09-28 through the App Store Connect API |
| App Store Connect API key | 9258LNDGUM (Admin), on the Mac mini under the claude user | fastlane upload |
| APNs key | id `S422GAVQ85`, created 2026-09-29; the .p8 is at `/root/.config/brazier/` on mitochondria and beside the App Store Connect key on the Mac mini (claude user), both mode 600 | relay var `APNS_KEY_ID`, secret `APNS_KEY` (loaded 2026-09-29) |
| Grafana JWT auth | header `X-JWT-Assertion`, JWKS = the Keystone app above, expect_claims iss + aud, lookup by email, auto sign-up off | `/opt/monitoring/docker-compose.yml`, grafana service, since 2026-09-28 |
| Grafana contact point | `brazier`, webhook `https://brazier.gicloud.org/grafana`, HMAC secret `BRAZIER_WEBHOOK_SECRET` from `/opt/monitoring/.env` | `grafana/provisioning/alerting/contact-points.yml` |
| Layout | `relay/` Worker (TypeScript) · `app/` Xcode project `Brazier.xcodeproj` · `docs/` · `assets/brand/` · `design/` | |
| Icon, favicon | `assets/brand/icon/brazier-icon-tonal-on-ink-1024.png`, `brazier-icon-tonal.ico` | Xcode asset catalog, docs site |
| Build guide | https://claude.ai/artifact/1sGCorNw9aoR5jXTEvzhjz | the page this repository mirrors |
