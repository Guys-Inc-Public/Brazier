import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { buildPayload, sentKey } from "../src/notify";
import { readPrefs } from "../src/index";
import { inQuietHours, level, localMinutes, meets } from "../src/severity";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/env";
import { signLikeGrafana } from "../src/hmac";
import { makeApnsKeyPem, grafanaWebhook } from "./helpers";

const SECRET = "test-webhook-secret";
const GRAFANA = "https://grafana.test";
const TOKEN_A = "a".repeat(64);
const TOKEN_B = "b".repeat(64);
const TOKEN_D = "d".repeat(64);

let testEnv: Env;

/** Outbound fetches are stubbed per origin; anything unexpected throws. */
type Handler = (req: Request) => Promise<Response> | Response;
const outbound: Array<{ origin: string; handler: Handler }> = [];
const realFetch = globalThis.fetch;

/** The credentials the stub Grafana at GRAFANA accepts, and who they belong to. */
const KNOWN: Record<string, { login: string; email: string; name: string }> = {
  "bearer:glsa_cj": { login: "cjackson@guysinc.org", email: "cjackson@guysinc.org", name: "Cameron Jackson" },
  "cookie:grafana_session=sess-cj": { login: "cjackson@guysinc.org", email: "cjackson@guysinc.org", name: "Cameron Jackson" },
  "cookie:CF_Authorization=proxy-jwt; grafana_session=sess-cj": { login: "cjackson@guysinc.org", email: "cjackson@guysinc.org", name: "Cameron Jackson" },
  "jwt:id-token-cj": { login: "cjackson@guysinc.org", email: "cjackson@guysinc.org", name: "Cameron Jackson" },
  "bearer:glsa_dm": { login: "dmeade", email: "dmeade@damp.meme", name: "Daniel Meade" },
};

function stubGrafana(origin = GRAFANA) {
  outbound.push({
    origin,
    handler: (req) => {
      if (new URL(req.url).pathname !== "/api/user") return new Response("not found", { status: 404 });
      const auth = req.headers.get("authorization");
      const cookie = req.headers.get("cookie");
      const jwt = req.headers.get("x-jwt-assertion");
      const key = auth ? `bearer:${auth.replace(/^Bearer /, "")}` : cookie ? `cookie:${cookie}` : jwt ? `jwt:${jwt}` : "";
      const who = KNOWN[key];
      return who ? Response.json(who) : Response.json({ message: "Unauthorized" }, { status: 401 });
    },
  });
}

async function call(req: Request): Promise<Response> {
  const ctx = createExecutionContext();
  const res = await worker.fetch(req, testEnv, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

async function signedWebhook(body: Record<string, unknown>, opts: { secret?: string; timestamp?: string | null; header?: string } = {}) {
  const raw = new TextEncoder().encode(JSON.stringify(body));
  const ts = opts.timestamp === undefined ? String(Math.floor(Date.now() / 1000)) : opts.timestamp;
  const sig = await signLikeGrafana(opts.secret ?? SECRET, raw, ts ?? undefined);
  const headers: Record<string, string> = { "content-type": "application/json", "user-agent": "Grafana" };
  headers[opts.header ?? "X-Grafana-Alerting-Signature"] = sig;
  if (ts) headers["X-Grafana-Alerting-Timestamp"] = ts;
  return call(new Request("https://relay.test/grafana", { method: "POST", headers, body: raw }));
}

type Cred = { bearer: string } | { cookie: string } | { jwt: string };
const CJ: Cred = { bearer: "glsa_cj" };
const DM: Cred = { bearer: "glsa_dm" };

function credHeaders(cred: Cred, origin = GRAFANA): Record<string, string> {
  const h: Record<string, string> = { "x-grafana-url": origin };
  if ("bearer" in cred) h.authorization = `Bearer ${cred.bearer}`;
  else if ("cookie" in cred) h.cookie = cred.cookie;
  else h["x-jwt-assertion"] = cred.jwt;
  return h;
}

async function register(token: string, cred: Cred, extra: Record<string, unknown> = {}, origin = GRAFANA) {
  return call(
    new Request("https://relay.test/devices", {
      method: "POST",
      headers: { ...credHeaders(cred, origin), "content-type": "application/json" },
      body: JSON.stringify({ token, platform: "ios", environment: "production", name: "CJ's iPhone", ...extra }),
    }),
  );
}

/** Let APNs answer; returns the requests it saw. */
function apnsAnswers(status: number, reason?: string, host = "https://api.push.apple.com") {
  const seen: Array<{ path: string; headers: Record<string, string>; body: string }> = [];
  const others = outbound.filter((r) => r.origin !== host);
  outbound.length = 0;
  outbound.push(...others, {
    origin: host,
    handler: async (req) => {
      seen.push({ path: new URL(req.url).pathname, headers: Object.fromEntries(req.headers), body: await req.text() });
      return new Response(reason ? JSON.stringify({ reason }) : "", { status, headers: { "content-type": "application/json" } });
    },
  });
  return seen;
}

beforeAll(async () => {
  testEnv = {
    ...env,
    GRAFANA_URLS: `${GRAFANA}, https://other.test`,
    RELAY_URL: undefined, // derived from the request origin in these tests unless a test sets it
    ORGS: undefined, // wrangler.jsonc names the estate's orgs; the tests set their own
    SIGN_IN: JSON.stringify({ [GRAFANA]: { issuer: "https://idp.test/application/o/brazier/", clientId: "client-123", name: "Test Org" } }),
    ROUTES: JSON.stringify({ "site=meade-manor": "dmeade@damp.meme", "host=~ovh|oc-.*": ["cjackson@guysinc.org", "dmeade"], "*": "CJackson@guysinc.org" }),
    WEBHOOK_SECRET: SECRET,
    APNS_KEY: await makeApnsKeyPem(),
    APNS_KEY_ID: "TESTKEYID",
    APNS_TEAM_ID: "7VM43528YK",
    APNS_TOPIC: "org.guysinc.brazier",
  };
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    const origin = new URL(req.url).origin;
    const route = outbound.find((r) => r.origin === origin);
    if (!route) throw new Error(`unexpected outbound fetch ${req.url}`);
    return route.handler(req);
  }) as typeof fetch;
});

