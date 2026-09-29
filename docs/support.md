---
type: reference
owner: CJ
reviewed: 2026-09-29
review: each release
---

# Support

## Getting help
Open an issue at <https://github.com/Guys-Inc-Public/Brazier/issues>. Say which Grafana version you run, how you sign in (username and password, Grafana's own page, a provider, or a token), and the relay version from Settings › Push, if you use one. Do not paste tokens, cookies or the webhook secret into an issue.

## The first run
1. Type your Grafana's address. The app probes it and reads the signpost beside it, if there is one, to find the relay and the sign-in the administrator published.
2. Sign in the way you already do: a provider button when one is published, your username and password when Grafana's own form is on, Grafana's page for anything else, or a service-account token.
3. Allow notifications, or skip them and read alerts whenever the app is open.
4. Done. Alerts, dashboards and settings are the three tabs.

## What most often goes wrong
- **A Grafana behind a sign-in gate** (Authelia, oauth2-proxy, Cloudflare Access): sign in through Grafana's page. The app keeps every cookie the gate and Grafana set and uses them together. A token does not get through a gate unless the gate lets `/api/` through.
- **A provider that needs a passkey**: passkeys do not work inside a page in an app. Use the provider sign-in the administrator published; it opens the system sign-in sheet, where passkeys work. If no provider button appears, ask the administrator to publish one in the relay's discovery document.

## The relay
How to run a relay of your own, its settings and routes are in the relay README in the repository: <https://github.com/Guys-Inc-Public/Brazier/tree/main/relay>. The reference copy is on this site under [Reference · The relay](reference/relay.md), and [Any Grafana, any sign-in](reference/compatibility.md) says what each kind of Grafana needs.

## Privacy
[Privacy](privacy.md) says what the app stores and who it talks to.
