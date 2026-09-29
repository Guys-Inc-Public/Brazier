---
type: reference
owner: CJ
reviewed: 2026-09-29
review: each release
---

# App Store listing

The listing as it is filed in App Store Connect. `node scripts/listing.mjs` (from mitochondria, with the
App Store Connect key at `/root/.config/brazier/`) reads the sections below by heading and writes them to the
app record, so this page is the source and the portal is the copy. Character limits are Apple's: subtitle
30, promotional text 170, keywords 100, description 4000.

## Name

Brazier

## Subtitle

Alerts for self-hosted Grafana

## Promotional text

Real push for firing and resolved alerts from your own Grafana, sign-in the way you already run it, and your dashboards on the phone.

## Description

Brazier is an iPhone app for people who run their own Grafana. It shows the alerts your Grafana is firing, lets you silence them from the phone, and opens your dashboards signed in. With a small relay that you or your Grafana admin run, it receives real push notifications for firing and resolved alerts.

Sign in the way you already do. Type your Grafana's address and Brazier finds out how it signs in: a username and password, the identity provider your admin uses (passkeys included, through the system sign-in sheet), Grafana's own sign-in page, or a service account token. The credential stays in the phone's keychain and goes only to that Grafana.

What it does

• Alerts: every firing, pending and normal instance across your organizations, grouped by folder, with the summary and labels the rule wrote. Search by alert, label or host.
• Silence from the phone: one, eight or twenty-four hours with a comment, written to Grafana as a silence you can see there.
• Push: firing and resolved alerts arrive as notifications with the alert's severity; a page interrupts, a warning does not. Silence from the lock screen. Choose which organizations, a minimum severity and quiet hours.
• Dashboards: search, starred first, opened signed in.
• Several Grafanas and several organizations, switched from the header.

What it needs

• Grafana 11 or newer, self-hosted. Grafana Cloud is not supported.
• For push: a relay, open source, one Cloudflare Worker, deployed by your admin with the instructions in the README. Without a relay everything else still works whenever the app is open.

Brazier is open source under the MIT licence. It collects no data: it talks only to the Grafana you typed, the identity provider that Grafana names, the relay you or your admin run, and Apple's push service.

Brazier is not affiliated with or endorsed by Grafana Labs. Grafana is a trademark of Grafana Labs.

## Keywords

grafana,alerts,alerting,monitoring,prometheus,loki,dashboards,on-call,silence,self-hosted,push,devops

## What's new

First release.

## Support URL

https://guys-inc-public.github.io/Brazier/support/

## Marketing URL

https://guys-inc-public.github.io/Brazier/

## Privacy policy URL

https://guys-inc-public.github.io/Brazier/privacy/

## Copyright

2026 Guys Inc

## Categories

UTILITIES, DEVELOPER_TOOLS

## Age rating

None of Apple's content categories apply; no gambling, no unrestricted web access, no user-generated content, no advertising. The app shows the user's own Grafana.

## Pricing and availability

Free, base territory United States, every territory, available in new territories. Release type manual: an approved version goes live only when CJ releases it.

## Review notes

Brazier is a client for a self-hosted Grafana. A Grafana for review is at demo.brazier.gicloud.org: on first run type that address, choose "Username and password" and sign in with the demo account. Three alerts fire there on purpose; silencing one from the phone writes a silence to that Grafana, visible under Alerting › Silences. Push notifications need the relay, which the demo Grafana is wired to: allow notifications when asked, register on the Notifications step, and a push arrives when an alert changes state (the "Container restarting" rule flaps every few minutes). The app collects nothing; the privacy policy is at the URL above.

## Review contact

Cameron Jackson, CJ@guysinc.org. Phone: CJ fills this in; the API leaves it empty.

## Screenshots

6.9-inch iPhone (1320 × 2868) and 13-inch iPad (2064 × 2752), taken in the simulator on the Mac mini
against the demo Grafana: Alerts, an alert with its silence sheet, Dashboards, a dashboard, Notifications,
the first run. Uploaded by `scripts/screenshots.mjs`.
