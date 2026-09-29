---
type: decision
number: 0003
owner: CJ
reviewed: 2026-09-28
review: never; superseded instead
status: accepted
---

# 0003 · Sign-in is Keystone through Grafana's JWT auth

**Status:** accepted, 2026-09-28; the sign-in half is superseded by 0004 on 2026-09-29 (Grafana's own login page is the default, this path is the advanced option).

## Context
Grafana behind SSO has no password to give a phone. Grafana OSS accepts a JWT in a request header and maps it to a user.

## Decision
The app signs in to the instance's identity provider (Keystone for the estate; any OIDC provider for others) with authorization code and PKCE as a public client, and calls Grafana with the ID token in the `X-JWT-Assertion` header. Grafana's JWT auth is pointed at the provider's JWKS and maps `preferred_username`, `email` and the groups claim to the same user record the browser login uses. For an instance without SSO, the app accepts a service account token and keeps it in the keychain.

## Rejected options
- **A Grafana service account per phone.** Long-lived, broad, and invisible to the identity provider's session controls.
- **Proxying Grafana through the relay.** Puts every dashboard byte through a Worker and makes the relay a single point of failure for reading, not just for push.

## Consequences
Two things to verify by curl before building: that Grafana 13's JWT auth accepts an ID token whose audience is the client id (it may need `expect_claims`), and that the alerting API paths are unchanged in 13.2. Keystone's client must set `grant_types` explicitly; the empty default has broken two apps here.
