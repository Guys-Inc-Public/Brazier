# Brazier relay

Grafana's webhook in, Apple's push out. One Cloudflare Worker, one KV namespace, no framework, no database.

```
Grafana contact point ──HMAC──▶ POST /grafana ──▶ KV: sent? routes? devices ──▶ APNs
Brazier app ──its Grafana credential──▶ POST /devices ──▶ that Grafana's /api/user says who
```

| Route | Auth | Does |
|---|---|---|
| `POST /grafana` | `X-Grafana-Alerting-Signature`: HMAC-SHA256 hex over `<timestamp>:<body>` (or the body alone without a timestamp header), constant-time compare; or HTTP Basic with `WEBHOOK_SECRET` as the password for Grafanas too old to sign | Per alert: skip if already sent for this org, fingerprint, status and start time; route the labels to users; push to each of their devices that wants it (see preferences); forget devices Apple reports gone |
| `POST /devices` | Headers `X-Grafana-Url: <origin>` and exactly one of `Authorization: Bearer <service account token>`, `Cookie: <the cookies for that host>`, `X-JWT-Assertion: <OIDC token>`: the same credential the app uses for Grafana. The relay asks that Grafana `/api/user` who it is; the origin must be on `GRAFANA_URLS` | Body `{ "token": "<APNs hex>", "platform": "ios", "environment": "production" \| "sandbox", "name": "…", "prefs"?: … }`. Idempotent; a re-registration without `prefs` keeps the ones filed. Devices are filed under the Grafana login, with the email as an alias |
| `GET /devices` | same | The caller's devices, tokens elided, each with its `prefs` |
| `PUT /devices/:token/preferences` | same | Replaces that device's preferences (below); 404 when the token is not one of the caller's |
| `DELETE /devices/:token` | same | Forget one device |
| `GET /health` | none | `{ ok, version, kv, apns, push, webhook, grafana }`; `push` is `key` (an APNs key of its own), `grant` (borrowing tokens from the push grant) or `none` |
| `GET /.well-known/brazier` | none | The Grafanas this relay serves and, per Grafana, how the app signs in through its identity provider (`SIGN_IN`), so a user only types the addresses |

## Let the app find you

A user should only have to type their Grafana's address. The app then looks, in this order, for a signpost the Grafana admin owns:

1. `https://<grafana host>/.well-known/brazier`, served in front of Grafana by the proxy already there. It is this relay's own discovery document, so point the path at the relay: on Cloudflare, a Worker route `<grafana host>/.well-known/brazier*` on this Worker (that is what `wrangler.jsonc` does for the estate); on nginx or Caddy, a `proxy_pass` / `reverse_proxy` for that one path to `https://<relay>/.well-known/brazier`.
2. A DNS TXT record at `_brazier.<grafana host>`, for admins without a proxy, read over DNS-over-HTTPS: `v=brazier1 relay=https://<relay>` and optionally `issuer=… client_id=… name=…` so sign-in works without a relay at all.
3. Failing both, the app asks for the relay address, and after that for sign-in the old way.

The document says: `{ "relay": { "url", "version" }, "grafana": { "<origin>": { "signIn"?: { "issuer", "clientId", "name" } } } }`. `RELAY_URL` names this relay's public address in it.

## Run it yourself

You need a Cloudflare account (the free plan is enough), Node 22 and about ten minutes.

