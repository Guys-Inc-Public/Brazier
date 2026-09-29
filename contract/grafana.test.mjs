// The contract between Brazier and Grafana: every call the app and the relay make, against a real Grafana.
// Run through run.sh; CI runs it against the official 11, 12 and 13 images.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createSign } from "node:crypto";
import { join } from "node:path";
import { api, base, admin, basic, version, major, waitFor, receiver, hmacHex } from "./lib.mjs";

const SECRET = "contract-webhook-secret";
const state = { version: "0", major: 0, ds: null, folder: null, dashboard: null, org2: null, token: null, hook: null, silence: null };

before(async () => {
  state.version = await version();
  state.major = major(state.version);
  console.log(`Grafana ${state.version}`);
});
after(() => state.hook?.close());

// ---- what the app needs before sign-in -------------------------------------------------------------

test("GET /api/health is public and names the version", async () => {
  const r = await api("GET", "/api/health", { auth: null });
  assert.equal(r.status, 200);
  assert.equal(r.json.database, "ok");
  assert.match(r.json.version, /^\d+\.\d+/);
});

test("the public login page carries grafanaBootData with the sign-in shape", async () => {
  const res = await fetch(`${base}/login?disableAutoLogin=true`, { headers: { "User-Agent": "brazier-contract" }, redirect: "manual" });
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /grafanaBootData/);
  const m = /"disableLoginForm":(true|false)/.exec(html);
  assert.ok(m, "settings.disableLoginForm present");
  assert.match(html, /"anonymousEnabled":(true|false)/);
});

test("GET /api/user without a credential is 401, not a redirect", async () => {
  const r = await api("GET", "/api/user", { auth: null });
  assert.equal(r.status, 401);
});

// ---- the native username-and-password card ------------------------------------------------------------

test("POST /login with JSON answers a session cookie; a wrong password is 401 password-auth.failed", async () => {
  const ok = await fetch(`${base}/login`, {
    method: "POST", redirect: "manual",
    headers: { "Content-Type": "application/json", Accept: "application/json", "User-Agent": "brazier-contract" },
    body: JSON.stringify({ user: admin.user, password: admin.password }),
  });
  assert.equal(ok.status, 200);
  const cookies = ok.headers.getSetCookie();
  const session = cookies.find((c) => c.startsWith("grafana_session="));
  assert.ok(session, "Set-Cookie grafana_session");
  state.cookie = cookies.map((c) => c.split(";")[0]).join("; ");
  const bad = await fetch(`${base}/login`, {
    method: "POST", redirect: "manual",
    headers: { "Content-Type": "application/json", Accept: "application/json", "User-Agent": "brazier-contract" },
    body: JSON.stringify({ user: admin.user, password: "wrong" }),
  });
  assert.equal(bad.status, 401);
  const body = await bad.json();
  assert.equal(body.messageId, "password-auth.failed");
});

test("the session cookie authenticates /api/user as a Cookie header", async () => {
  const r = await api("GET", "/api/user", { auth: null, headers: { Cookie: state.cookie } });
  assert.equal(r.status, 200);
  assert.equal(r.json.login, admin.user);
  assert.equal(typeof r.json.email, "string");
});

// ---- organizations ----------------------------------------------------------------------------------

test("a second org exists, the user is in it, and X-Grafana-Org-Id scopes a call", async () => {
  const created = await api("POST", "/api/orgs", { body: { name: "Contract second org" } });
  assert.ok([200, 409].includes(created.status), `create org: ${created.status} ${created.text}`);
  const orgs = await api("GET", "/api/orgs");
  state.org2 = orgs.json.find((o) => o.name === "Contract second org").id;
  const add = await api("POST", `/api/orgs/${state.org2}/users`, { body: { loginOrEmail: admin.user, role: "Admin" } });
  assert.ok([200, 409].includes(add.status), `add user: ${add.status} ${add.text}`);
  const mine = await api("GET", "/api/user/orgs");
  assert.equal(mine.status, 200);
  const names = mine.json.map((o) => o.name);
  assert.ok(names.includes("Contract second org"), `user orgs: ${names}`);
  for (const o of mine.json) {
    assert.equal(typeof o.orgId, "number");
    assert.equal(typeof o.name, "string");
    assert.equal(typeof o.role, "string");
  }
  const dash = await api("POST", "/api/dashboards/db", { org: state.org2, body: { dashboard: { title: "Only in org two", uid: "contract-org2", panels: [] }, overwrite: true } });
  assert.equal(dash.status, 200, dash.text);
  const inTwo = await api("GET", "/api/search?type=dash-db&query=Only%20in%20org%20two", { org: state.org2 });
  assert.equal(inTwo.json.length, 1);
  const inOne = await api("GET", "/api/search?type=dash-db&query=Only%20in%20org%20two", { org: 1 });
  assert.equal(inOne.json.length, 0, "org 1 must not see org 2's dashboard");
});

