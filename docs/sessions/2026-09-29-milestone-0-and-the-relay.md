---
session: 2026-09-29-milestone-0-and-the-relay
repo: Guys-Inc-Public/Brazier
branch: main
driver: CJ, with Claude Code
outcome: merged
---

# Milestone 0 closed, the relay live, the app building

## Intent
Start the build from the guide: verify the two Grafana assumptions, create the identities the app needs, ship the relay for the estate, and get the SwiftUI app compiling on the Mac mini.

## What was done
- Grafana 13.2.1: every alerting, silence, search and user path in the guide answers 200. JWT auth is on (`X-JWT-Assertion`, Keystone's `brazier` JWKS, expect `iss` and `aud`, lookup by email, no auto sign-up) and was proven with a locally signed token of Keystone's claim shape: it lands on CJ's existing user as Admin, the alerts and silences APIs answer with it, and a wrong audience is refused.
- Keystone application `brazier` (provider 46): public client, PKCE, `brazier://auth/callback`, openid, email, profile and offline_access mappings.
- Apple App ID `org.guysinc.brazier` (WFDZ9J88XU) registered with Push Notifications through the App Store Connect API.
- Relay under `relay/`: one Worker, one KV namespace, HMAC over `timestamp:body` verified against a real Grafana capture, device registry keyed by lower-case username, label routing, 7-day dedupe, APNs with provider tokens, 410 drops the device. 19 tests in the Workers runtime, in CI. Deployed to `brazier.gicloud.org` with the webhook secret; a Blackbox probe watches `/health`.
- App under `app/`: 3,034 lines of Swift, xcodegen project, Servers, Auth, GrafanaClient, Alerts, Push, Settings, a Dashboards stub, the brand's tones and fonts, the Curl. Builds for the simulator with zero warnings and lists the estate's alerts.
- Grafana contact point `brazier` (webhook, HMAC, resolved messages on) provisioned in org 1 and the org's root policy moved to it, loaded with the provisioning reload API, no restart. A temporary rule fired through it: the relay's log shows the signed webhooks verified, parsed and routed, with APNs reported unconfigured.
- `docs/reference/identifiers.md` and `relay.md` carry every id created tonight.

## What was learned
- Grafana 13 removed the receiver test endpoint and its replacement accepts no body shape we tried; a temporary rule with `notification_settings.receiver` forces a real send. The signature is hex HMAC-SHA256 over `<timestamp>:<body>`.
- Grafana's `jwk_set_url` must be https; test with `jwk_set_file`. Grafana keys the user on `sub` and syncs login and email from every token, so a test token that reuses a real `sub` with another email renames that user. Grafana refuses `PUT /api/users/:id` on external users; the fix is another token with the right claims.
- Keystone's client-credentials grant answers `invalid_grant` in every form, so no headless ID token; the first real one comes from the app.
- Grafana's OAuth-created user has the email as its login, so the JWT username claim is `email`, not `preferred_username` as the guide first said.
- vitest-pool-workers 0.22 is a Vite plugin (`cloudflareTest`), has no `fetchMock`, and its workerd caps the compatibility date; npm 10.9.8 needs `--legacy-peer-deps` for this dependency set.
- On the Mac, simulators are per user and a simulator build with signing disabled has no entitlements, so keychain writes fail silently; the Makefile signs ad hoc.

## Open
- CJ: APNs key (.p8) into the relay (`wrangler secret put APNS_KEY`, `APNS_KEY_ID` in wrangler.jsonc), the App Store Connect app record, Daniel as internal tester. (Branding-Standards PR #19 and #20 merged 2026-09-29; plugin 1.14.0.)
- Grafana orgs 2, 3 and 4 (Guys Inc Public, Personal, Meade Manor) still notify in-app only; copy the `brazier` receiver per org when CJ wants their alerts on the phone.
- First real push: register a phone, force an alert, silence it from the phone.
- Milestone 3: dashboards web view session carry-over, uptime tiles, iPad.
