---
type: reference
owner: CJ
reviewed: 2026-09-29
review: each release of the relay
---

# The relay

| Route | Auth | Does |
|---|---|---|
| `POST /grafana` | `X-Grafana-Alerting-Signature`: HMAC-SHA256 hex over `<timestamp>:<body>` with `WEBHOOK_SECRET` (`X-Grafana-Alerting-Timestamp` carries the timestamp; without it the body alone is signed), constant-time compare, verified against Grafana 13.2.1's real output on 2026-09-28; or, for Grafanas too old to sign, HTTP Basic with the secret as the password | Parses Grafana's webhook payload (`alerts[]` with `status`, `labels`, `annotations`, `fingerprint`, `startsAt`). Per alert: skip if `sent/<orgId>:<fingerprint>:<status>:<startsAt>` exists (the org from the alert, else the body, else 0; a fingerprint hashes the labels, so two orgs may share one); match the labels against `ROUTES`; load `devices/<user>`; push to each device whose preferences want it; record sent once at least one push was accepted. Answers `{ received, pushed, skipped, unrouted, filtered, quiet, dropped, failed, apns }` |
| `POST /devices` | Headers: `X-Grafana-Url: <origin>` plus exactly one of `Authorization: Bearer <service account token>`, `Cookie: <every cookie the app holds for that host, so an auth proxy's travels too>`, `X-JWT-Assertion: <OIDC token>`; the relay asks that Grafana `/api/user` (decision 0004). The origin must be on `GRAFANA_URLS` (403 otherwise; 401 when Grafana rejects the credential; 502 when it cannot be reached) | Stores `{ token, platform, environment, name, added, grafana, prefs? }` under `devices/<login, lower case>` and `alias/<email>` → login; `environment` is `production` or `sandbox` and picks the APNs host; idempotent, and a re-registration without `prefs` keeps the ones filed (the app re-registers on every launch). Bad `prefs` → 400 |
| `GET /devices` | same | The caller's devices, tokens elided, each with its `prefs` (`{}` when none) |
| `PUT /devices/:token/preferences` | same | Body = the preferences object below; replaces the device's preferences whole; `{ ok, prefs }`; 400 with the reason for a bad field, 404 when the token is not filed under the caller |
| `DELETE /devices/:token` | same | Removes it; called on sign-out and when a server is removed |
| `GET /health` | none | 200, version, KV reachable, whether APNs and the webhook secret are configured, the served Grafanas |
| `GET /.well-known/brazier` | none | Discovery: `{ relay: { url, version }, grafana: { <origin>: { signIn?: { issuer, clientId, name } } } }`. Served on the relay and, through a Worker route, on `grafana.gicloud.org/.well-known/brazier`, so the app finds the relay and the sign-in from the Grafana address alone; a DNS TXT `_brazier.<host>` is the alternative signpost. When `signIn` is present the app offers "Sign in with <name>" through the system sheet (passkeys work there; they do not in an in-app web view) |

| Setting | Value | Kept where |
|---|---|---|
| `WEBHOOK_SECRET` | random 32 bytes, also on the Grafana contact point | wrangler secret |
| `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` | the .p8, its id, the team, the bundle id; replaced by the push grant in a self-hosted relay | wrangler secrets |
| `GRAFANA_URLS` | the Grafana origins this relay serves, comma separated; the estate's is `https://grafana.gicloud.org` | wrangler var |
| `SIGN_IN` | JSON, Grafana origin → `{ issuer, clientId, name }`; the estate's points at Keystone's `brazier` client (provider 46) with name Guys Inc | wrangler var |
| `RELAY_URL` | this relay's public address, named in the discovery document (`https://brazier.gicloud.org`) | wrangler var |
| `ROUTES` | JSON, label matcher → Grafana user or users (login or email), first match wins, `*` default; `label=value` or `label=~regex`; the estate's is `{"site=meade-manor":"dmeade@damp.meme","*":"cjackson@guysinc.org"}` | wrangler var |
| `ORGS` | optional JSON, org id (string) → display name, for the lock screen and the payload; bad JSON is logged and ignored; the estate's is `{"1":"Infrastructure","2":"Guys Inc Public","3":"Personal","4":"Meade Manor"}` | wrangler var |
| KV namespace | one (`DEVICES`), 7-day TTL on `sent/*` | wrangler.jsonc binding |

Grafana's own `DatasourceError` and `DatasourceNoData` alerts (a rule's query failed or came back empty) are titled by the rule and the datasource, "Out-of-memory kill · query failed", with the error text as the body; their templated summary reads "[no value]" and is ignored. Route them to nobody with `"alertname=DatasourceError": []` in `ROUTES` if they are unwanted.

Preferences, per device (`prefs`), applied at send time so a phone's choice never depends on Grafana's notification policies: `orgs` (org ids; absent, null or empty = every org; an alert from another org is not sent to that device), `minSeverity` (`info` < `warning` < `critical` < `page`; the `severity` label is read case-insensitively, `warn` is warning, `crit`/`high`/`error` are critical, `emergency` is page, missing or unknown counts as warning; a resolved alert carries its firing's label, so a suppressed firing never leaves a lone resolved push) and `quiet` (`{ start: "HH:MM", end: "HH:MM", tz: "<IANA zone>", allowPage?: true }`, a window in the device's own zone that may cross midnight; inside it a push is delivered without a sound at the passive interruption level; `severity=page` still sounds unless `allowPage` is false; an unknown zone means no window).

Payload: title = alert name (`Resolved: …` when resolved); body = `summary` annotation or the first label pair; subtitle = org (when `ORGS` names it), site and host; thread-id = folder; category `ALERT` so the app offers Silence as an action; `severity=page` sets the time-sensitive interruption level, everything else is active; resolved pushes reuse the collapse-id and carry no sound. A top-level `brazier` object carries fingerprint, status, labels, annotations, `generatorURL`, `silenceURL`, `externalURL`, folder, `orgId` and `org` for the app.

Code: `relay/` in this repository, tests in `relay/test/`, deploy notes in `relay/README.md`. Live at `https://brazier.gicloud.org` (Worker `brazier-relay`).
