---
session: 2026-09-29-build-7-the-last-of-the-functionality
repo: Guys-Inc-Public/Brazier
branch: main
driver: Claude Code, unattended; CJ asked for every remaining piece of functionality before the store
outcome: merged
---

# Build 7: the last of the functionality before the store

## Intent
CJ, after silencing an alert and opening a dashboard on build 6: "Silence works and the dashboard loads. I
want to finish absolutely all of the functionality before we publish this to the app store." The audit
went through the build guide's four milestones, the compatibility matrix and the listing's promises, and
found what was still marked later, half-built or silently wrong. All of it is in build 7.

## What was done
- **Anonymous access**, the one row of the sign-in matrix still marked later. The sign-in step offers
  "Browse without signing in" when the Grafana's login page says `anonymousEnabled`; the server is read
  as a visitor (`AuthMode.anonymous`, `Credential.none`): alerts, silences, search, the dashboard JSON, its
  queries and the page all load plain. Nothing is written: the alert's silence control, the star and the
  relay registration each say why. Signing in later on Grafana's page turns the server into a session
  one; a Grafana that turns anonymous access off faults the bay with "Anonymous access is off" and the
  same sign-in button. Pinned by a new contract check on 11, 12 and 13: a visitor reads the four things
  and gets 401 from `/api/user` and `/api/user/orgs`, 401 or 403 writing a silence.
- **Silences ended, and listed.** `DELETE …/silence/:id` from the alert's own page ("End this silence now")
  and from a new Silences screen reached from the row above the alert rack: active (with End), starting
  later (with Cancel), expired, per organization. A row whose instance an active silence covers carries
  a moon mark. Matchers are read the way Alertmanager reads them (equal, not equal, regex).
- **A relay per Grafana.** Build 6 kept one relay address for the whole app, so a second server whose
  signpost named another relay overwrote the first server's and pushes for it stopped without a word.
  The relay now lives on the server (`Server.relay`), the walkthrough files what it found there, the
  server's own page has the field with Test, Look up (the signpost) and Save and register, and the phone
  registers with every server's relay under that server's login. Registration state, the filed login and
  the preference hand-over are kept per server; Settings › Push is gone; the one address a build-6 install
  had is carried onto every server on first launch and the old key removed.
- **Stars.** A star in the dashboard's toolbar, Grafana's own (`POST`/`DELETE /api/user/stars/dashboard/uid/…`,
  a new contract check); the list reads again and starred dashboards lead it.
- **Tiles for gauge and bar gauge panels** as well as stat: the same reduce, unit, threshold and mapping
  settings, one number per series.
- **A privacy manifest** (`PrivacyInfo.xcprivacy`): no tracking, nothing collected, UserDefaults declared
  with reason CA92.1. Apple has required it since May 2024 and build 6 shipped without one.
- **One model from launch.** The AppModel is created by the app delegate before any view, so a Silence
  action taken from the lock screen while the app is not running has a model to write the silence with.
- Screenshot hooks `BRAZIER_SHOT=silences` and `server-detail`, `BRAZIER_SEED_ANONYMOUS=1`, and Makefile
  `launch-sim` (install, launch with every seed and hook variable, screenshot) so a batch of screens costs
  one build.
- Docs: the compatibility matrix (anonymous built, relay per Grafana, silences section, stars, gauges,
  19 checks), the contract README, the listing's description (filed again), the app README, the
  architecture parts table.

## What was learned
- Anonymous access in Grafana is bound to one organization by name (`GF_AUTH_ANONYMOUS_ORG_NAME`), so a
  renamed organization needs the setting or visitors land nowhere; `/api/user` and `/api/user/orgs` answer
  401 to a visitor on 11, 12 and 13 while the alert, search, dashboard and query endpoints answer 200.
- Starring an already-starred dashboard answers 200 on 11.6 rather than 400, so the check unstars first.
- `SetupMethod` and `Server.AuthMode` are two enums on purpose: the walkthrough's draft has no server yet.

## Open
- CJ's phone on build 7: end a silence, star a dashboard, the relay on the server's page, and the
  guest path against any Grafana with anonymous access on (the demo had it on only for this session's
  simulator check).
- App Store Connect, CJ only: the review contact phone number and demo account through
  `scripts/listing.mjs`, the App Privacy answers ("Data Not Collected"), Submit for Review.
- Daniel's Keystone group `meade-manor-admins`; a live auth-proxy-fronted Grafana and a live DNS TXT
  signpost have fixtures only; the push grant is open to any relay that answers the discovery document.
