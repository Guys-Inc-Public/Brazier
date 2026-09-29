# Brazier relay

Grafana's webhook in, Apple's push out. One Cloudflare Worker, one KV namespace, no framework, no database.

```
Grafana contact point ──HMAC──▶ POST /grafana ──▶ KV: sent? routes? devices ──▶ APNs
Brazier app ──Bearer ID token──▶ POST /devices, DELETE /devices/:token
```

| Route | Auth | Does |
|---|---|---|
| `POST /grafana` | `X-Grafana-Alerting-Signature`: HMAC-SHA256 hex over `<timestamp>:<body>` (or the body alone without a timestamp header), constant-time compare | Per alert: skip if already sent for this fingerprint, status and start time; route the labels to users; push to each of their devices; forget devices Apple reports gone |
| `POST /devices` | `Authorization: Bearer <OIDC ID token>` verified against `JWKS_URL`, `JWT_ISSUER`, `JWT_AUDIENCE` | Body `{ "token": "<APNs hex>", "platform": "ios", "environment": "production" \| "sandbox", "name": "…" }`. Idempotent. The user key is `preferred_username`, lower case |
| `GET /devices` | same | The caller's devices, tokens elided |
| `DELETE /devices/:token` | same | Forget one device |
| `GET /health` | none | `{ ok, version, kv, apns, webhook }` |

## Run it yourself

1. Copy `wrangler.jsonc`, change `name`, `account_id`, the KV namespace id (`wrangler kv namespace create DEVICES`) and the route.
2. Set the vars: `JWKS_URL`, `JWT_ISSUER`, `JWT_AUDIENCE` for your identity provider's app; `ROUTES` (see below); `APNS_TEAM_ID`, `APNS_TOPIC`, `APNS_KEY_ID`.
3. `wrangler secret put WEBHOOK_SECRET` (any random string; the same value goes on the Grafana contact point) and `wrangler secret put APNS_KEY < AuthKey_XXXX.p8`.
4. `npm install && npm test && npm run deploy`.
5. In Grafana: a webhook contact point at `https://<relay>/grafana` with **HMAC signature** on, secret = `WEBHOOK_SECRET`, header `X-Grafana-Alerting-Signature`, timestamp header `X-Grafana-Alerting-Timestamp`. Point a notification policy at it.

The APNs key belongs to the Apple developer account that ships the app. Until the push-grant service exists (milestone 4 in the build guide), a self-hosted relay needs its own build of the app under its own bundle id.

## Routes

`ROUTES` is JSON: a label matcher to a user or list of users, first match wins, `*` is the default owner.

```json
{ "site=meade-manor": "dmeade", "host=~ovh|oc-.*": ["cjackson", "dmeade"], "*": "cjackson" }
```

## What a push carries

`aps.alert` title, subtitle (`site · host`) and body (the `summary` annotation, else the first label); `thread-id` = the Grafana folder; `category` = `ALERT` so the app can offer Silence; `interruption-level` = `time-sensitive` for `severity=page`, else `active`; a resolved alert reuses the firing alert's collapse id (its fingerprint) so the lock screen shows one line, and carries no sound. A top-level `brazier` object holds the fingerprint, status, labels, annotations, `generatorURL`, `silenceURL`, `externalURL` and folder.

## Tests

`npm test` runs in the Workers runtime (vitest-pool-workers): signature good, bad, tampered and missing, Grafana 13.2's own captured webhook (`test/capture.json`), device registration with good and bad tokens, routing, dedupe, sandbox vs production, a 410 from Apple dropping the device, and an unconfigured relay accepting webhooks without sending.