1. Clone this repository and `cd relay`. `npm install --legacy-peer-deps`, then `npx wrangler login` (or set `CLOUDFLARE_API_TOKEN`).
2. `npx wrangler kv namespace create DEVICES` and put the id it prints into `wrangler.jsonc`; set `account_id` to yours, `name` if you like, and the route to the hostname the relay will live on (a custom domain in a zone you have on Cloudflare, or delete the routes and use the `workers.dev` address wrangler prints).
3. Vars in `wrangler.jsonc`: `GRAFANA_URLS` (your Grafana's origin, `https://grafana.example.com`; the relay refuses to talk to any other), `RELAY_URL` (the relay's own public address), `ROUTES` (who hears what, below; `{"*":"you@example.com"}` sends everything to one person); remove `APNS_KEY_ID` unless you have a key of your own. Optional: `ORGS` if your Grafana has more than one organization, so the lock screen names it (`{"1":"Infrastructure","2":"Guys Inc Public"}`); `SIGN_IN` if your Grafana signs in through an identity provider that needs a passkey or refuses in-app web views (`{"https://grafana.example.com":{"issuer":"<OIDC issuer>","clientId":"<public PKCE client for the app, redirect brazier://auth/callback>","name":"<what the button says>"}}`, with Grafana's `[auth.jwt]` pointed at that provider; the app then signs in through the system sheet and hands Grafana the ID token).
4. `npx wrangler secret put WEBHOOK_SECRET`: any long random string; the same value goes on the Grafana contact point.
5. `npm test && npx wrangler deploy`. `curl https://<relay>/health` answers `ok: true` with `push: none`.
6. Push, one of two ways. **Without an APNs key of your own** (the usual case, next section): register with the push grant and set `PUSH_GRANT_URL` and `PUSH_GRANT_KEY`. **With your own key** (you ship your own build of the app under your own bundle id): `npx wrangler secret put APNS_KEY < AuthKey_XXXX.p8` and the vars `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`.
7. In Grafana: a webhook contact point at `https://<relay>/grafana` with **HMAC signature** on, secret = `WEBHOOK_SECRET`, header `X-Grafana-Alerting-Signature`, timestamp header `X-Grafana-Alerting-Timestamp`; on a Grafana older than 11, use the contact point's Basic auth instead with any username and `WEBHOOK_SECRET` as the password. Point a notification policy at it, with resolved messages on.
8. Put up the signpost (previous section) so the app finds the relay from the Grafana address, or type the relay address once in the app.

## Push without an APNs key of your own

Apple only accepts a push for the Brazier app from a token signed with Guys Inc's key. The push grant (`grant/` in this repository, decision 0005) lends your relay such a token, fifty minutes at a time; the key never leaves Guys Inc and your alerts never pass through it. Register once, after the relay is deployed and reachable:

```
curl -X POST https://grant.brazier.gicloud.org/relays \
  -H 'content-type: application/json' -H 'user-agent: curl' \
  -d '{"relay":"https://<relay>"}'
```

The answer carries `relayKey`, shown once. Then:

```
npx wrangler secret put PUSH_GRANT_KEY          # the relayKey
# wrangler.jsonc vars: "PUSH_GRANT_URL": "https://grant.brazier.gicloud.org"
npx wrangler deploy
```

`GET /health` now says `push: grant`. The relay asks the grant for a token when it has none or when the kept one (`grant/token` in KV) is five minutes from lapsing, at most once a minute, and sends every push to Apple itself with it. If the grant is down or refuses the key, the webhook is still accepted and each send counts as `failed`; the devices stay.

## Routes

`ROUTES` is JSON: a label matcher to a Grafana user (login or email) or a list of them, first match wins, `*` is the default owner.

```json
{ "site=meade-manor": "daniel@example.com", "host=~ovh|oc-.*": ["cam@example.com", "daniel@example.com"], "*": "cam@example.com" }
```

## Preferences

Each device may carry what it wants to hear, set from the app's Notifications screen and applied by the relay at send time, so a phone's choice never depends on Grafana's notification policies:

```json
{ "orgs": [1, 4], "minSeverity": "critical", "quiet": { "start": "22:00", "end": "07:00", "tz": "America/Chicago", "allowPage": true } }
```

- `orgs`: Grafana organization ids; absent, null or empty means every org. An alert from any other org is not sent to that device.
- `minSeverity`: `info`, `warning`, `critical` or `page`. The `severity` label is read case-insensitively (`warn` is warning, `crit`, `high` and `error` are critical, `emergency` is page); a missing or unknown severity counts as warning. A resolved alert carries the same label as its firing, so a suppressed firing never produces a lone resolved push.
- `quiet`: a window in the device's own zone, which may cross midnight. Inside it a push is still delivered, without a sound and at the passive interruption level, so it waits in the list; a `severity=page` alert still sounds unless `allowPage` is false. A zone the runtime does not know means no window.

The webhook's answer counts `filtered` (device sends skipped by org or severity) and `quiet` (delivered silently) beside `received`, `pushed`, `skipped`, `unrouted`, `dropped` and `failed`.

## What a push carries

`aps.alert` title, subtitle (`org · site · host`, the org when `ORGS` names it) and body (the `summary` annotation, else the first label); Grafana's own `DatasourceError` and `DatasourceNoData` alerts are titled by the rule (`<rule> · query failed`, `<rule> · no data`), subtitled by the datasource, with the error as the body, since their summary is templated with no labels; drop them with `"alertname=DatasourceError": []` in `ROUTES` if unwanted; `thread-id` = the Grafana folder; `category` = `ALERT` so the app can offer Silence; `interruption-level` = `time-sensitive` for `severity=page`, else `active`; a resolved alert reuses the firing alert's collapse id (its fingerprint) so the lock screen shows one line, and carries no sound. A top-level `brazier` object holds the fingerprint, status, labels, annotations, `generatorURL`, `silenceURL`, `externalURL`, folder, `orgId` and `org` (the name from `ORGS`, when set). The dedupe record is per org as well as per fingerprint, state and start time, since a fingerprint is a hash of the labels and two orgs may share a rule.

## Tests

`npm test` runs in the Workers runtime (vitest-pool-workers): signature good, bad, tampered and missing, Grafana 13.2's own captured webhook (`test/capture.json`), device registration through a stub Grafana with token, session and OIDC credentials, unknown credentials, a Grafana not on the allow list, an unreachable one, the email alias, routing, dedupe per org, the org name on the lock screen, sandbox vs production, a 410 from Apple dropping the device, an unconfigured relay accepting webhooks without sending, the push grant (a borrowed token used and kept, refreshed when about to lapse, a refusal counted as a failure with the device kept), severity ranking, and the preferences: validation, kept across a re-registration, replaced on PUT, the org and severity filters, and quiet hours around midnight, with a page let through, and with a zone the runtime cannot read.
