import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
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
  "cookie:sess-cj": { login: "cjackson@guysinc.org", email: "cjackson@guysinc.org", name: "Cameron Jackson" },
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
      const key = auth ? `bearer:${auth.replace(/^Bearer /, "")}` : cookie ? `cookie:${cookie.replace(/^grafana_session=/, "")}` : jwt ? `jwt:${jwt}` : "";
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
  else if ("cookie" in cred) h.cookie = `grafana_session=${cred.cookie}`;
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
    expect(body).toMatchObject({ ok: true, kv: "ok", apns: true, webhook: true, grafana: [GRAFANA, "https://other.test"] });
    expect(typeof body.version).toBe("string");
  });

  it("reports apns unconfigured when the key is missing", async () => {
    const saved = testEnv.APNS_KEY;
    testEnv.APNS_KEY = undefined;
    const body = (await (await call(new Request("https://relay.test/health"))).json()) as Record<string, unknown>;
    testEnv.APNS_KEY = saved;
    expect(body.apns).toBe(false);
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
    await register(TOKEN_A, { cookie: "sess-cj" });
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
    expect((await register(TOKEN_A, { cookie: "stale" })).status).toBe(401);
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
    expect(await env.DEVICES.get("sent/b69ade466fb0e990:firing:2026-09-28T23:53:50Z")).toBeNull();
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