afterAll(() => {
  globalThis.fetch = realFetch;
});

beforeEach(async () => {
  outbound.length = 0;
  stubGrafana();
  // a clean registry per test
  const list = await env.DEVICES.list();
  await Promise.all(list.keys.map((k) => env.DEVICES.delete(k.name)));
});

describe("health", () => {
  it("answers with version and configuration state", async () => {
    const res = await call(new Request("https://relay.test/health"));
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(body).toMatchObject({ ok: true, kv: "ok", apns: true, push: "key", webhook: true, grafana: [GRAFANA, "https://other.test"] });
    expect(typeof body.version).toBe("string");
  });

  it("reports apns unconfigured when the key is missing", async () => {
    const saved = testEnv.APNS_KEY;
    testEnv.APNS_KEY = undefined;
    const body = (await (await call(new Request("https://relay.test/health"))).json()) as Record<string, unknown>;
    testEnv.APNS_KEY = saved;
    expect(body.apns).toBe(false);
    expect(body.push).toBe("none");
  });
});

describe("push grant", () => {
  const GRANT = "https://grant.test";
  let savedKey: string | undefined;

  /** The grant answers tokens; returns the requests it saw. */
  function grantAnswers(status = 200, expiresIn = 3000) {
    const seen: Array<{ auth: string | null; agent: string | null }> = [];
    outbound.push({
      origin: GRANT,
      handler: (req) => {
        seen.push({ auth: req.headers.get("authorization"), agent: req.headers.get("user-agent") });
        const now = Math.floor(Date.now() / 1000);
        return status === 200
          ? Response.json({ token: `granted-${seen.length}`, keyId: "PTDYNZWJJJ", teamId: "7VM43528YK", topic: "org.guysinc.brazier", issuedAt: now, expiresAt: now + expiresIn })
          : Response.json({ error: "unknown relay key" }, { status });
      },
    });
    return seen;
  }

  beforeEach(() => {
    savedKey = testEnv.APNS_KEY;
    testEnv.APNS_KEY = undefined;
    testEnv.PUSH_GRANT_URL = `${GRANT}/`;
    testEnv.PUSH_GRANT_KEY = "relay-key-123";
  });
  afterEach(() => {
    testEnv.APNS_KEY = savedKey;
    testEnv.PUSH_GRANT_URL = undefined;
    testEnv.PUSH_GRANT_KEY = undefined;
  });

  it("counts as configured with only the grant settings, and health says so", async () => {
    const body = (await (await call(new Request("https://relay.test/health"))).json()) as Record<string, unknown>;
    expect(body.apns).toBe(true);
    expect(body.push).toBe("grant");
  });

  it("borrows a token from the grant, pushes with it, and keeps it in KV for the next push", async () => {
    const grants = grantAnswers();
    const apns = apnsAnswers(200);
    expect((await register(TOKEN_A, CJ)).status).toBe(200);
    const first = await signedWebhook(grafanaWebhook([{ fingerprint: "f1" }]));
    expect(await first.json()).toMatchObject({ pushed: 1, failed: 0 });
    expect(grants).toEqual([{ auth: "Bearer relay-key-123", agent: "brazier-relay" }]);
    expect(apns[0].headers.authorization).toBe("bearer granted-1");
    expect(apns[0].headers["apns-topic"]).toBe("org.guysinc.brazier");
    const kept = (await env.DEVICES.get("grant/token", "json")) as { token: string };
    expect(kept.token).toBe("granted-1");
    const second = await signedWebhook(grafanaWebhook([{ fingerprint: "f2" }]));
    expect(await second.json()).toMatchObject({ pushed: 1 });
    expect(grants).toHaveLength(1);
    expect(apns[1].headers.authorization).toBe("bearer granted-1");
  });

  it("asks for a fresh token when the kept one is about to lapse", async () => {
    const grants = grantAnswers();
    const apns = apnsAnswers(200);
    const now = Math.floor(Date.now() / 1000);
    await env.DEVICES.put("grant/token", JSON.stringify({ token: "stale", keyId: "K", teamId: "T", topic: "org.guysinc.brazier", issuedAt: now - 2900, expiresAt: now + 100 }));
    expect((await register(TOKEN_A, CJ)).status).toBe(200);
    await signedWebhook(grafanaWebhook([{ fingerprint: "f3" }]));
    expect(grants).toHaveLength(1);
    expect(apns[0].headers.authorization).toBe("bearer granted-1");
  });

  it("keeps the device and counts a failure when the grant refuses", async () => {
    grantAnswers(401);
    const apns = apnsAnswers(200);
    expect((await register(TOKEN_A, CJ)).status).toBe(200);
    const res = await signedWebhook(grafanaWebhook([{ fingerprint: "f4" }]));
    expect(await res.json()).toMatchObject({ pushed: 0, failed: 1, dropped: 0 });
    expect(apns).toHaveLength(0);
    expect((await call(new Request("https://relay.test/devices", { headers: credHeaders(CJ) }))).status).toBe(200);
    expect(((await (await call(new Request("https://relay.test/devices", { headers: credHeaders(CJ) }))).json()) as { devices: unknown[] }).devices).toHaveLength(1);
  });
});

