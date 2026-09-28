---
type: brief
owner: CJ
reviewed: 2026-09-28
review: at each milestone
---

# Project brief · Brazier

_One page. Written from the study of 2026-09-28._

**01 · Done looks like** — A self-hoster installs Brazier from the App Store, adds their Grafana by URL, signs in through their own SSO or a token, and gets a push on their phone within a minute of an alert firing and again when it resolves, without Grafana Cloud.

**02 · Who it is for, and how many of them** — People who run Grafana OSS themselves and lost push when OnCall OSS was archived in March 2026. First users: CJ and Daniel on the Guys Inc and Meade Manor estate; then the public.

**03 · Constraints** — stack: SwiftUI, iOS 17+, Cloudflare Workers with KV for the relay · hosting: relay self-hosted by each user first, a Guys Inc push-grant service for the APNs key · compliance: no Grafana trademark in the name or mark, Apple review needs a demo Grafana · deadline: milestone 1 (relay) before anything else, because it is also the estate's own notification channel.

**04 · Explicitly out of scope** — Editing dashboards, on-call schedules, incidents, Loki search, Android in v1, anything Grafana Cloud does that OSS does not.

**05 · Owner and decision-maker** — CJ / CJ.

**06 · How we will know it worked, 30 days after** — Every estate alert reached a phone with no missed firing; at least one stranger has a self-hosted relay running from the README alone; zero support issues about the relay's setup that the docs did not already answer.