// ---- a service account token, as the token card uses it ------------------------------------------------

test("a service account token authenticates as Bearer and /api/user names it", async () => {
  const sa = await api("POST", "/api/serviceaccounts", { body: { name: "brazier-contract", role: "Editor", isDisabled: false } });
  assert.ok([201, 200].includes(sa.status), sa.text);
  const tok = await api("POST", `/api/serviceaccounts/${sa.json.id}/tokens`, { body: { name: "contract" } });
  assert.ok([200, 201].includes(tok.status), tok.text);
  state.token = tok.json.key;
  assert.match(state.token, /^glsa_/);
  const me = await api("GET", "/api/user", { auth: `Bearer ${state.token}` });
  assert.equal(me.status, 200);
  assert.match(me.json.login, /^sa-/);
});

// ---- dashboards and datasources --------------------------------------------------------------------------

test("a testdata datasource, a folder and a dashboard exist; search and the dashboard JSON read back", async () => {
  let ds = await api("POST", "/api/datasources", { body: { name: "contract-testdata", type: "grafana-testdata-datasource", access: "proxy" } });
  if (ds.status === 409) {
    const found = await api("GET", "/api/datasources/name/contract-testdata");
    ds = { status: 200, json: { datasource: found.json } };
  }
  assert.equal(ds.status, 200, ds.text);
  state.ds = ds.json.datasource;
  const folder = await api("POST", "/api/folders", { body: { title: "Contract", uid: "contract" } });
  assert.ok([200, 409, 412].includes(folder.status), folder.text);
  state.folder = folder.status === 200 ? folder.json : (await api("GET", "/api/folders/contract")).json;
  const dashboard = {
    uid: "contract-stats", title: "Contract stats", tags: ["contract", "brazier"], panels: [
      { id: 1, type: "stat", title: "Answer", gridPos: { h: 4, w: 6, x: 0, y: 0 },
        datasource: { type: "grafana-testdata-datasource", uid: state.ds.uid },
        targets: [{ refId: "A", scenarioId: "csv_metric_values", stringInput: "42,42,42", datasource: { type: "grafana-testdata-datasource", uid: state.ds.uid } }],
        fieldConfig: { defaults: { unit: "short", thresholds: { mode: "absolute", steps: [{ color: "green", value: null }, { color: "red", value: 80 }] } }, overrides: [] },
        options: { reduceOptions: { calcs: ["lastNotNull"], fields: "", values: false }, colorMode: "value", graphMode: "none", textMode: "value" } },
      { id: 2, type: "timeseries", title: "Walk", gridPos: { h: 8, w: 12, x: 6, y: 0 },
        datasource: { type: "grafana-testdata-datasource", uid: state.ds.uid },
        targets: [{ refId: "A", scenarioId: "random_walk", datasource: { type: "grafana-testdata-datasource", uid: state.ds.uid } }] },
    ],
    time: { from: "now-1h", to: "now" }, schemaVersion: 39,
  };
  const save = await api("POST", "/api/dashboards/db", { body: { dashboard, folderUid: "contract", overwrite: true } });
  assert.equal(save.status, 200, save.text);
  state.dashboard = save.json;
  const star = await api("POST", `/api/user/stars/dashboard/uid/${dashboard.uid}`);
  assert.ok([200, 400].includes(star.status), `star: ${star.status} ${star.text}`);
  const hits = await api("GET", "/api/search?type=dash-db&limit=200");
  const hit = hits.json.find((h) => h.uid === "contract-stats");
  assert.ok(hit, "search finds the dashboard");
  for (const k of ["uid", "title", "url", "type"]) assert.equal(typeof hit[k], "string", k);
  assert.ok(Array.isArray(hit.tags));
  assert.equal(hit.folderTitle, "Contract");
  assert.equal(typeof hit.isStarred, "boolean");
  const json = await api("GET", "/api/dashboards/uid/contract-stats");
  assert.equal(json.status, 200);
  assert.equal(json.json.dashboard.panels.length, 2);
  assert.equal(json.json.dashboard.panels[0].type, "stat");
  assert.equal(json.json.meta.folderUid ?? json.json.meta.folderUid, "contract");
});