describe("well-known", () => {
  it("publishes the served Grafanas and how to sign in to them", async () => {
    const res = await call(new Request("https://relay.test/.well-known/brazier"));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      relay: { url: "https://relay.test", version: expect.any(String) },
      grafana: {
        [GRAFANA]: { signIn: { issuer: "https://idp.test/application/o/brazier/", clientId: "client-123", name: "Test Org" } },
        "https://other.test": {},
      },
    });
  });

  it("names its own address when served on a Grafana's hostname (Worker route) via RELAY_URL", async () => {
    testEnv.RELAY_URL = "https://relay.example";
    const body = (await (await call(new Request(`${GRAFANA}/.well-known/brazier`))).json()) as { relay: { url: string } };
    testEnv.RELAY_URL = undefined;
    expect(body.relay.url).toBe("https://relay.example");
    // and without RELAY_URL it cannot guess from a Grafana's origin
    const none = (await (await call(new Request(`${GRAFANA}/.well-known/brazier`))).json()) as { relay: { url?: string } };
    expect(none.relay.url).toBeUndefined();
  });

  it("works without any sign-in configured", async () => {
    const saved = testEnv.SIGN_IN;
    testEnv.SIGN_IN = undefined;
    const body = (await (await call(new Request("https://relay.test/.well-known/brazier"))).json()) as { grafana: Record<string, unknown> };
    testEnv.SIGN_IN = saved;
    expect(body.grafana).toEqual({ [GRAFANA]: {}, "https://other.test": {} });
  });
});

describe("POST /grafana signature", () => {
  it("rejects a missing signature", async () => {
    const res = await call(new Request("https://relay.test/grafana", { method: "POST", body: JSON.stringify(grafanaWebhook([{}])) }));
    expect(res.status).toBe(401);
  });

  it("rejects a wrong secret", async () => {
    const res = await signedWebhook(grafanaWebhook([{}]), { secret: "nope" });
    expect(res.status).toBe(401);
  });

  it("rejects a tampered body", async () => {
    const body = grafanaWebhook([{}]);
    const raw = new TextEncoder().encode(JSON.stringify(body));
    const sig = await signLikeGrafana(SECRET, raw, "1790639641");
    const tampered = JSON.stringify({ ...body, receiver: "other" });
    const res = await call(new Request("https://relay.test/grafana", { method: "POST", headers: { "X-Grafana-Alerting-Signature": sig, "X-Grafana-Alerting-Timestamp": "1790639641" }, body: tampered }));
    expect(res.status).toBe(401);
  });

  it("accepts Grafana's own capture (timestamp:body, hex) verbatim", async () => {
    // Captured from grafana 13.2.1 with secret "s3cr3t-test" (test/grafana-webhook-capture.log).
    const capture = (await import("./capture.json")).default as { headers: Record<string, string>; body: string };
    const saved = testEnv.WEBHOOK_SECRET;
    testEnv.WEBHOOK_SECRET = "s3cr3t-test";
    const res = await call(new Request("https://relay.test/grafana", { method: "POST", headers: capture.headers, body: capture.body }));
    testEnv.WEBHOOK_SECRET = saved;
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ received: 1 });
  });

  it("accepts HTTP Basic with the secret as the password, for Grafanas too old to sign", async () => {
    const body = JSON.stringify(grafanaWebhook([{}]));
    const good = await call(new Request("https://relay.test/grafana", { method: "POST", headers: { authorization: `Basic ${btoa(`brazier:${SECRET}`)}` }, body }));
    expect(good.status).toBe(200);
    const bad = await call(new Request("https://relay.test/grafana", { method: "POST", headers: { authorization: `Basic ${btoa("brazier:wrong")}` }, body }));
    expect(bad.status).toBe(401);
    const empty = await call(new Request("https://relay.test/grafana", { method: "POST", headers: { authorization: "Basic " + btoa("brazier:") }, body }));
    expect(empty.status).toBe(401);
  });

  it("accepts a signature without a timestamp header (HMAC over the body alone)", async () => {
    const res = await signedWebhook(grafanaWebhook([{}]), { timestamp: null });
    expect(res.status).toBe(200);
  });

  it("answers 503 when the relay has no secret yet", async () => {
    const saved = testEnv.WEBHOOK_SECRET;
    testEnv.WEBHOOK_SECRET = undefined;
    const res = await signedWebhook(grafanaWebhook([{}]));
    testEnv.WEBHOOK_SECRET = saved;
    expect(res.status).toBe(503);
  });

  it("rejects a body that is not a Grafana webhook", async () => {
    const res = await signedWebhook({ hello: "world" });
    expect(res.status).toBe(400);
  });
});

