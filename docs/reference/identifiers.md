---
type: reference
owner: CJ
reviewed: 2026-09-28
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
| Keystone application | slug `brazier`, public client, PKCE, grants authorization_code + refresh_token, scopes openid profile email offline_access | created with the Keystone MCP `create_application` tool; JWKS `https://keystone.gicloud.org/application/o/brazier/jwks/` |
| Relay hostname | `brazier.gicloud.org` | Worker custom domain; Grafana contact point URL `https://brazier.gicloud.org/grafana` |
| Worker | `brazier-relay`, KV binding `DEVICES` | `relay/wrangler.jsonc` |
| Apple team | 7VM43528YK | signing, APNs provider token |
| App Store Connect API key | 9258LNDGUM (Admin), on the Mac mini under the claude user | fastlane upload |
| APNs key | to be created by CJ; id recorded here when it exists | relay secret `APNS_KEY_ID` |
| Layout | `relay/` Worker (TypeScript) · `app/` Xcode project `Brazier.xcodeproj` · `docs/` · `assets/brand/` · `design/` | |
| Icon, favicon | `assets/brand/icon/brazier-icon-tonal-on-ink-1024.png`, `brazier-icon-tonal.ico` | Xcode asset catalog, docs site |
| Build guide | https://claude.ai/artifact/1sGCorNw9aoR5jXTEvzhjz | the page this repository mirrors |
