---
type: decision
number: 0005
owner: CJ
reviewed: 2026-09-29
review: never; superseded instead
status: accepted
---

# 0005 · A push grant lends our APNs key without lending it

**Status:** accepted, 2026-09-29. Completes the second half of 0002.

## Context
Apple accepts a push for the Brazier app only from a provider token signed with a key that belongs to the Apple developer team that ships it: ours. Decision 0002 made the relay self-hosted, so a stranger's relay has to push through our key without ever holding it, and the alerts it pushes must never pass through us. Milestone 4 needed the mechanism.

## Decision
A second, tiny Worker of ours, the push grant at `grant.brazier.gicloud.org`, holds the APNs key. A self-hoster registers their relay once (`POST /relays` with the relay's address; the grant checks that the address answers `/.well-known/brazier` like a Brazier relay, then hands back a relay key, shown once and stored only as a hash). From then on the relay asks `POST /grant` with that key and receives a provider token: the same ES256 JWT Apple wants, signed by us, good for fifty minutes, one a minute at most per relay. The relay keeps it in its own KV until five minutes before it lapses and sends its pushes to Apple directly with it. Our key stays in our Worker; the alert text goes from the relay to Apple and nowhere else.

A relay with a key of its own (ours) keeps signing locally; `PUSH_GRANT_URL` and `PUSH_GRANT_KEY` are the alternative, not a requirement. The health answer says which (`push: key | grant | none`).

## Rejected options
- **Proxy the push through us.** One call less to design, but every alert's title and body would transit our Worker and its logs, which 0002 ruled out.
- **Ship the key in the README.** Anyone could push to any Brazier phone whose device token they obtained, and Apple revokes a key the first time it leaks, taking every relay down with it.
- **App Attest, so only a genuine app install can obtain a grant.** The right gate later, when the registration step needs proof of an app rather than proof of a relay; too much machinery for the first release.

## Consequences
A relay key lets its holder push to Brazier's topic only, and only to device tokens that relay already holds, so its worst case is spam to that relay's own users; we revoke it by deleting its KV record. The grant sees relay addresses and grant counts, nothing about alerts or people. Apple's limits on provider tokens (one key, tokens refreshed under an hour) are met by the fifty-minute lifetime and the once-a-minute rate. A leaked APNs key would now be rotated in one place. Registration is open; if it draws abuse, the App Attest gate above is the next step.