describe("devices", () => {
  it("registers, lists and forgets a device for the Grafana user, lower-cased", async () => {
    const reg = await register(TOKEN_A, CJ);
    expect(reg.status).toBe(200);
    expect(await reg.json()).toMatchObject({ ok: true, user: "cjackson@guysinc.org", devices: 1 });

    // idempotent, and the same person through a session cookie or an OIDC token is the same user
    await register(TOKEN_A, { cookie: "grafana_session=sess-cj" });
    // an auth proxy's cookie travels with Grafana's, untouched
    expect((await register(TOKEN_A, { cookie: "CF_Authorization=proxy-jwt; grafana_session=sess-cj" })).status).toBe(200);
    await register(TOKEN_A, { jwt: "id-token-cj" });
    const list = (await (await call(new Request("https://relay.test/devices", { headers: credHeaders(CJ) }))).json()) as { devices: unknown[] };
    expect(list.devices).toHaveLength(1);

    const del = await call(new Request(`https://relay.test/devices/${TOKEN_A}`, { method: "DELETE", headers: credHeaders(CJ) }));
    expect(await del.json()).toMatchObject({ ok: true, removed: true });
    expect(await env.DEVICES.get("devices/cjackson@guysinc.org")).toBeNull();
  });

  it("files an email alias so ROUTES may name the person by either", async () => {
    await register(TOKEN_D, DM);
    expect(await env.DEVICES.get("alias/dmeade@damp.meme")).toBe("dmeade");
    expect(await env.DEVICES.get("devices/dmeade", "json")).toHaveLength(1);
  });

  it("rejects a credential Grafana does not know, and a call with no or two credentials", async () => {
    expect((await register(TOKEN_A, { bearer: "glsa_nope" })).status).toBe(401);
    expect((await register(TOKEN_A, { cookie: "grafana_session=stale" })).status).toBe(401);
    const none = await call(new Request("https://relay.test/devices", { method: "POST", headers: { "x-grafana-url": GRAFANA, "content-type": "application/json" }, body: "{}" }));
    expect(none.status).toBe(401);
    const two = await call(new Request("https://relay.test/devices", { method: "POST", headers: { ...credHeaders(CJ), cookie: "grafana_session=sess-cj", "content-type": "application/json" }, body: "{}" }));
    expect(two.status).toBe(401);
  });

  it("refuses a Grafana the relay does not serve, and a non-https one", async () => {
    const res = await register(TOKEN_A, CJ, {}, "https://stranger.test");
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ error: "this relay does not serve https://stranger.test" });
    expect((await register(TOKEN_A, CJ, {}, "http://grafana.test")).status).toBe(401);
    const missing = await call(new Request("https://relay.test/devices", { method: "POST", headers: { authorization: "Bearer glsa_cj", "content-type": "application/json" }, body: "{}" }));
    expect(missing.status).toBe(401);
  });

  it("answers 502 when that Grafana cannot be reached", async () => {
    outbound.length = 0; // no stub at all
    const res = await register(TOKEN_A, CJ);
    expect(res.status).toBe(502);
  });

  it("rejects a token that is not an APNs hex token", async () => {
    const res = await register("not-hex", CJ);
    expect(res.status).toBe(400);
  });
});

describe("delivery", () => {
  it("pushes a firing alert to the default owner with the right headers and payload, then dedupes the repeat", async () => {
    await register(TOKEN_A, CJ);
    const seen = apnsAnswers(200);

    const first = await signedWebhook(grafanaWebhook([{}]));
    expect(await first.json()).toMatchObject({ received: 1, pushed: 1, skipped: 0 });
    expect(seen).toHaveLength(1);
    expect(seen[0].path).toBe(`/3/device/${TOKEN_A}`);
    expect(seen[0].headers["apns-topic"]).toBe("org.guysinc.brazier");
    expect(seen[0].headers["apns-collapse-id"]).toBe("b69ade466fb0e990");
    expect(seen[0].headers["apns-push-type"]).toBe("alert");
    expect(seen[0].headers["authorization"]).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    const payload = JSON.parse(seen[0].body) as { aps: Record<string, unknown>; brazier: Record<string, unknown> };
    expect(payload.aps).toMatchObject({ alert: { title: "Disk above 85 percent", subtitle: "home · mitochondria", body: "mitochondria /mnt/Plex1 is over 85% full" }, category: "ALERT", "thread-id": "Estate", "interruption-level": "time-sensitive", sound: "default" });
    expect(payload.brazier).toMatchObject({ fingerprint: "b69ade466fb0e990", status: "firing", externalURL: "https://grafana.gicloud.org/", folder: "Estate" });

    const again = await signedWebhook(grafanaWebhook([{}]));
    expect(await again.json()).toMatchObject({ received: 1, pushed: 0, skipped: 1 });
    expect(seen).toHaveLength(1);
    expect(await env.DEVICES.get("sent/1:b69ade466fb0e990:firing:2026-09-28T23:53:50Z")).toBe("1");
  });

  it("dedupes per org: the same fingerprint in another org is a different alert", async () => {
    await register(TOKEN_A, CJ);
    const seen = apnsAnswers(200);
    await signedWebhook(grafanaWebhook([{}]));
    const other = grafanaWebhook([{ orgId: 2 } as never]);
    other.orgId = 2;
    const res = await signedWebhook(other);
    expect(await res.json()).toMatchObject({ pushed: 1, skipped: 0 });
    expect(seen).toHaveLength(2);
    expect(await env.DEVICES.get("sent/2:b69ade466fb0e990:firing:2026-09-28T23:53:50Z")).toBe("1");
  });

  it("pushes the resolved state under the same collapse id, without a sound, and a warn alert at the active level", async () => {
    await register(TOKEN_A, CJ);
    const seen = apnsAnswers(200);
    await signedWebhook(grafanaWebhook([{ status: "resolved", endsAt: "2026-09-29T00:10:00Z" }, { fingerprint: "c0ffee0000000001", labels: { alertname: "Disk full within 7 days", grafana_folder: "Estate", host: "ovh", severity: "warn" }, annotations: {} }]));
    expect(seen).toHaveLength(2); // resolved -> cjackson; warn on ovh -> cjackson + dmeade, and dmeade has no devices
    const resolved = JSON.parse(seen[0].body) as { aps: Record<string, unknown> };
    expect(seen[0].headers["apns-collapse-id"]).toBe("b69ade466fb0e990");
    expect((resolved.aps.alert as Record<string, string>).title).toBe("Resolved: Disk above 85 percent");
    expect(resolved.aps.sound).toBeUndefined();
    expect(resolved.aps["interruption-level"]).toBe("active");
  });

  it("routes by label: a meade-manor alert reaches Daniel's phone (named by email in ROUTES), not CJ's", async () => {
    await register(TOKEN_A, CJ);
    await register(TOKEN_D, DM);
    const seen = apnsAnswers(200);
    const res = await signedWebhook(grafanaWebhook([{ labels: { alertname: "Host stopped reporting", grafana_folder: "Meade Manor", host: "meade-monster", severity: "page", site: "meade-manor" } }]));
    expect(await res.json()).toMatchObject({ pushed: 1 });
    expect(seen.map((s) => s.path)).toEqual([`/3/device/${TOKEN_D}`]);
  });

  it("uses the sandbox host for a sandbox device", async () => {
    await register(TOKEN_B, CJ, { environment: "sandbox" });
    const seen = apnsAnswers(200, undefined, "https://api.sandbox.push.apple.com");
    await signedWebhook(grafanaWebhook([{}]));
    expect(seen).toHaveLength(1);
  });

  it("drops a device Apple says is gone (410) and keeps one that merely failed (500)", async () => {
    await register(TOKEN_A, CJ);
    let seen = apnsAnswers(500, "InternalServerError");
    let res = await signedWebhook(grafanaWebhook([{}]));
    expect(await res.json()).toMatchObject({ pushed: 0, failed: 1, dropped: 0 });
    expect(seen).toHaveLength(1);
    expect(await env.DEVICES.get("devices/cjackson@guysinc.org", "json")).toHaveLength(1);

    seen = apnsAnswers(410, "Unregistered");
    res = await signedWebhook(grafanaWebhook([{}]));
    expect(await res.json()).toMatchObject({ pushed: 0, dropped: 1 });
    expect(await env.DEVICES.get("devices/cjackson@guysinc.org")).toBeNull();
    // and nothing was recorded as sent, so a new device would still hear about it
    expect(await env.DEVICES.get("sent/1:b69ade466fb0e990:firing:2026-09-28T23:53:50Z")).toBeNull();
  });

  it("accepts the webhook but sends nothing while APNs is unconfigured", async () => {
    await register(TOKEN_A, CJ);
    const saved = testEnv.APNS_KEY;
    testEnv.APNS_KEY = undefined;
    const res = await signedWebhook(grafanaWebhook([{}]));
    testEnv.APNS_KEY = saved;
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ received: 1, pushed: 0, apns: false });
  });

  it("counts an alert nobody is routed to", async () => {
    testEnv.ROUTES = JSON.stringify({ "site=meade-manor": "dmeade" });
    const res = await signedWebhook(grafanaWebhook([{}]));
    testEnv.ROUTES = JSON.stringify({ "site=meade-manor": "dmeade@damp.meme", "host=~ovh|oc-.*": ["cjackson@guysinc.org", "dmeade"], "*": "CJackson@guysinc.org" });
    expect(await res.json()).toMatchObject({ unrouted: 1, pushed: 0 });
  });
});

