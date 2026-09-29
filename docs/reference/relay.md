---
type: reference
owner: CJ
reviewed: 2026-09-29
review: each release of the relay
---

# The relay

| Route | Auth | Does |
|---|---|---|
| `POST /grafana` | `X-Grafana-Alerting-Signature`: HMAC-SHA256 hex over `<timestamp>:<body>` with `WEBHOOK_SECRET` (`X-Grafana-Alerting-Timestamp` carries the timestamp; without it the body alone is signed), constant-time compare. Verified against Grafana 13.2.1's real output on 2026-09-28 | Parses Grafana's webhook payload (`alerts[]` with `status`, `labels`, `annotations`, `fingerprint`, `startsAt`). Per alert: skip if `sent/<fingerprint>:<status>:<startsAt>` exists; match the labels against `ROUTES`; load `devices/<user>`; push to each; record sent once at least one push was accepted |
| `POST /devices` | Headers: `X-Grafana-Url: <origin>` plus exactly one of `Authorization: Bearer <service account token>`, `Cookie: grafana_session=<value>`, `X-JWT-Assertion: <OIDC token>`; the relay asks that Grafana `/api/user` (decision 0004). The origin must be on `GRAFANA_URLS` (403 otherwise; 401 when Grafana rejects the credential; 502 when it cannot be reached) | Stores `{ token, platform, environment, name, added, grafana }` under `devices/<login, lower case>` and `alias/<email>` → login; `environment` is `production` or `sandbox` and picks the APNs host; idempotent |
| `GET /devices` | same | The caller's devices, tokens elided |
| `DELETE /devices/:token` | same | Removes it; called on sign-out and when a server is removed |
| `GET /health` | none | 200, version, KV reachable, whether APNs and the webhook secret are configured |

| Setting | Value | Kept where |
|---|---|---|
| `WEBHOOK_SECRET` | random 32 bytes, also on the Grafana contact point | wrangler secret |
| `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` | the .p8, its id, the team, the bundle id; replaced by the push grant in a self-hosted relay | wrangler secrets |
| `GRAFANA_URLS` | the Grafana origins this relay serves, comma separated; the estate's is `https://grafana.gicloud.org` | wrangler var |
| `ROUTES` | JSON, label matcher → Grafana user or users (login or email), first match wins, `*` default; `label=value` or `label=~regex`; the estate's is `{"site=meade-manor":"dmeade@damp.meme","*":"cjackson@guysinc.org"}` | wrangler var |
| KV namespace | one (`DEVICES`), 7-day TTL on `sent/*` | wrangler.jsonc binding |

Payload: title = alert name (`Resolved: …` when resolved); body = `summary` annotation or the first label pair; subtitle = site and host; thread-id = folder; category `ALERT` so the app offers Silence as an action; `severity=page` sets the time-sensitive interruption level, everything else is active; resolved pushes reuse the collapse-id and carry no sound. A top-level `brazier` object carries fingerprint, status, labels, annotations, `generatorURL`, `silenceURL`, `externalURL` and folder for the app.

Code: `relay/` in this repository, tests in `relay/test/`, deploy notes in `relay/README.md`. Live at `https://brazier.gicloud.org` (Worker `brazier-relay`).
