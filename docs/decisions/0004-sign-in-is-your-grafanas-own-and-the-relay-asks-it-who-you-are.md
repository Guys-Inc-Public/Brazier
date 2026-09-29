---
type: decision
number: 0004
owner: CJ
reviewed: 2026-09-29
review: never; superseded instead
status: accepted
---

# 0004 · Sign-in is your Grafana's own, and the relay asks it who you are

**Status:** accepted, 2026-09-29. Supersedes the sign-in half of 0003; Grafana's JWT auth stays as an advanced option.

## Context
CJ, 2026-09-29: "Lets remove all the presets. I want this to be publicly accessible from the first moment. We need to have some intuitive way to walk users through setups. Like you download the app and open it, it asks for the server URL and then walks you through the login process and whatever else." Decision 0003 needed an OIDC public client in the identity provider and Grafana's JWT auth pointed at it: right for the estate, two admin tasks too many for a stranger, and the relay then needed that provider's keys to know who a phone belonged to.

## Decision
The app's first run asks for the Grafana address, probes it, and signs in through that Grafana's own login page in a web view: password, or whatever single sign-on the instance has, with no change to the instance. The app keeps the resulting Grafana session and renews it as Grafana rotates it. A service-account token is the second method; an OIDC token through Grafana's JWT auth (0003) stays as an advanced one.

The relay no longer verifies identity tokens. A device registers with the same credential the app uses for Grafana, in headers (`X-Grafana-Url` plus one of `Authorization: Bearer`, `Cookie: grafana_session`, `X-JWT-Assertion`); the relay asks that Grafana `/api/user` and files the device under the login it answers with, with the email as an alias so `ROUTES` may name a person by either. The relay only talks to Grafana origins on its `GRAFANA_URLS` allow list.

## Rejected options
- **Keep the OIDC client as the only sign-in.** Every self-hoster would need an identity provider, a public client and Grafana's JWT auth before the first alert; the intuitive first run CJ asked for is impossible that way.
- **The app's own accounts on a Brazier service.** A second identity, a database, and nothing the user did not already have in Grafana.
- **Hand the relay a Grafana API key of its own.** Broad, long-lived, and still leaves the question of which person a device belongs to.

## Amendment, 2026-09-29
CJ's first run on a real phone found the in-page sign-in useless for the estate: iOS does not allow passkeys in an in-app web view, and Keystone requires one. So the relay also publishes, per Grafana, the identity provider the app may sign in with (`/.well-known/brazier`, from `SIGN_IN`); when it does, the app's recommended sign-in is "Sign in with <name>" through the system sign-in sheet, where passkeys work, and Grafana's JWT auth (0003) carries the token. The in-page sign-in stays for Grafanas that use a password; manual issuer and client id entry moves out of the walkthrough into the server's advanced settings.

## Amendment 2, 2026-09-29
CJ: "Why is the relay required? Why can't it be auto discovered." Grafana OSS has no unauthenticated place an admin can write a note for the app, so the signpost lives beside Grafana instead: the relay's discovery document served on the Grafana's own hostname at `/.well-known/brazier` (a Worker route for the estate, a one-line proxy rule elsewhere), or a DNS TXT record at `_brazier.<host>`. The app reads those from the Grafana address alone; the relay field is the fallback. The document also names the relay's address, so nothing but the Grafana address is typed.

## Amendment 3, 2026-09-29
CJ: "this needs to work for any OnPrem deployment of grafana with any IdP in front or the default grafana basic Auth." Checked against a throwaway Grafana 11.6 and the estate's 13.2, and closed where it fell short:

- **Basic auth and LDAP** get a native username-and-password card: the app posts to Grafana's own JSON login endpoint (`POST /login`, the same call its page makes) and keeps the session it answers with. A Grafana whose password form is off answers `auth.client.notConfigured`, and the card says so.
- **An auth proxy in front of Grafana** (Authelia, oauth2-proxy, Cloudflare Access) keeps its own cookie. The app keeps every cookie for the host after a page sign-in, sends them all as one `Cookie` header, and the relay forwards that header untouched to `/api/user`. The address probe treats a sign-in page in front of `/api/health` as reachable, not as a failure.
- **What a Grafana offers** is read from its public login page (`/login?disableAutoLogin=true`, which shows the page even when auto-login to a provider is on): whether the password form is on, which providers it lists, whether anonymous access is on. The sign-in step orders its cards from that and from the signpost (amendment 2). `/api/frontend/settings` needs a session, so it is not used.
- **Grafanas older than 11** cannot sign a webhook; the relay also accepts HTTP Basic with the shared secret as the password.
- **SAML and providers without ID tokens** sign in through the page; no provider card is possible for them, and that is documented rather than worked around.

`docs/reference/compatibility.md` is the matrix and stays current with every build.

## Consequences
The credential the app holds reaches the relay once per registration, so a relay must be run by someone the user already trusts with their Grafana session: the Grafana admin, or themselves. That is the self-hosted-first shape of 0002 and rules out a shared relay for strangers until the push grant of milestone 4 exists. Grafana sessions expire after inactivity; the app must notice a 401 and offer to sign in again.