describe("lock-screen text", () => {
  const base = { fingerprint: "f56ec99056388acd", startsAt: "2026-09-29T13:58:30Z", endsAt: "0001-01-01T00:00:00Z" };
  const datasourceError = {
    ...base,
    status: "firing" as const,
    labels: { alertname: "DatasourceError", rulename: "Out-of-memory kill", datasource_uid: "prometheus", ref_id: "A", severity: "warn", grafana_folder: "Estate" },
    annotations: { summary: "The kernel on [no value] killed a process for memory in the last 10 minutes", Error: 'Post "http://127.0.0.1:58696/api/v1/query": dial tcp 127.0.0.1:58696: connect: connection refused' },
  };

  it("names the rule and the datasource when Grafana raises DatasourceError, never the [no value] summary", () => {
    const p = buildPayload(datasourceError as never, undefined) as { aps: { alert: { title: string; subtitle?: string; body: string }; "interruption-level": string }; brazier: { alertname: string; rulename?: string } };
    expect(p.aps.alert.title).toBe("Out-of-memory kill · query failed");
    expect(p.aps.alert.subtitle).toBe("prometheus");
    expect(p.aps.alert.body).toMatch(/^Grafana could not query prometheus: Post /);
    expect(p.aps.alert.body).not.toContain("[no value]");
    expect(p.aps["interruption-level"]).toBe("active");
    expect(p.brazier.alertname).toBe("DatasourceError");
    expect(p.brazier.rulename).toBe("Out-of-memory kill");
    const r = buildPayload({ ...datasourceError, status: "resolved" } as never, undefined) as { aps: { alert: { title: string } } };
    expect(r.aps.alert.title).toBe("Resolved: Out-of-memory kill · query failed");
  });

  it("says no data for DatasourceNoData", () => {
    const a = { ...base, status: "firing" as const, labels: { alertname: "DatasourceNoData", rulename: "Exporter not scraping", datasource_uid: "prometheus" }, annotations: {} };
    const p = buildPayload(a as never, undefined) as { aps: { alert: { title: string; body: string } } };
    expect(p.aps.alert.title).toBe("Exporter not scraping · no data");
    expect(p.aps.alert.body).toBe("The query on prometheus returned nothing.");
  });

  it("keeps a real alert's summary, site and host", () => {
    const a = { ...base, status: "firing" as const, labels: { alertname: "Disk almost full", site: "house", host: "mitochondria", severity: "page" }, annotations: { summary: "/ has 4% left" } };
    const p = buildPayload(a as never, undefined) as { aps: { alert: { title: string; subtitle?: string; body: string }; "interruption-level": string } };
    expect(p.aps.alert.title).toBe("Disk almost full");
    expect(p.aps.alert.subtitle).toBe("house · mitochondria");
    expect(p.aps.alert.body).toBe("/ has 4% left");
    expect(p.aps["interruption-level"]).toBe("time-sensitive");
  });
});

