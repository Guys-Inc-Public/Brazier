---
type: decision
number: 0002
owner: CJ
reviewed: 2026-09-28
review: never; superseded instead
status: accepted
---

# 0002 · The push relay is self-hosted first

**Status:** accepted, 2026-09-28.

## Context
Apple push needs a server that receives Grafana's webhook and calls APNs with a key tied to the app's developer team. Someone has to run it. Alert payloads pass through it.

## Decision
The relay is one Cloudflare Worker with a KV namespace, open source in this repository, that each user deploys in their own account. Grafana posts firing and resolved alerts to it with an HMAC; it routes by label, deduplicates by fingerprint and pushes through APNs. Because only Guys Inc can hold the APNs key, the app obtains a scoped, expiring push grant from a small Guys Inc service and hands it to the user's relay; the key never leaves us and the alert data never reaches us.

## Rejected options
- **A relay we host for everyone.** Simplest onboarding, but alert payloads transit our infrastructure and we carry uptime for strangers. Kept as a possible later tier.
- **Shipping the APNs key in the open-source relay.** Anyone could push to any Brazier user.
- **ntfy or Gotify instead of APNs.** Works, and remains a fallback transport, but it is a second app on the phone and loses the tap-through and the actions.

## Consequences
Milestone 1 is the relay and the Grafana contact point, deployed for the Guys Inc estate first. Milestone 4 adds the push-grant service before the public listing.
