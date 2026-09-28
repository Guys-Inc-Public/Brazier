---
type: decision
number: 0001
owner: CJ
reviewed: 2026-09-28
review: never; superseded instead
status: accepted
---

# 0001 · A thin native client over Grafana's API

**Status:** accepted, 2026-09-28.

## Context
Grafana Labs' mobile app is Grafana Cloud only. OnCall OSS, whose relay let self-hosted users receive push, was archived on 2026-03-24. The one indie app for self-hosters polls in the background, which iOS throttles. Self-hosted Grafana already exposes everything a phone needs over HTTP.

## Decision
Brazier is a native SwiftUI app that reads Grafana's HTTP API (alerts, silences, search, health, datasource queries) and shows Grafana's own dashboard pages in a web view. It does not fork, embed or rebuild Grafana, and it does not store dashboards or metrics of its own.

## Rejected options
- **An installable web app.** Web Push on iOS works only from the home screen and is throttled; the push story is the product.
- **A Grafana plugin or fork.** Every Grafana upgrade becomes our problem, and it puts our code inside the instance we are meant to watch.
- **Polling from the phone.** The competitor's approach; it is what fails.

## Consequences
The app targets Grafana 11, 12 and 13 and tests against official images in CI. Push needs a relay (ADR 0002). Sign-in is Keystone or any OIDC via Grafana's JWT auth (ADR 0003).