describe("organizations", () => {
  const alert = { fingerprint: "abc", startsAt: "2026-09-29T10:00:00Z", status: "firing" as const, labels: { alertname: "Disk almost full", site: "house", host: "mitochondria", severity: "page" }, annotations: { summary: "/ has 4% left" } };

  it("keys the dedupe record by org, fingerprint, state and start", () => {
    expect(sentKey(alert as never, 4)).toBe("sent/4:abc:firing:2026-09-29T10:00:00Z");
    expect(sentKey({ ...alert, startsAt: undefined } as never, 0)).toBe("sent/0:abc:firing:");
  });

  it("puts the org name first on the lock screen and the id and name in the payload", () => {
    const p = buildPayload(alert as never, "https://grafana.test/", 4, "Meade Manor") as { aps: { alert: { subtitle?: string } }; brazier: { orgId?: number; org?: string } };
    expect(p.aps.alert.subtitle).toBe("Meade Manor · house · mitochondria");
    expect(p.brazier).toMatchObject({ orgId: 4, org: "Meade Manor" });
    const bare = buildPayload(alert as never, undefined, 4) as { aps: { alert: { subtitle?: string } }; brazier: { orgId?: number; org?: string } };
    expect(bare.aps.alert.subtitle).toBe("house · mitochondria");
    expect(bare.brazier.orgId).toBe(4);
    expect(bare.brazier.org).toBeUndefined();
    const synthetic = buildPayload({ ...alert, labels: { alertname: "DatasourceNoData", rulename: "Exporter", datasource_uid: "prometheus" } } as never, undefined, 1, "Infrastructure") as { aps: { alert: { title: string; subtitle?: string } } };
    expect(synthetic.aps.alert.title).toBe("Exporter · no data");
    expect(synthetic.aps.alert.subtitle).toBe("Infrastructure · prometheus");
  });

  it("names the org from ORGS on a real push, and ignores a broken ORGS", async () => {
    await register(TOKEN_A, CJ);
    const seen = apnsAnswers(200);
    testEnv.ORGS = JSON.stringify({ "1": "Infrastructure", "2": "Guys Inc Public" });
    await signedWebhook(grafanaWebhook([{}]));
    testEnv.ORGS = "{not json";
    await signedWebhook(grafanaWebhook([{ fingerprint: "c0ffee0000000002" }]));
    testEnv.ORGS = undefined;
    expect(seen).toHaveLength(2);
    const named = JSON.parse(seen[0].body) as { aps: { alert: { subtitle: string } }; brazier: { orgId: number; org: string } };
    expect(named.aps.alert.subtitle).toBe("Infrastructure · home · mitochondria");
    expect(named.brazier).toMatchObject({ orgId: 1, org: "Infrastructure" });
    const unnamed = JSON.parse(seen[1].body) as { aps: { alert: { subtitle: string } }; brazier: { orgId: number; org?: string } };
    expect(unnamed.aps.alert.subtitle).toBe("home · mitochondria");
    expect(unnamed.brazier.orgId).toBe(1);
    expect(unnamed.brazier.org).toBeUndefined();
  });
});

describe("severity", () => {
  it("ranks the usual words and treats anything else as warning", () => {
    expect(level("page")).toBe("page");
    expect(level("Emergency")).toBe("page");
    expect(level("critical")).toBe("critical");
    expect(level("CRIT")).toBe("critical");
    expect(level("high")).toBe("critical");
    expect(level("error")).toBe("critical");
    expect(level("warn")).toBe("warning");
    expect(level("medium")).toBe("warning");
    expect(level("info")).toBe("info");
    expect(level("notice")).toBe("info");
    expect(level("low")).toBe("info");
    expect(level("purple")).toBe("warning");
    expect(level(undefined)).toBe("warning");
    expect(level("")).toBe("warning");
  });

  it("applies a floor; no floor lets everything through", () => {
    expect(meets("info", undefined)).toBe(true);
    expect(meets("info", "warning")).toBe(false);
    expect(meets("warn", "warning")).toBe(true);
    expect(meets(undefined, "critical")).toBe(false);
    expect(meets("page", "critical")).toBe(true);
    expect(meets("critical", "page")).toBe(false);
  });
});

