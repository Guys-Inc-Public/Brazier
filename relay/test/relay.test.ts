import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/env";
import { signLikeGrafana } from "../src/hmac";
import { makeIssuer, makeApnsKeyPem, grafanaWebhook, type Issuer } from "./helpers";

const SECRET = "test-webhook-secret";
const JWKS_URL = "https://keystone.test/application/o/brazier/jwks/";
const ISSUER = "https://keystone.test/application/o/brazier/";
const AUD = "test-client-id";
const TOKEN_A = "a".repeat(64);
const TOKEN_B = "b".repeat(64);
const TOKEN_D = "d".repeat(64);

let issuer: Issuer;
let testEnv: Env;

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

async function idToken(overrides: Record<string, unknown> = {}, kid?: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return issuer.sign({ iss: ISSUER, aud: AUD, sub: "hash-of-cj", preferred_username: "CJackson", email: "CJackson@guysinc.org", iat: now, exp: now + 3600, ...overrides }, kid);
}

async function register(token: string, jwt: string, extra: Record<string, unknown> = {}) {
  return call(
    new Request("https://relay.test/devices", {
      method: "POST",
      headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json" },
      body: JSON.stringify({ token, platform: "ios", environment: "production", name: "CJ's iPhone", ...extra }),
    }),
  );
}

/** Outbound fetches are stubbed per origin; anything unexpected throws. */
type Handler = (req: Request) => Promise<Response> | Response;
const outbound: Array<{ origin: string; handler: Handler }> = [];
const realFetch = globalThis.fetch;

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
  issuer = await makeIssuer();
  testEnv = {
    ...env,
    JWKS_URL,
    JWT_ISSUER: ISSUER,
    JWT_AUDIENCE: AUD,
    ROUTES: JSON.stringify({ "site=meade-manor": "DMeade", "host=~ovh|oc-.*": ["cjackson", "dmeade"], "*": "cjackson" }),
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
  outbound.push({ origin: "https://keystone.test", handler: () => Response.json(issuer.jwks) });
  // a clean registry per test
  const list = await env.DEVICES.list();
  await Promise.all(list.keys.map((k) => env.DEVICES.delete(k.name)));
});

describe("health", () => {
  it("answers with version and configuration state", async () => {
    const res = await call(new Request("https://relay.test/health"));
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(body).toMatchObject({ ok: true, kv: "ok", apns: true, webhook: true });
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
  it("registers, lists and forgets a device for the token's user, lower-cased", async () => {
    const jwt = await idToken();
    const reg = await register(TOKEN_A, jwt);
    expect(reg.status).toBe(200);
    expect(await reg.json()).toMatchObject({ ok: true, user: "cjackson", devices: 1 });

    // idempotent
    await register(TOKEN_A, jwt);
    const list = (await (await call(new Request("https://relay.test/devices", { headers: { authorization: `Bearer ${jwt}` } }))).json()) as { devices: unknown[] };
    expect(list.devices).toHaveLength(1);

    const del = await call(new Request(`https://relay.test/devices/${TOKEN_A}`, { method: "DELETE", headers: { authorization: `Bearer ${jwt}` } }));
    expect(await del.json()).toMatchObject({ ok: true, removed: true });
    expect(await env.DEVICES.get("devices/cjackson")).toBeNull();
  });

  it("rejects a token from another issuer, an expired one, a wrong audience, an unknown key and a bad signature", async () => {
    const cases = [
      await idToken({ iss: "https://elsewhere.test/" }),
      await idToken({ exp: Math.floor(Date.now() / 1000) - 120 }),
      await idToken({ aud: "someone-else" }),
      await idToken({}, "unknown-kid"),
      (await idToken()).slice(0, -8) + "AAAAAAAA",
    ];
    for (const jwt of cases) {
      const res = await register(TOKEN_A, jwt);
      expect(res.status, jwt).toBe(401);
    }
    expect(await register(TOKEN_A, "")).toHaveProperty("status", 401);
  });

  it("rejects a token that is not an APNs hex token", async () => {
    const res = await register("not-hex", await idToken());
    expect(res.status).toBe(400);
  });
});

describe("delivery", () => {
  it("pushes a firing alert to the default owner with the right headers and payload, then dedupes the repeat", async () => {
    await register(TOKEN_A, await idToken());
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
    await register(TOKEN_A, await idToken());
    const seen = apnsAnswers(200);
    await signedWebhook(grafanaWebhook([{ status: "resolved", endsAt: "2026-09-29T00:10:00Z" }, { fingerprint: "c0ffee0000000001", labels: { alertname: "Disk full within 7 days", grafana_folder: "Estate", host: "ovh", severity: "warn" }, annotations: {} }]));
    expect(seen).toHaveLength(2); // resolved -> cjackson; warn on ovh -> cjackson + dmeade, and dmeade has no devices
    const resolved = JSON.parse(seen[0].body) as { aps: Record<string, unknown> };
    expect(seen[0].headers["apns-collapse-id"]).toBe("b69ade466fb0e990");
    expect((resolved.aps.alert as Record<string, string>).title).toBe("Resolved: Disk above 85 percent");
    expect(resolved.aps.sound).toBeUndefined();
    expect(resolved.aps["interruption-level"]).toBe("active");
  });

  it("routes by label: a meade-manor alert reaches dmeade's phone, not cjackson's", async () => {
    await register(TOKEN_A, await idToken());
    await register(TOKEN_D, await idToken({ preferred_username: "DMeade", sub: "hash-of-dm" }));
    const seen = apnsAnswers(200);
    const res = await signedWebhook(grafanaWebhook([{ labels: { alertname: "Host stopped reporting", grafana_folder: "Meade Manor", host: "meade-monster", severity: "page", site: "meade-manor" } }]));
    expect(await res.json()).toMatchObject({ pushed: 1 });
    expect(seen.map((s) => s.path)).toEqual([`/3/device/${TOKEN_D}`]);
  });

  it("uses the sandbox host for a sandbox device", async () => {
    await register(TOKEN_B, await idToken(), { environment: "sandbox" });
    const seen = apnsAnswers(200, undefined, "https://api.sandbox.push.apple.com");
    await signedWebhook(grafanaWebhook([{}]));
    expect(seen).toHaveLength(1);
  });

  it("drops a device Apple says is gone (410) and keeps one that merely failed (500)", async () => {
    await register(TOKEN_A, await idToken());
    let seen = apnsAnswers(500, "InternalServerError");
    let res = await signedWebhook(grafanaWebhook([{}]));
    expect(await res.json()).toMatchObject({ pushed: 0, failed: 1, dropped: 0 });
    expect(seen).toHaveLength(1);
    expect(await env.DEVICES.get("devices/cjackson", "json")).toHaveLength(1);

    seen = apnsAnswers(410, "Unregistered");
    res = await signedWebhook(grafanaWebhook([{}]));
    expect(await res.json()).toMatchObject({ pushed: 0, dropped: 1 });
    expect(await env.DEVICES.get("devices/cjackson")).toBeNull();
    // and nothing was recorded as sent, so a new device would still hear about it
    expect(await env.DEVICES.get("sent/b69ade466fb0e990:firing:2026-09-28T23:53:50Z")).toBeNull();
  });

  it("accepts the webhook but sends nothing while APNs is unconfigured", async () => {
    await register(TOKEN_A, await idToken());
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
    testEnv.ROUTES = JSON.stringify({ "site=meade-manor": "DMeade", "host=~ovh|oc-.*": ["cjackson", "dmeade"], "*": "cjackson" });
    expect(await res.json()).toMatchObject({ unrouted: 1, pushed: 0 });
  });
});
