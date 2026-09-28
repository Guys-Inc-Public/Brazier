---
type: reference
owner: CJ
reviewed: 2026-09-28
review: each release of the relay
---

# The relay

| Route | Auth | Does |
|---|---|---|
| `POST /grafana` | HMAC of the raw body with `WEBHOOK_SECRET`, constant-time compare | Parses Grafana's webhook payload (`alerts[]` with `status`, `labels`, `annotations`, `fingerprint`, `startsAt`). Per alert: skip if `sent/<fingerprint>:<status>` exists; resolve the site label to a user; load `devices/<user>`; push to each; record sent |
| `POST /devices` | Bearer JWT verified against `JWKS_URL` | Stores `{ token, platform, name, added }` under `devices/<sub>`; idempotent |
| `DELETE /devices/:token` | same | Removes it; called on sign-out and when a server is removed |
| `GET /health` | none | 200, version, KV reachable |

| Setting | Value | Kept where |
|---|---|---|
| `WEBHOOK_SECRET` | random 32 bytes, also on the Grafana contact point | wrangler secret |
| `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` | the .p8, its id, the team, the bundle id; replaced by the push grant in a self-hosted relay | wrangler secrets |
| `JWKS_URL` | `https://keystone.gicloud.org/application/o/<slug>/jwks/` | wrangler var |
| `ROUTES` | JSON, label matcher → user, e.g. `{"site=meade-manor":"dmeade","*":"cjackson"}` | wrangler var |
| KV namespace | one, TTL on `sent/*` | wrangler.jsonc binding |

Payload: title = alert name; body = `summary` annotation or the first label pair; subtitle = site and host; thread-id = folder; category `alert` so the app offers Silence as an action; `severity=page` sets the time-sensitive interruption level; resolved pushes reuse the collapse-id.
