---
session: 2026-09-29-build-8-and-the-live-checks
repo: Guys-Inc-Public/Brazier
branch: main
driver: Claude Code, unattended; CJ asked for every phase and step before testing
outcome: merged
---

# Build 8 and the live checks: nothing left that a session can close

## Intent
CJ: "So is the app completely done? I want you to complete absolutely every phase and all steps before we
test." The honest answer after build 7 was: the functionality yes, the guide no. Three rows still said
"fixtures only" or "a stranger's relay", two loose ends sat in Keystone, and two session-renewal edges in
the app had no path back to a sign-in. This session closed all of it that does not need a phone in a
hand or a form only CJ can fill.

## What was done
- **A stranger's relay, from the README alone.** `brazier-relay-stranger` at `stranger.brazier.gicloud.org`:
  its own KV namespace, `GRAFANA_URLS` = the demo and the fronted Grafana, `ROUTES` everything to
  `reviewer`, no APNs key. Registered with the push grant (`POST /relays` → relay key), `PUSH_GRANT_KEY`
  set, health `push: grant`. Then the app's own steps by hand: the reviewer's session from `POST /login`,
  `POST /devices` with that cookie (filed under `reviewer`), a signed webhook with a demo-shaped alert.
  Outcome `{received:1, pushed:0, dropped:1, failed:0, apns:true}`: the relay asked the grant for a token,
  signed the push with it, Apple accepted the token and answered BadDeviceToken for the bogus device,
  which was dropped. Decision 0005's path is proven end to end; the relay stays up as the fronted
  Grafana's relay. Its config is not in the repository (`docs/reference/identifiers.md` has the ids).
- **The DNS signpost, live.** `demo-txt.brazier.gicloud.org` is the demo Grafana under a third custom domain
  of the demo Worker; the Worker serves `/.well-known/brazier` on the demo hostname only, so this one
  answers Grafana's own 302 there. A TXT record `_brazier.demo-txt.brazier.gicloud.org` =
  `v=brazier1 relay=https://brazier.gicloud.org` (made through the Cloudflare connector, since the
  deploy token cannot write DNS) leads the address step to the relay with nothing else typed.
- **An auth proxy in front of Grafana, live.** `fronted.brazier.gicloud.org`: Authelia 4.38 (one-factor,
  file users, portal under `/authelia` on the same hostname) in front of a second Grafana 13.2.3, in the
  demo's compose stack behind the same gate, routed by the hostname the Worker was reached on.
  Checked by hand first: `GET /api/health` with no cookie is a 302 to `/authelia/?rd=…` (the address
  step's `.fronted` reading); the portal answers 200; `POST /authelia/api/firstfactor` sets
  `authelia_session`; with it Grafana's health and login page answer 200 and `POST /login` sets
  `grafana_session`; `/api/user` answers 200 with both cookies in one header, 302 to the portal with
  Grafana's alone, 401 with Authelia's alone. The stranger's relay serves this origin, so a phone can
  register through it with the same two-cookie header.
- **Build 8.** A refresh token the provider no longer honours (400/401 `invalid_grant`) ends the sign-in
  and the bay offers the provider again, instead of "read again" with a token-endpoint error. The
  dashboard page hands the session cookie Grafana rotates inside it back to the keychain (after each
  load, once a minute, and when the page goes away), so a long look at a dashboard no longer strands
  the API on a dead cookie. A visitor's page starts with no Grafana session for the host, whatever an
  earlier sign-in left in the web view's store. DEBUG only: `BRAZIER_SHOT_FILL` and
  `BRAZIER_SHOT_GATE_FILL` type into Grafana's form and an Authelia portal so the page sign-in can be
  driven headless. In the simulator, from a clean install: the address step on `demo-txt` reads "Relay found ·
  brazier.gicloud.org · 0.6.0 ok" from the TXT record alone; "Sign in on your Grafana's page" against the
  demo fills Grafana's form and lands on "Signed in as reviewer · SESSION"; the same against the fronted
  Grafana meets Authelia's portal first, then Grafana's form, and lands on the same plate, `/api/user`
  having answered through the gate with both cookies in the jar. The main relay now serves `demo-txt`
  too, so a walkthrough begun there registers as well.
- **Build 9, after CJ's first look at build 8: "all boxes on the dashboards show as cancelled".** The
  tiles were publishing the outcome of a read the view had cancelled: every query answers "cancelled"
  (Apple's wording) the moment the tiles' task is torn down, and a restarted task then skipped its own
  read because the flag from the dead one still said "reading", so the faults stood for a minute. A
  token in the simulator never showed it; the phone's provider sign-in and a real tap's transition did.
  Now a cancelled read publishes nothing and never blocks the next, a cancelled dashboard load is not
  a fault, and a dozen concurrent tile queries share one refresh of the provider token instead of each
  spending the refresh token (providers rotate it; every refresh but the first would have failed, and
  build 8 would have read that as the sign-in ending). Also: the tiles now ask over the dashboard's own
  time range with a fine step, so "Down now" on a tile matches the page instead of trailing it by minutes.
- **Keystone.** Daniel was already in `meade-manor-admins` (added earlier today; he signed in at 12:26 UTC),
  so that open item was closed before this session touched it. The Grafana application's launch URL
  was still `grafana.guysinc.org`; it is `grafana.gicloud.org` now.
- Docs: the compatibility matrix (DNS row live, auth-proxy row live, relay and APNs rows carry the
  stranger's proof), identifiers (stranger relay, TXT record, fronted Grafana, the Worker's three
  names), this record.

## What was learned
- A Worker's fetch cannot carry the outside `Host`, so the gate on the box routes by
  `X-Forwarded-Host`; nginx's `internal` locations with a `rewrite … last` keep the DEMO_KEY check in one place.
- Authelia 4.38 runs under a path (`server.address: tcp://:9091/authelia`), which keeps the portal, its
  API and the AuthRequest endpoint on the protected hostname itself; one cookie domain, no second name.
- The grant's `POST /relays` checks the relay's discovery document first, so a stranger deploys, then
  registers, then sets the key: the README's order is right.

## Open
- CJ's phone on build 9 before Submit: the tiles read on every open, a dashboard left open past ten
  minutes still reads afterwards, and the fronted Grafana signs in through its page (gatekeeper, then reviewer).
- App Store Connect, CJ only: the review contact phone number and demo account through
  `scripts/listing.mjs`, the App Privacy answers ("Data Not Collected"), Submit for Review.
- TESS trademark search; a hosted relay tier; Android.
