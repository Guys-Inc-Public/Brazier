# The demo Grafana

A small Grafana with a demo user, three dashboards and three alert rules on synthetic data, for Apple's
reviewer and for anyone who wants to try Brazier before pointing it at their own Grafana. It needs no
Keystone: the reviewer signs in with a username and password on the app's own card.

Address: `https://demo.brazier.gicloud.org`. Type that on the app's address step; the relay and the
sign-in cards appear on their own.

## Where it runs

Two parts:

- `stack/` runs on the OVH box under `/opt/brazier-demo` with Docker Compose: `grafana/grafana:13.2.3`
  on `127.0.0.1:3010`, provisioned from `stack/provisioning` (the TestData data source, the dashboards
  in `dashboards/json`, the rules and the `brazier` contact point that signs webhooks for the relay),
  and an nginx gate on `0.0.0.0:8880` that answers 403 to anything without the `X-Demo-Key` header.
  The secrets sit in `/opt/brazier-demo/.env` on the box (see `stack/.env.example`).
- The Worker in `src/` is `brazier-demo` on the custom domain `demo.brazier.gicloud.org`. It forwards
  every request to the gate with the key, hands Grafana's redirects and cookies through untouched,
  answers `/.well-known/brazier` with the relay's discovery document and keeps robots out.

The relay at `brazier.gicloud.org` serves the demo origin too: its `GRAFANA_URLS` names it, and
`ROUTES` sends alerts labelled `site=demo` to the `reviewer` login, so a phone registered through the
demo gets the demo's pushes and nobody else's.

## The reviewer account

Login `reviewer`, role Editor (so a silence from the phone works). The password, the admin password and
the gate key are in `/root/.config/brazier/demo-credentials` on mitochondria, mode 600, never in this
repository. The same values go into App Store Connect's review notes.

## What the reviewer sees

Alerts: "Disk above 85 percent" (warn, always firing), "Certificate expiring" (page, always firing) and
"Container restarting" (warn, flapping about once a minute, so a resolved push follows a firing one).
Dashboards in the folder Demo: Estate uptime (stat tiles, every service, a reachability timeline, response
times), Hosts (CPU, memory, disk, network) and Containers (counts, a table, load by container).

## Redeploying

The stack, from mitochondria:

```
rsync -a --delete -e 'ssh -p 377' demo/stack/ root@51.79.19.128:/opt/brazier-demo/
ssh -p 377 root@51.79.19.128 'cd /opt/brazier-demo && docker compose up -d'
```

Grafana re-reads provisioning on start; alerting files need `POST /api/admin/provisioning/alerting/reload`
or a restart. The Worker, from `demo/`:

```
npm ci --legacy-peer-deps
npm test
CLOUDFLARE_API_TOKEN=… ./node_modules/.bin/wrangler deploy
```

`wrangler secret put DEMO_KEY` once, with the gate key.

## Why a Worker and a key

The Cloudflare token the sessions hold can deploy Workers and custom domains but cannot edit DNS or the
tunnels, so the box is reached on a plain public port instead. The key makes that port useless to
anyone but the Worker; the Worker gives the demo its hostname and TLS. Two Workers facts shaped it: a
fetch to an IP literal fails with Cloudflare error 1003, so the origin is the box's OVH hostname
(`ns566383.ip-51-79-19.net`), and a fetch to an outside host works only on the ports Cloudflare
proxies, so the gate listens on 8880.