test("POST /api/ds/query runs a stat panel's query and answers frames", async () => {
  const r = await api("POST", "/api/ds/query", {
    body: {
      from: "now-5m", to: "now",
      queries: [{ refId: "A", datasource: { type: "grafana-testdata-datasource", uid: state.ds.uid }, scenarioId: "csv_metric_values", stringInput: "42,42,42", intervalMs: 60000, maxDataPoints: 100 }],
    },
  });
  assert.equal(r.status, 200, r.text);
  const frames = r.json.results.A.frames;
  assert.ok(Array.isArray(frames) && frames.length >= 1, "frames");
  const values = frames[0].data.values;
  assert.ok(Array.isArray(values) && values.length >= 2, "time + value columns");
  const last = values[values.length - 1].at(-1);
  assert.equal(Number(last), 42);
});

// ---- alerting: rule, instances list, silence, webhook -------------------------------------------------------

test("a webhook contact point and an always-firing rule routed to it are provisioned", async () => {
  state.hook = await receiver();
  const settings = { url: `http://host.docker.internal:${state.hook.port}/grafana`, httpMethod: "POST", username: "brazier", password: SECRET };
  let cp = await api("POST", "/api/v1/provisioning/contact-points", {
    body: { name: "brazier-contract", type: "webhook", disableResolveMessage: false,
      settings: { ...settings, hmacConfig: { secret: SECRET, header: "X-Grafana-Alerting-Signature", timestampHeader: "X-Grafana-Alerting-Timestamp" } } },
    headers: { "X-Disable-Provenance": "true" },
  });
  if (cp.status >= 400) {
    // Grafanas before HMAC signing refuse the unknown setting: fall back to Basic auth alone.
    cp = await api("POST", "/api/v1/provisioning/contact-points", { body: { name: "brazier-contract", type: "webhook", disableResolveMessage: false, settings }, headers: { "X-Disable-Provenance": "true" } });
    state.hmac = false;
  } else {
    state.hmac = true;
  }
  assert.ok([200, 202].includes(cp.status), `contact point: ${cp.status} ${cp.text}`);
  const rule = {
    title: "Contract always firing", ruleGroup: "contract", folderUID: "contract", orgID: 1,
    condition: "C", noDataState: "OK", execErrState: "Error", for: "0s",
    labels: { severity: "warn", host: "contract" },
    annotations: { summary: "The contract test rule, always firing" },
    notification_settings: { receiver: "brazier-contract" },
    data: [
      { refId: "A", relativeTimeRange: { from: 600, to: 0 }, datasourceUid: state.ds.uid,
        model: { refId: "A", scenarioId: "csv_metric_values", stringInput: "1,1,1,1", datasource: { type: "grafana-testdata-datasource", uid: state.ds.uid } } },
      { refId: "B", datasourceUid: "__expr__", model: { refId: "B", type: "reduce", expression: "A", reducer: "last", datasource: { type: "__expr__", uid: "__expr__" } } },
      { refId: "C", datasourceUid: "__expr__", model: { refId: "C", type: "threshold", expression: "B", conditions: [{ evaluator: { type: "gt", params: [0] } }], datasource: { type: "__expr__", uid: "__expr__" } } },
    ],
  };
  const r = await api("POST", "/api/v1/provisioning/alert-rules", { body: rule, headers: { "X-Disable-Provenance": "true" } });
  assert.ok([200, 201].includes(r.status), `rule: ${r.status} ${r.text}`);
  state.ruleUID = r.json.uid;
  const group = await api("PUT", "/api/v1/provisioning/folder/contract/rule-groups/contract", { body: { title: "contract", interval: 10, rules: [r.json] }, headers: { "X-Disable-Provenance": "true" } });
  assert.ok([200, 202].includes(group.status), `group interval: ${group.status} ${group.text}`);
});

test("GET /api/prometheus/grafana/api/v1/alerts lists the instance as it fires", async () => {
  const alert = await waitFor("the rule to fire", async () => {
    const r = await api("GET", "/api/prometheus/grafana/api/v1/alerts");
    if (r.status !== 200) return null;
    const a = r.json.data.alerts.find((x) => x.labels.alertname === "Contract always firing");
    return a && /^(alerting|firing)$/i.test(a.state) ? a : null;
  }, { timeoutMs: 120_000 });
  assert.equal(alert.labels.severity, "warn");
  assert.equal(alert.labels.grafana_folder, "Contract");
  assert.equal(typeof alert.activeAt, "string");
  assert.equal(alert.annotations.summary, "The contract test rule, always firing");
  state.alert = alert;
});

