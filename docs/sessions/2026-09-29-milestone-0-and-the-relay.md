---
session: 2026-09-29-milestone-0-and-the-relay
repo: Guys-Inc-Public/Brazier
branch: main
driver: CJ, with Claude Code
outcome: merged
---

# Milestone 0 closed, the relay live, the app on TestFlight with its walkthrough

## Intent
Start the build from the guide: verify the two Grafana assumptions, create the identities the app needs, ship the relay for the estate, and get the SwiftUI app compiling on the Mac mini.

## What was done
- Grafana 13.2.1: every alerting, silence, search and user path in the guide answers 200. JWT auth is on (`X-JWT-Assertion`, Keystone's `brazier` JWKS, expect `iss` and `aud`, lookup by email, no auto sign-up) and was proven with a locally signed token of Keystone's claim shape: it lands on CJ's existing user as Admin, the alerts and silences APIs answer with it, and a wrong audience is refused.
- Keystone application `brazier` (provider 46): public client, PKCE, `brazier://auth/callback`, openid, email, profile and offline_access mappings.
- Apple App ID `org.guysinc.brazier` (WFDZ9J88XU) registered with Push Notifications through the App Store Connect API.
- Relay under `relay/`: one Worker, one KV namespace, HMAC over `timestamp:body` verified against a real Grafana capture, device registry keyed by lower-case username, label routing, 7-day dedupe, APNs with provider tokens, 410 drops the device. 19 tests in the Workers runtime, in CI. Deployed to `brazier.gicloud.org` with the webhook secret; a Blackbox probe watches `/health`.
- App under `app/`: 3,034 lines of Swift, xcodegen project, Servers, Auth, GrafanaClient, Alerts, Push, Settings, a Dashboards stub, the brand's tones and fonts, the Curl. Builds for the simulator with zero warnings and lists the estate's alerts.
- Grafana contact point `brazier` (webhook, HMAC, resolved messages on) provisioned in org 1 and the org's root policy moved to it, loaded with the provisioning reload API, no restart. A temporary rule fired through it: the relay's log shows the signed webhooks verified, parsed and routed, with APNs reported unconfigured.
- APNs: CJ's first key came out sandbox-only (Apple caps team-scoped push keys at two, held by Honeywick and Guys Inc Cloud); Honeywick's team key carried the relay for an hour, then CJ's second key `PTDYNZWJJJ` replaced it. Through the relay, a push to a bogus production token came back from Apple as BadDeviceToken and the device was dropped: transport, provider token and drop path exercised for real.
- App Store Connect: CJ created the app record (6817156133). First archive and upload from the Mac mini as the claude user, cloud-managed distribution signing through the API key; `make archive upload` in `app/` via `scripts/remote.sh`. Version 0.1.0 build 1 uploaded and processing.
- Direction change from CJ mid-session: no presets, public from the first moment, a walkthrough. Decision 0004: sign-in is the Grafana's own login page in a web view (password or SSO), session kept and renewed; token second; OIDC through JWT auth advanced. Relay 0.2.0 verifies a device's owner by asking that Grafana `/api/user` with the app's credential, only for origins on `GRAFANA_URLS`; devices filed by login with email aliases; proven live with a throwaway service-account token. App build 2: Welcome, Server (live probe), Sign in (three methods), Notifications (optional relay with a test, skippable), Done; every preset removed. Boards, architecture page and README follow.
- `docs/reference/identifiers.md` and `relay.md` carry every id created tonight.

## What was learned
- Grafana 13 removed the receiver test endpoint and its replacement accepts no body shape we tried; a temporary rule with `notification_settings.receiver` forces a real send. The signature is hex HMAC-SHA256 over `<timestamp>:<body>`.
- Grafana's `jwk_set_url` must be https; test with `jwk_set_file`. Grafana keys the user on `sub` and syncs login and email from every token, so a test token that reuses a real `sub` with another email renames that user. Grafana refuses `PUT /api/users/:id` on external users; the fix is another token with the right claims.
- Keystone's client-credentials grant answers `invalid_grant` in every form, so no headless ID token; the first real one comes from the app.
- Grafana's OAuth-created user has the email as its login, so the JWT username claim is `email`, not `preferred_username` as the guide first said.
- vitest-pool-workers 0.22 is a Vite plugin (`cloudflareTest`), has no `fetchMock`, and its workerd caps the compatibility date; npm 10.9.8 needs `--legacy-peer-deps` for this dependency set.
- On the Mac, simulators are per user and a simulator build with signing disabled has no entitlements, so keychain writes fail silently; the Makefile signs ad hoc.
- Headless archive: xcodebuild says "User interaction is not allowed" when the build user's keychain is locked or a freshly created signing key has no access list for codesign. The Makefile now unlocks `claude.keychain-db`, sets no timeout and runs `set-key-partition-list`. The first failed attempt still created a development certificate through the API with no local key; Xcode then refused to make another for "this machine" until that orphan was revoked (`DELETE /v1/certificates/:id`).
- A brand-new APNs key takes about a minute to propagate at Apple; the first push right after loading it fails, the next succeeds.
- Cloudflare's browser check on brazier.gicloud.org refuses requests with no User-Agent; Grafana sends one, test clients must too.

## Open
- CJ and Daniel: install build 2 from TestFlight, enter grafana.gicloud.org, sign in on Grafana's page through Keystone, enter the relay brazier.gicloud.org, allow notifications; then a forced alert proves the first real push and a silence from the phone closes milestone 2. Daniel needs the Keystone group `meade-manor-admins` to sign in. The session capture and its ten-minute rotation are unproven until then.
- Grafana orgs 2, 3 and 4 (Guys Inc Public, Personal, Meade Manor) still notify in-app only; copy the `brazier` receiver per org when CJ wants their alerts on the phone.
- Milestone 3: dashboards web view session carry-over, uptime tiles, iPad.
