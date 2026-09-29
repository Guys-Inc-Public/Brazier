---
type: reference
owner: CJ
reviewed: 2026-09-29
review: each milestone
---

# Any Grafana, any sign-in

Brazier is built for the estate first and the public second (build guide, decision 03). This page is the
check that nothing in it is estate-only. Every row is built as of build 7 (1.0) unless it says otherwise.

## How a user signs in

| Grafana is set up with | What the app offers | Needs from the admin | State |
|---|---|---|---|
| Basic auth, LDAP | Username and password, posted to Grafana's own login endpoint; session kept and renewed | nothing | built |
| Generic OAuth or OIDC provider without passkeys or web-view blocks (Keycloak, Authentik, Okta, Entra, Auth0, GitHub) | Grafana's page in the app; the provider's login runs inside it | nothing | built |
| A provider that needs a passkey or refuses in-app web views (Google, any WebAuthn second factor) | "Sign in with <provider>" through the system sign-in sheet; Grafana's JWT auth carries the ID token | a public PKCE client for the app in the provider (redirect `brazier://auth/callback`), Grafana `[auth.jwt]` pointed at it, and the signpost below | built |
| An auth proxy in front of Grafana (Authelia, oauth2-proxy, Cloudflare Access) | Grafana's page in the app; every cookie for the host is kept and sent | nothing | built; live against Authelia 4.38 in front of Grafana 13.2.3 at `fronted.brazier.gicloud.org` (2026-09-29): the health probe meets a 302 to the portal and reads as reachable, the portal then Grafana's own form sign in on the page, and `/api/user` answers only with both cookies together |
| Anonymous access on | "Browse without signing in": alerts, silences and dashboards as a visitor sees them; no silencing, no stars, no push (the relay files a phone under a Grafana login); signing in later on the page turns the server into a session one | nothing | built (build 7) |
| Any Grafana | A service-account token | a token | built |
| SAML (Enterprise), GitHub (no ID tokens) | Grafana's page in the app, or a token; no provider sign-in possible | nothing | built |

Manual issuer and client id entry stays available under the server's advanced settings for any case the
signpost does not cover.

## How the app finds the admin's settings

| Signpost | Who can set it | State |
|---|---|---|
| `https://<grafana host>/.well-known/brazier`, served by the proxy in front of Grafana (Cloudflare Worker route, nginx or Caddy rule) | anyone with a proxy | built; the estate uses a Worker route |
| DNS TXT `_brazier.<grafana host>` (`v=brazier1 relay=… [issuer=… client_id=… name=…]`) | anyone with DNS | built; live at `demo-txt.brazier.gicloud.org`, a name for the demo Grafana that serves no `/.well-known/brazier`, whose TXT record alone leads the address step to the relay (2026-09-29) |
| Typed relay address | everyone | built, fallback |

## Push

| Piece | Today | Public |
|---|---|---|
| Relay | one per admin, `wrangler deploy`, serves several Grafanas, routes by label to Grafana users; the app keeps a relay per Grafana, so two Grafanas from two admins push through two relays | same; proven 2026-09-29 by a second relay (`stranger.brazier.gicloud.org`) deployed from the README's eight steps alone |
| Webhook auth | HMAC (Grafana 11+) or HTTP Basic with the shared secret (older) | same |
| APNs key | ours, in the estate's relay | a self-hosted relay borrows a 50-minute provider token from `grant.brazier.gicloud.org` (decision 0005) and never holds the key; the stranger's relay above pushed with one and Apple accepted it (a bogus device answered BadDeviceToken and was dropped) |
| Who a phone belongs to | the relay asks the user's Grafana `/api/user` with the app's credential | same; a relay is run by someone the user already trusts with their Grafana |

| What a phone gets | every alert its user is routed to | the same, minus what the phone declines: organizations, a minimum severity, quiet hours (delivered silently), filed per device on the relay |

## Dashboards on the phone

| Sign-in | How a dashboard page is signed in | State |
|---|---|---|
| Username and password, Grafana's page, auth proxy | the cookie jar is put into the web view's cookie store before the page loads | built |
| Provider through Grafana's JWT auth | the ID token rides as `X-JWT-Assertion` on the page load and, through a script in the page, on every request the page makes itself | built; an ID token that lapses while a dashboard stays open makes the page's requests fail until it is reopened |
| Service-account token | the same, with `Authorization: Bearer` | built |
| Any of the above | a dashboard's `stat`, `gauge` and `bargauge` panels rendered natively as tiles, their queries run through `/api/ds/query` over the dashboard's own time range with a 15-second step floor, so a "last value" is as fresh as the page's | built (build 6; gauges build 7; the range build 9) |
| Anonymous | the page and the tiles load plain, as a visitor | built (build 7) |
| Any signed-in user | a star on the dashboard, Grafana's own (`/api/user/stars/dashboard/uid/…`), starred first in the list | built (build 7) |

`?auth_token=` (Grafana's `url_login`) renders the page but never sets a session cookie, on 11, 12 and 13, so
the app does not use it; the contract tests pin that.

## Organizations

A user in several organizations sees all of them or one, switched from the header; every call carries
`X-Grafana-Org-Id`, a silence is written in the alert's own organization, and the relay names the
organization on the lock screen from its `ORGS` setting (per Grafana when it serves several).

## Silences

A silence is written from the alert (one, eight or twenty-four hours, a comment) or from the lock screen.
Every silence on the server is listed from the row above the alerts (active, starting later, expired),
an active one is ended from that list or from the alert it covers (`DELETE …/silence/:id`), and a row
whose instance an active silence covers carries the mark. Matchers are read the way Alertmanager reads
them: equal, not equal, regex.

## Grafana versions

Unified alerting (Grafana 9 and later) for the alert and silence APIs; the search and health endpoints are
older still. `contract/` runs every call the app and the relay make against the official images in CI:
19 checks, green on 11.6.5, 12.4.3 and 13.2.3 as of 2026-09-29. The webhook is HMAC-signed on all three;
Basic auth stays for anything older. Anonymous access reads alerts, search, a dashboard and its query
with no credential on all three, and `/api/user` still answers 401 to a visitor; a star by uid works on all three.
