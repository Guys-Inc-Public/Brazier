# Contract tests

Every call the app and the relay make to Grafana, run against a real one. `run.sh` starts the image in
Docker with JWT auth pointed at a throwaway key, runs `grafana.test.mjs` with Node's own test runner, and
removes the container. CI runs it against the official 11, 12 and 13 images; run it here the same way:

```
bash contract/run.sh grafana/grafana-oss:11.6.5
```

What it checks, in order: the public health and login page the address step reads; the JSON login the
password card posts and the cookie it keeps; organizations and `X-Grafana-Org-Id`; a service-account
token as Bearer; search, the dashboard JSON and `/api/ds/query` the tiles use; an alert rule firing into
the instances list; the webhook's shape and its signature (HMAC on 11+, else Basic); a silence created,
listed and expired; what a visitor may read when anonymous access is on (and what it may not); a star by
uid; state history; `X-JWT-Assertion` through auth.jwt with a wrong issuer refused; and
that a dashboard page renders signed in with a Bearer token or a JWT header. It also pins one negative
fact the app is built around: `?auth_token=` (url_login) never sets a session cookie.

`probe.sh IMAGE NAME` starts the same Grafana for hand probing and prints its port; `pageauth.mjs` is the
probe that settled the web-view question.
