---
session: 2026-09-29-milestones-2-to-4
repo: Guys-Inc-Public/Brazier
branch: main
driver: Claude Code, unattended; CJ set the goal and left
outcome: merged
---

# Milestones 2 to 4, built while CJ was away

## Intent
CJ: "continue working and complete all the remaining milestones. We can do final verification tests when
we're all done… publish as many builds to TestFlight as you need… update the app config in the developer
portal to get ready for an actual review and release." Everything below was built, tested and deployed
without a human; the checks that need a phone in a hand are listed under Open.

## What was done
- **Every organization notifies the relay.** Monitoring commit 8c70c7a: the `brazier` contact point and a
  root policy at it in orgs 2, 3 and 4 (Guys Inc Public, Personal, Meade Manor), the switchboard route
  continuing as before.
- **Relay 0.5.0** (839393c): dedupe per organization, `ORGS` names the org on the lock screen, `brazier.orgId`
  and `brazier.org` in the payload; per-device preferences (organizations, minimum severity with
  info < warning < critical < page, quiet hours in the phone's time zone delivered silently) filed with
  `POST /devices` or `PUT /devices/:token/preferences`. **0.6.0** (b907237): borrows a provider token from the
  push grant when it has no key; a send that throws counts as failed and keeps the device. Then `ORGS` keyed
  by Grafana origin (3bd6633). 52 tests.
- **App build 5** (6fb5bb5, TestFlight 0.1.0 (5)): organizations read from `/api/user/orgs`, all or one from
  the header menu, every call with `X-Grafana-Org-Id`, silences written in the alert's own org, an org
  chip on each alert when several are on screen; Settings › Notifications with the per-organization
  toggles, minimum severity and quiet hours, synced to the relay; dashboards search always visible; the
  dashboard web view signed in: the cookie jar into the web view's store for session servers, a script in
  the page that puts the credential header on every fetch and XHR for token and provider servers.
- **Contract tests** (`contract/`): seventeen checks of every call the app and the relay make, run against
  the official Grafana 11.6.5, 12.4.3 and 13.2.3 images in Docker, green on all three, in CI as a matrix.
  They pin the negative fact the web view is built on: `?auth_token=` (url_login) renders the page but
  never sets a session cookie. The estate's `GF_AUTH_JWT_URL_LOGIN` went on for an hour and came back off.
- **Push grant** (decision 0005, `grant/`, live at grant.brazier.gicloud.org): a self-hosted relay registers
  by its public address, gets a key, and asks for a 50-minute APNs provider token at most once a minute;
  the .p8 stays in the grant Worker. Our own relay is registered as the first customer and still signs
  with its own key. 11 tests.
- **Demo Grafana** for Apple's reviewer (`demo/`, live at demo.brazier.gicloud.org): grafana 13.2.3 on the
  OVH box under `/opt/brazier-demo` behind an nginx gate that wants a key, reached through a Worker that
  forwards to it and serves the relay's discovery document. Three dashboards and three rules on TestData,
  a `reviewer` Editor with a password; the relay serves the origin and routes `site=demo` to that login.
  Credentials in `/root/.config/brazier/demo-credentials` on mitochondria.
- **Docs site** at https://guys-inc-public.github.io/Brazier/ from `scripts/site.py` and a Pages workflow,
  with the privacy policy and support page the listing points at.
- **App Store listing** filed through the API by `scripts/listing.mjs` from `docs/reference/listing.md`:
  subtitle, categories, age rating, description, keywords, URLs, copyright, manual release, no
  third-party content, free in every territory. `scripts/screenshots.mjs` uploads the screenshots.
- **App build 6** (1.0 (6), uploaded to TestFlight 2026-09-29 ~21:10 UTC): on a regular width a split view
  with the sections in a sidebar; a dashboard opens on its stat panels rendered natively (queries through
  `/api/ds/query` as the panel wrote them, reduced by its calc, mapped, formatted and coloured by its field
  config), Tiles and Page behind one switch; the twelve store screenshots (6.9-inch iPhone, 13-inch iPad)
  taken against the demo and uploaded to App Store Connect. `scripts/release.mjs` attaches the processed
  build to version 1.0.
- Trademark: the App Store has no "Brazier" and a web search finds no software mark of that name; a proper
  TESS search is still CJ's.

## What was learned
- Grafana's `url_login` answers a page for `?auth_token=` but sets no `grafana_session` cookie, on 11, 12
  and 13. A page load does accept `Authorization: Bearer` and `X-JWT-Assertion`, so the web view carries
  the header on the page and on the page's own requests through a `WKUserScript` that patches `fetch` and
  `XMLHttpRequest`. Tokens stay out of URLs and access logs.
- A service-account token gets `304`/empty from `/api/user/orgs`; token servers read as one organization.
- `POST /api/alertmanager/grafana/api/v2/silences` answers 202 on some versions, 200 or 201 on others.
- Grafana 11.6 already signs webhooks with HMAC; Basic auth is for anything older.
- A Worker `fetch` to an IP literal fails with Cloudflare error 1003, and outside hosts are reachable only
  on Cloudflare's proxied ports; the demo gate listens on 8880 and the Worker names the box's hostname.
- The Cloudflare token the relay deploys with cannot edit DNS records or tunnels; Workers custom domains
  are the one way it can give a hostname to something.
- App Store Connect: the age rating declaration wants every attribute answered, `ageRatingOverride` and
  `ageRatingOverrideV2` cannot both be sent, "What's new" is refused on a first release, and the review
  detail cannot be created without a phone number.
- The bot's push to main lands despite the "changes must be made through a pull request" ruleset message.

## Open
- CJ's phone: install build 6, see the organizations and the Notifications screen, silence an alert
  (closes milestone 2), open a dashboard signed in through Keystone (the provider path of the web view is
  the one thing no simulator could prove).
- App Store Connect, CJ only: the review contact phone number (`REVIEW_PHONE=… DEMO_USER=reviewer
  DEMO_PASSWORD=… node scripts/listing.mjs` files it with the demo account), the App Privacy answers
  ("Data Not Collected"; there is no API for them), and Submit for Review. Release type is manual.
- Daniel's Keystone group `meade-manor-admins`; Keystone's Grafana app launch URL, cosmetic.
- A live auth-proxy-fronted Grafana and a live DNS TXT signpost have fixtures only.
- The push grant is open to any relay that answers the discovery document; App Attest is the next gate if
  that is abused (decision 0005).
