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

## Consequences
The credential the app holds reaches the relay once per registration, so a relay must be run by someone the user already trusts with their Grafana session: the Grafana admin, or themselves. That is the self-hosted-first shape of 0002 and rules out a shared relay for strangers until the push grant of milestone 4 exists. Grafana sessions expire after inactivity; the app must notice a 401 and offer to sign in again.