describe("quiet hours", () => {
  const at = (iso: string) => new Date(iso);

  it("reads the local clock in the device's zone", () => {
    expect(localMinutes("UTC", at("2026-09-29T23:30:00Z"))).toBe(23 * 60 + 30);
    expect(localMinutes("America/Chicago", at("2026-09-29T23:30:00Z"))).toBe(18 * 60 + 30); // CDT, UTC-5
    expect(localMinutes("Europe/Paris", at("2026-09-29T23:30:00Z"))).toBe(1 * 60 + 30); // CEST, next day
    expect(localMinutes("Mars/Olympus", at("2026-09-29T23:30:00Z"))).toBeNull();
  });

  it("knows a window that crosses midnight", () => {
    const quiet = { start: "22:00", end: "07:00", tz: "UTC" };
    expect(inQuietHours(quiet, at("2026-09-29T21:59:00Z"))).toBe(false);
    expect(inQuietHours(quiet, at("2026-09-29T22:00:00Z"))).toBe(true);
    expect(inQuietHours(quiet, at("2026-09-30T03:00:00Z"))).toBe(true);
    expect(inQuietHours(quiet, at("2026-09-30T06:59:00Z"))).toBe(true);
    expect(inQuietHours(quiet, at("2026-09-30T07:00:00Z"))).toBe(false);
    expect(inQuietHours(quiet, at("2026-09-30T12:00:00Z"))).toBe(false);
  });

  it("knows a window inside one day, in the device's zone", () => {
    const quiet = { start: "13:00", end: "14:00", tz: "America/Chicago" };
    expect(inQuietHours(quiet, at("2026-09-29T18:30:00Z"))).toBe(true); // 13:30 CDT
    expect(inQuietHours(quiet, at("2026-09-29T19:00:00Z"))).toBe(false); // 14:00 CDT
    expect(inQuietHours(quiet, at("2026-09-29T13:30:00Z"))).toBe(false); // 08:30 CDT
  });

  it("is never quiet with an unknown zone, a bad time or no window", () => {
    expect(inQuietHours({ start: "00:00", end: "23:59", tz: "Mars/Olympus" }, at("2026-09-29T12:00:00Z"))).toBe(false);
    expect(inQuietHours({ start: "25:00", end: "07:00", tz: "UTC" }, at("2026-09-29T03:00:00Z"))).toBe(false);
    expect(inQuietHours({ start: "07:00", end: "07:00", tz: "UTC" }, at("2026-09-29T07:00:00Z"))).toBe(false);
    expect(inQuietHours(null, at("2026-09-29T07:00:00Z"))).toBe(false);
    expect(inQuietHours(undefined, at("2026-09-29T07:00:00Z"))).toBe(false);
  });
});

/** A quiet window around the present moment in UTC, so the delivery tests hold at any hour. */
function quietNow(): { start: string; end: string; tz: string } {
  const cur = localMinutes("UTC", new Date()) as number;
  const hhmm = (m: number) => `${String(Math.floor(((m % 1440) + 1440) % 1440 / 60)).padStart(2, "0")}:${String(((m % 1440) + 1440) % 1440 % 60).padStart(2, "0")}`;
  return { start: hhmm(cur - 60), end: hhmm(cur + 60), tz: "UTC" };
}