test("the webhook arrives with fingerprint, status, labels and orgId, signed or with Basic auth", async () => {
  const hit = await waitFor("the webhook", async () => state.hook.hits.find((h) => h.path === "/grafana") ?? null, { timeoutMs: 120_000 });
  const body = JSON.parse(hit.body);
  assert.ok(Array.isArray(body.alerts) && body.alerts.length >= 1);
  const a = body.alerts.find((x) => x.labels.alertname === "Contract always firing") ?? body.alerts[0];
  assert.match(a.fingerprint, /^[0-9a-f]{16}$/);
  assert.equal(a.status, "firing");
  assert.equal(a.labels.severity, "warn");
  assert.equal(typeof a.startsAt, "string");
  assert.equal(body.orgId ?? a.orgId, 1, "orgId on the body or the alert");
  assert.equal(typeof body.externalURL, "string");
  const sig = hit.headers["x-grafana-alerting-signature"];
  const ts = hit.headers["x-grafana-alerting-timestamp"];
  if (sig) {
    assert.equal(sig, hmacHex(SECRET, ts, hit.body), "HMAC over timestamp:body with the secret");
    state.signed = "hmac";
  } else {
    assert.equal(hit.headers.authorization, "Basic " + Buffer.from(`brazier:${SECRET}`).toString("base64"));
    state.signed = "basic";
  }
  console.log(`webhook auth on ${state.version}: ${state.signed}`);
});

test("a silence is created for the instance, listed active, then expired", async () => {
  const now = new Date();
  const later = new Date(now.getTime() + 3600_000);
  const body = {
    matchers: Object.entries(state.alert.labels).filter(([k]) => !k.startsWith("__")).map(([name, value]) => ({ name, value, isRegex: false, isEqual: true })),
    startsAt: now.toISOString(), endsAt: later.toISOString(), createdBy: "brazier-contract", comment: "Silenced from the contract test",
  };
  const created = await api("POST", "/api/alertmanager/grafana/api/v2/silences", { body });
  assert.ok([200, 201, 202].includes(created.status), created.text);
  assert.equal(typeof created.json.silenceID, "string");
  state.silence = created.json.silenceID;
  const list = await api("GET", "/api/alertmanager/grafana/api/v2/silences");
  const mine = list.json.find((s) => s.id === state.silence);
  assert.ok(mine, "listed");
  assert.equal(mine.status.state, "active");
  assert.equal(mine.createdBy, "brazier-contract");
  assert.ok(Array.isArray(mine.matchers) && mine.matchers.every((m) => "name" in m && "value" in m && "isRegex" in m && "isEqual" in m));
  const gone = await api("DELETE", `/api/alertmanager/grafana/api/v2/silence/${state.silence}`);
  assert.equal(gone.status, 200);
});

// ---- anonymous access: browse without signing in -------------------------------------------------------

test("with anonymous access on, alerts, search, a dashboard and its query read with no credential; /api/user, orgs and a silence do not", async () => {
  // The app's "Browse without signing in" card: the login page says anonymousEnabled, the reads work
  // without a credential, and everything that needs a person answers 401 (or 403 for a Viewer).
  const page = await api("GET", "/login?disableAutoLogin=true", { auth: null, headers: { Accept: "text/html" } });
  assert.match(page.text, /"anonymousEnabled":true/);
  const alerts = await api("GET", "/api/prometheus/grafana/api/v1/alerts", { auth: null });
  assert.equal(alerts.status, 200, alerts.text);
  assert.ok(Array.isArray(alerts.json.data.alerts));
  const search = await api("GET", "/api/search?type=dash-db&limit=200", { auth: null });
  assert.equal(search.status, 200);
  assert.ok(search.json.some((h) => h.uid === state.dashboard.uid));
  const dash = await api("GET", `/api/dashboards/uid/${state.dashboard.uid}`, { auth: null });
  assert.equal(dash.status, 200);
  const panel = dash.json.dashboard.panels[0];
  const query = await api("POST", "/api/ds/query", { auth: null, body: { from: "now-6h", to: "now", queries: panel.targets.map((t) => ({ ...t, datasource: { type: state.ds.type, uid: state.ds.uid }, intervalMs: 60000, maxDataPoints: 100 })) } });
  assert.equal(query.status, 200, query.text);
  const silences = await api("GET", "/api/alertmanager/grafana/api/v2/silences", { auth: null });
  assert.equal(silences.status, 200);
  const me = await api("GET", "/api/user", { auth: null });
  assert.equal(me.status, 401);
  const orgs = await api("GET", "/api/user/orgs", { auth: null });
  assert.equal(orgs.status, 401);
  const write = await api("POST", "/api/alertmanager/grafana/api/v2/silences", { auth: null, body: { matchers: [{ name: "alertname", value: "x", isRegex: false, isEqual: true }], startsAt: new Date().toISOString(), endsAt: new Date(Date.now() + 60000).toISOString(), createdBy: "anon", comment: "no" } });
  assert.ok([401, 403].includes(write.status), write.text);
});

