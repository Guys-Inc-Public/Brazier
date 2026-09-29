# Brazier push grant

Apple only accepts a push for the Brazier app from a provider token signed with the key of the team that ships it. That key is ours and stays here: this Worker signs short-lived provider tokens for relays other people run (decision 0005). The relay then talks to Apple itself, so no alert ever passes through us.

```
your relay ──POST /grant, Bearer <relay key>──▶ brazier-grant ──▶ { token, topic, expiresAt }
your relay ──bearer <token>──▶ api.push.apple.com
```

| Route | Auth | Does |
|---|---|---|
| `POST /relays` | none | Body `{ "relay": "https://<your relay>" }`. The address must be https and public, and must answer `/.well-known/brazier` like a Brazier relay. Answers `{ ok, relayKey, topic, relay }` once; only a hash of the key is kept. 409 if that relay is already registered |
| `POST /grant` | `Authorization: Bearer <relay key>` | A provider token for the Brazier topic: `{ token, keyId, teamId, topic, issuedAt, expiresAt }`, good for 50 minutes; one grant a minute per relay (429 with `retry-after` otherwise) |
| `GET /health` | none | `{ ok, version, apns, relays }` |

## Register your relay

Deploy your relay first (it must be reachable at its https address), then:

```
curl -X POST https://grant.brazier.gicloud.org/relays \
  -H 'content-type: application/json' -H 'user-agent: curl' \
  -d '{"relay":"https://relay.example.com"}'
```

Keep the `relayKey` from the answer: it is shown once. Give it to your relay and tell it where the grant is:

```
cd relay
npx wrangler secret put PUSH_GRANT_KEY      # paste the relayKey
# and in wrangler.jsonc vars: "PUSH_GRANT_URL": "https://grant.brazier.gicloud.org"
npx wrangler deploy
```

`GET /health` on your relay then says `"push": "grant"`. You can ask for a token by hand too:

```
curl -X POST https://grant.brazier.gicloud.org/grant -H 'authorization: Bearer <relayKey>' -H 'user-agent: curl'
```

## What a relay key can do

Push to Brazier's topic (`org.guysinc.brazier`), to device tokens the relay already holds because its users registered their phones with it. It cannot read anything, cannot push to another app and cannot obtain more than one token a minute. If a key leaks, the worst case is unwanted pushes to that relay's own users; we revoke it by deleting its record (`relays/<sha256 of the key>` and `url/<origin>` in the `RELAYS` namespace), after which the relay registers again for a new one.

## Run and test

`npm install --legacy-peer-deps`, `npm test` (the Workers runtime: registration of a relay that answers like one, refusal of one that does not or is http or loopback, a duplicate, a grant with a bad key, a grant whose token verifies against the test key, the rate limit, health), `npm run check`. Deploy with `wrangler secret put APNS_KEY < AuthKey_XXXX.p8` and `wrangler deploy`; the vars are in `wrangler.jsonc`.