describe("preferences", () => {
  const prefsOf = async (cred: Cred = CJ) => {
    const list = (await (await call(new Request("https://relay.test/devices", { headers: credHeaders(cred) }))).json()) as { devices: Array<{ prefs: unknown }> };
    return list.devices.map((d) => d.prefs);
  };
  const put = (token: string, body: unknown, cred: Cred = CJ) =>
    call(new Request(`https://relay.test/devices/${token}/preferences`, { method: "PUT", headers: { ...credHeaders(cred), "content-type": "application/json" }, body: typeof body === "string" ? body : JSON.stringify(body) }));

  it("checks each field", () => {
    expect(readPrefs({})).toEqual({});
    expect(readPrefs({ orgs: [1, 4, 1], minSeverity: "critical", quiet: { start: "22:00", end: "07:00", tz: "America/Chicago", allowPage: true } })).toEqual({ orgs: [1, 4], minSeverity: "critical", quiet: { start: "22:00", end: "07:00", tz: "America/Chicago", allowPage: true } });
    expect(readPrefs({ orgs: null, quiet: null })).toEqual({ orgs: null, quiet: null });
    for (const bad of [null, [], "x", { orgs: [0] }, { orgs: ["1"] }, { orgs: 1 }, { minSeverity: "loud" }, { minSeverity: 3 }, { quiet: [] }, { quiet: { start: "22:00", tz: "UTC" } }, { quiet: { start: "22:00", end: "7:00", tz: "UTC" } }, { quiet: { start: "25:00", end: "07:00", tz: "UTC" } }, { quiet: { start: "22:00", end: "07:00", tz: "" } }, { quiet: { start: "22:00", end: "07:00", tz: "x".repeat(65) } }, { quiet: { start: "22:00", end: "07:00", tz: "UTC", allowPage: "yes" } }, { colour: "hot" }]) {
      expect(() => readPrefs(bad), JSON.stringify(bad)).toThrow();
    }
  });

  it("takes prefs on registration, keeps them across a re-registration, and replaces them on PUT", async () => {
    const reg = await register(TOKEN_A, CJ, { prefs: { orgs: [1], minSeverity: "warning" } });
    expect(reg.status).toBe(200);
    expect(await prefsOf()).toEqual([{ orgs: [1], minSeverity: "warning" }]);
    // the app re-registers on every launch, without prefs: nothing is lost
    await register(TOKEN_A, { jwt: "id-token-cj" });
    expect(await prefsOf()).toEqual([{ orgs: [1], minSeverity: "warning" }]);
    const res = await put(TOKEN_A, { quiet: { start: "22:00", end: "07:00", tz: "America/Chicago" } });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, prefs: { quiet: { start: "22:00", end: "07:00", tz: "America/Chicago" } } });
    expect(await prefsOf()).toEqual([{ quiet: { start: "22:00", end: "07:00", tz: "America/Chicago" } }]);
    // and a device registered without any shows an empty object
    await register(TOKEN_B, CJ);
    expect((await prefsOf()).sort((a, b) => JSON.stringify(a).length - JSON.stringify(b).length)).toEqual([{}, { quiet: { start: "22:00", end: "07:00", tz: "America/Chicago" } }]);
  });

  it("answers 400 for bad prefs, on registration and on PUT", async () => {
    expect((await register(TOKEN_A, CJ, { prefs: { minSeverity: "loud" } })).status).toBe(400);
    expect((await register(TOKEN_A, CJ, { prefs: "all" })).status).toBe(400);
    await register(TOKEN_A, CJ);
    expect((await put(TOKEN_A, { orgs: [0] })).status).toBe(400);
    expect((await put(TOKEN_A, { quiet: { start: "22:00", end: "07:00" } })).status).toBe(400);
    expect((await put(TOKEN_A, "{not json")).status).toBe(400);
    expect((await put(TOKEN_A, { colour: "hot" })).status).toBe(400);
    expect((await put("not-hex", {})).status).toBe(400);
  });

  it("answers 404 for a token not filed under the caller, and 401 without a credential", async () => {
    await register(TOKEN_A, CJ);
    expect((await put(TOKEN_B, {})).status).toBe(404);
    expect((await put(TOKEN_A, {}, DM)).status).toBe(404);
    expect((await put(TOKEN_A, {}, { bearer: "glsa_nope" })).status).toBe(401);
    expect(await prefsOf()).toEqual([{}]);
  });

  it("drops alerts below the device's severity floor, and the resolved push with them", async () => {
    await register(TOKEN_A, CJ, { prefs: { minSeverity: "critical" } });
    const seen = apnsAnswers(200);
    const warn = { fingerprint: "c0ffee0000000001", labels: { alertname: "Disk full within 7 days", grafana_folder: "Estate", host: "mitochondria", severity: "warn" }, annotations: {} };
    let res = await signedWebhook(grafanaWebhook([warn]));
    expect(await res.json()).toMatchObject({ pushed: 0, filtered: 1, unrouted: 0 });
    expect(seen).toHaveLength(0);
    res = await signedWebhook(grafanaWebhook([{ ...warn, status: "resolved", endsAt: "2026-09-29T00:10:00Z" }]));
    expect(await res.json()).toMatchObject({ pushed: 0, filtered: 1 });
    expect(seen).toHaveLength(0);
    // a page still comes through, and one with no severity label counts as warning
    await signedWebhook(grafanaWebhook([{}, { fingerprint: "c0ffee0000000003", labels: { alertname: "Unlabelled", grafana_folder: "Estate" } }]));
    expect(seen.map((s) => (JSON.parse(s.body) as { aps: { alert: { title: string } } }).aps.alert.title)).toEqual(["Disk above 85 percent"]);
  });

  it("drops alerts from orgs the device did not ask for; an empty list means every org", async () => {
    await register(TOKEN_A, CJ, { prefs: { orgs: [2, 3] } });
    await register(TOKEN_B, CJ, { prefs: { orgs: [] } });
    const seen = apnsAnswers(200);
    const res = await signedWebhook(grafanaWebhook([{}])); // org 1
    expect(await res.json()).toMatchObject({ pushed: 1, filtered: 1 });
    expect(seen.map((s) => s.path)).toEqual([`/3/device/${TOKEN_B}`]);
    const org3 = grafanaWebhook([{ fingerprint: "c0ffee0000000004", orgId: 3 } as never]);
    org3.orgId = 3;
    expect(await (await signedWebhook(org3)).json()).toMatchObject({ pushed: 2, filtered: 0 });
  });

  it("delivers silently inside quiet hours, except a page unless the device said otherwise", async () => {
    await register(TOKEN_A, CJ, { prefs: { quiet: quietNow() } });
    await register(TOKEN_B, CJ, { prefs: { quiet: { ...quietNow(), allowPage: false } } });
    const seen = apnsAnswers(200);
    const warn = { fingerprint: "c0ffee0000000005", labels: { alertname: "Disk full within 7 days", grafana_folder: "Estate", host: "mitochondria", severity: "warn" }, annotations: {} };
    const res = await signedWebhook(grafanaWebhook([warn, { fingerprint: "b69ade466fb0e990" }]));
    expect(await res.json()).toMatchObject({ pushed: 4, quiet: 3 });
    const byPath = (fp: string, token: string) => seen.filter((s) => s.path === `/3/device/${token}` && s.headers["apns-collapse-id"] === fp).map((s) => JSON.parse(s.body) as { aps: Record<string, unknown> })[0];
    const warnA = byPath("c0ffee0000000005", TOKEN_A);
    expect(warnA.aps.sound).toBeUndefined();
    expect(warnA.aps["interruption-level"]).toBe("passive");
    const pageA = byPath("b69ade466fb0e990", TOKEN_A);
    expect(pageA.aps.sound).toBe("default");
    expect(pageA.aps["interruption-level"]).toBe("time-sensitive");
    const pageB = byPath("b69ade466fb0e990", TOKEN_B);
    expect(pageB.aps.sound).toBeUndefined();
    expect(pageB.aps["interruption-level"]).toBe("passive");
    // the loud copy is untouched: the payload was cloned, not edited
    expect((pageA.aps.alert as Record<string, string>).title).toBe("Disk above 85 percent");
  });

  it("is loud outside quiet hours and with a zone it cannot read", async () => {
    const cur = localMinutes("UTC", new Date()) as number;
    const far = (m: number) => `${String(Math.floor((((m % 1440) + 1440) % 1440) / 60)).padStart(2, "0")}:${String((((m % 1440) + 1440) % 1440) % 60).padStart(2, "0")}`;
    await register(TOKEN_A, CJ, { prefs: { quiet: { start: far(cur + 120), end: far(cur + 180), tz: "UTC" } } });
    await register(TOKEN_B, CJ, { prefs: { quiet: { start: "00:00", end: "23:59", tz: "Mars/Olympus" } } });
    const seen = apnsAnswers(200);
    const res = await signedWebhook(grafanaWebhook([{}]));
    expect(await res.json()).toMatchObject({ pushed: 2, quiet: 0 });
    for (const s of seen) expect((JSON.parse(s.body) as { aps: Record<string, unknown> }).aps.sound).toBe("default");
  });
});
