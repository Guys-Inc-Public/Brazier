---
type: reference
owner: CJ
reviewed: 2026-09-29
review: each milestone
---

# Any Grafana, any sign-in

Brazier is built for the estate first and the public second (build guide, decision 03). This page is the
check that nothing in it is estate-only. Rows marked *built* exist today; *build 5* is the next app build.

## How a user signs in

| Grafana is set up with | What the app offers | Needs from the admin | State |
|---|---|---|---|
| Basic auth, LDAP | Username and password, posted to Grafana's own login endpoint; session kept and renewed | nothing | build 5 (today: Grafana's page in the app) |
| Generic OAuth or OIDC provider without passkeys or web-view blocks (Keycloak, Authentik, Okta, Entra, Auth0, GitHub) | Grafana's page in the app; the provider's login runs inside it | nothing | built |
| A provider that needs a passkey or refuses in-app web views (Google, any WebAuthn second factor) | "Sign in with <provider>" through the system sign-in sheet; Grafana's JWT auth carries the ID token | a public PKCE client for the app in the provider (redirect `brazier://auth/callback`), Grafana `[auth.jwt]` pointed at it, and the signpost below | built |
| An auth proxy in front of Grafana (Authelia, oauth2-proxy, Cloudflare Access) | Grafana's page in the app; every cookie for the host is kept and sent | nothing | relay built; app build 5 |
| Anonymous access on | "Continue without signing in": browse alerts, no push (the relay needs a signed-in user to own a phone) | nothing | later |
| Any Grafana | A service-account token | a token | built |
| SAML (Enterprise), GitHub (no ID tokens) | Grafana's page in the app, or a token; no provider sign-in possible | nothing | built |

Manual issuer and client id entry stays available under the server's advanced settings for any case the
signpost does not cover.

## How the app finds the admin's settings

| Signpost | Who can set it | State |
|---|---|---|
| `https://<grafana host>/.well-known/brazier`, served by the proxy in front of Grafana (Cloudflare Worker route, nginx or Caddy rule) | anyone with a proxy | built; the estate uses a Worker route |
| DNS TXT `_brazier.<grafana host>` (`v=brazier1 relay=… [issuer=… client_id=… name=…]`) | anyone with DNS | app build 4 |
| Typed relay address | everyone | built, fallback |

## Push

| Piece | Today | Public |
|---|---|---|
| Relay | one per admin, `wrangler deploy`, serves several Grafanas, routes by label to Grafana users | same |
| Webhook auth | HMAC (Grafana 11+) or HTTP Basic with the shared secret (older) | same |
| APNs key | ours, in the estate's relay | milestone 4: a push grant so a self-hosted relay sends through our key without holding it |
| Who a phone belongs to | the relay asks the user's Grafana `/api/user` with the app's credential | same; a relay is run by someone the user already trusts with their Grafana |

## Grafana versions

Unified alerting (Grafana 9 and later) for the alert and silence APIs; the search and health endpoints are
older still. Milestone 3 runs the relay and the client's contract tests against the official 11, 12 and
13 images in CI.
