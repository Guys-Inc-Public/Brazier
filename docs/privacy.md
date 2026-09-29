---
type: reference
owner: CJ
reviewed: 2026-09-29
review: each release
---

# Privacy

Effective 2026-09-29. This is the privacy policy for Brazier, the iPhone app published by Guys Inc.

## What Brazier is
Brazier is a client for a Grafana you already run. It reads alerts and dashboards from that Grafana and, if a push relay is set up for it, shows its alerts as notifications. There is no Brazier account and no Brazier server that holds your data.

## What the app stores on your phone
- The address of each Grafana you add, and the name you give it.
- The credential that Grafana handed you when you signed in: its session cookie, a service-account token you pasted, or the tokens your identity provider issued. These live in the iPhone keychain, under the app's own entries, and nowhere else.
- The address of your push relay and your notification preferences.

## Who the app talks to
Brazier makes requests only to:

- The Grafana you typed, to sign in, read alerts and dashboards, and write silences.
- The identity provider that Grafana names, when you choose to sign in through it.
- The push relay that you or your Grafana's administrator run. When you allow notifications the app registers its Apple push token there once, together with the same Grafana credential, so the relay can ask your Grafana who you are and file the phone under your login. The relay is the one place outside your phone that sees that credential, which is why a relay must be run by someone you already trust with your Grafana session.
- Apple's push service, which delivers the notifications.

## What Guys Inc collects
Nothing. The app has no analytics, no advertising and no tracking. Crash reports reach us only through Apple's own opt-in sharing, which you control in iOS settings. When you run your own relay, no alert, dashboard, credential or device token ever reaches Guys Inc.

The push grant service at `grant.brazier.gicloud.org` lets a self-hosted relay send through Apple without holding Guys Inc's signing key. When a relay uses it, Guys Inc sees the relay's public address and how often it asked for a token, and nothing else: never an alert, never a device token.

The relay at `brazier.gicloud.org` is Guys Inc's own. It serves only Guys Inc's Grafana and registers only devices that Grafana vouches for.

## Deleting your data
Remove a server in the app: its keychain entries are deleted and the phone's registration is removed from the relay. Deleting the app removes everything it stored. A relay administrator can also remove a device on the relay side.

## Children
Brazier is a tool for people who run servers and is not directed at children.

## Changes
Changes to this policy are made in the repository and dated at the top. The current text is always at the address the App Store listing points to.

## Contact
See [Support](support.md).