// ---- stars ---------------------------------------------------------------------------------------------------

test("a dashboard is starred by uid, the search says so, and unstarred again", async () => {
  await api("DELETE", `/api/user/stars/dashboard/uid/${state.dashboard.uid}`); // the provisioning check may have starred it
  const on = await api("POST", `/api/user/stars/dashboard/uid/${state.dashboard.uid}`);
  assert.equal(on.status, 200, on.text);
  const starred = await api("GET", "/api/search?type=dash-db&starred=true");
  assert.ok(starred.json.some((h) => h.uid === state.dashboard.uid && h.isStarred === true), starred.text);
  const off = await api("DELETE", `/api/user/stars/dashboard/uid/${state.dashboard.uid}`);
  assert.equal(off.status, 200, off.text);
  const plain = await api("GET", "/api/search?type=dash-db");
  assert.equal(plain.json.find((h) => h.uid === state.dashboard.uid)?.isStarred, false);
});

test("GET /api/annotations?type=alert reads state history", async () => {
  const r = await api("GET", "/api/annotations?type=alert&limit=50");
  assert.equal(r.status, 200);
  assert.ok(Array.isArray(r.json));
});

// ---- JWT auth: the provider path and the dashboard web view -----------------------------------------------

function idToken(claims) {
  const key = readFileSync(join(process.env.CONTRACT_WORK, "key.pem"), "utf8");
  const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: "ES256", kid: "contract", typ: "JWT" });
  const body = b64({ iss: "https://contract.invalid/", iat: now, exp: now + 600, ...claims });
  const s = createSign("sha256"); s.update(`${head}.${body}`); s.end();
  return `${head}.${body}.${s.sign({ key, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

test("X-JWT-Assertion signs in through auth.jwt and a wrong issuer is refused", async () => {
  const ok = await api("GET", "/api/user", { auth: null, headers: { "X-JWT-Assertion": idToken({ sub: "contract-jwt", email: "jwt@contract.invalid" }) } });
  assert.equal(ok.status, 200, ok.text);
  assert.equal(ok.json.login, "contract-jwt");
  const bad = await api("GET", "/api/user", { auth: null, headers: { "X-JWT-Assertion": idToken({ iss: "https://elsewhere.invalid/", sub: "contract-jwt" }) } });
  assert.equal(bad.status, 401);
});

test("a dashboard page renders signed in with a Bearer token or a JWT header; ?auth_token= sets no cookie", async () => {
  // The app's web view carries the credential on the page load and patches the page's own fetch/XHR
  // to carry it too, because Grafana's url_login answers the page but never a session cookie (11–13).
  async function page(headers, qs = "") {
    const res = await fetch(`${base}/d/contract-stats?orgId=1&kiosk${qs}`, { headers: { "User-Agent": "brazier-contract", ...headers }, redirect: "manual" });
    const html = await res.text();
    return { status: res.status, login: /"login":"([^"]*)"/.exec(html)?.[1], cookies: res.headers.getSetCookie().map((c) => c.split("=")[0]) };
  }
  const bearer = await page({ Authorization: `Bearer ${state.token}` });
  assert.equal(bearer.status, 200);
  assert.match(bearer.login ?? "", /^sa-/);
  const jwt = await page({ "X-JWT-Assertion": idToken({ sub: "contract-jwt", email: "jwt@contract.invalid" }) });
  assert.equal(jwt.status, 200);
  assert.equal(jwt.login, "contract-jwt");
  const url = await page({}, `&auth_token=${idToken({ sub: "contract-jwt", email: "jwt@contract.invalid" })}`);
  assert.equal(url.status, 200);
  assert.equal(url.login, "contract-jwt");
  assert.ok(!url.cookies.includes("grafana_session"), "url_login does not create a session; the app must not rely on it");
});

test("a dashboard page loaded with the session cookie answers 200 in kiosk mode", async () => {
  const res = await fetch(`${base}/d/contract-stats?orgId=1&kiosk&theme=dark`, { headers: { "User-Agent": "brazier-contract", Cookie: state.cookie }, redirect: "manual" });
  assert.equal(res.status, 200);
  assert.match(await res.text(), /grafanaBootData/);
});
