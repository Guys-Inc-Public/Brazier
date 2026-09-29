import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/env";
import { relayOrigin } from "../src/relays";

let testEnv: Env;
let publicKey: CryptoKey;

type Handler = (req: Request) => Promise<Response> | Response;
const outbound: Array<{ origin: string; handler: Handler }> = [];
const realFetch = globalThis.fetch;

function fromB64url(s: string): Uint8Array {
  return Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
}

/** A relay at that origin whose discovery document says what a Brazier relay says. */
function stubRelay(origin: string, body: unknown = { relay: { url: origin, version: "0.5.0" }, grafana: {} }, status = 200) {
  outbound.push({ origin, handler: () => (status === 200 ? Response.json(body) : new Response("no", { status })) });
}

async function call(req: Request): Promise<Response> {
  const ctx = createExecutionContext();
  const res = await worker.fetch(req, testEnv, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

const register = (relay: unknown) =>
  call(new Request("https://grant.test/relays", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ relay }) }));
const grant = (key: string) => call(new Request("https://grant.test/grant", { method: "POST", headers: { authorization: `Bearer ${key}` } }));

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  publicKey = pair.publicKey;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let s = "";
  for (const b of der) s += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(s).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----\n`;
  testEnv = { ...env, APNS_KEY: pem, APNS_KEY_ID: "TESTKEYID", APNS_TEAM_ID: "7VM43528YK", APNS_TOPIC: "org.guysinc.brazier" };
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
  const list = await env.RELAYS.list();
  await Promise.all(list.keys.map((k) => env.RELAYS.delete(k.name)));
});

describe("health", () => {
  it("answers with the version, the key state and the relay count", async () => {
    const res = await call(new Request("https://grant.test/health"));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, apns: true, relays: 0, version: expect.any(String) });
    const saved = testEnv.APNS_KEY;
    testEnv.APNS_KEY = undefined;
    expect(((await (await call(new Request("https://grant.test/health"))).json()) as { apns: boolean }).apns).toBe(false);
    testEnv.APNS_KEY = saved;
  });

  it("names itself at the root", async () => {
    const res = await call(new Request("https://grant.test/"));
    expect(await res.text()).toMatch(/^brazier-grant \d/);
  });
});

describe("relay addresses", () => {
  it("takes a public https origin and nothing else", () => {
    expect(relayOrigin("https://relay.example.com/anything?x=1")).toEqual({ origin: "https://relay.example.com" });
    expect(relayOrigin("https://relay.example.com:8443")).toEqual({ origin: "https://relay.example.com:8443" });
    for (const bad of ["http://relay.example.com", "https://localhost", "https://127.0.0.1", "https://10.1.2.3", "https://192.168.1.5", "https://172.16.0.1", "https://relay.local", "https://relay", "https://user:pw@relay.example.com", "not a url", "", 42, null]) {
      expect(relayOrigin(bad)).toHaveProperty("error");
    }
  });
});

describe("POST /relays", () => {
  it("registers a relay that answers like one and hands back its key once", async () => {
    stubRelay("https://relay.example.com");
    const res = await register("https://relay.example.com/");
    expect(res.status).toBe(201);
    const body = (await res.json()) as { ok: boolean; relayKey: string; topic: string; relay: string };
    expect(body.ok).toBe(true);
    expect(body.relayKey).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(body.topic).toBe("org.guysinc.brazier");
    expect(body.relay).toBe("https://relay.example.com");
    // only the hash is filed
    const keys = (await env.RELAYS.list()).keys.map((k) => k.name);
    expect(keys).toHaveLength(2);
    expect(keys.join()).not.toContain(body.relayKey);
    expect(keys.find((k) => k.startsWith("relays/"))).toMatch(/^relays\/[0-9a-f]{64}$/);
    const health = (await (await call(new Request("https://grant.test/health"))).json()) as { relays: number };
    expect(health.relays).toBe(1);
  });

  it("refuses a relay that does not answer like one, an http one and a loopback one", async () => {
    stubRelay("https://notarelay.example.com", { hello: "world" });
    expect((await register("https://notarelay.example.com")).status).toBe(422);
    stubRelay("https://down.example.com", undefined, 404);
    expect((await register("https://down.example.com")).status).toBe(422);
    expect((await register("http://relay.example.com")).status).toBe(400);
    expect((await register("https://127.0.0.1")).status).toBe(400);
    expect((await register(undefined)).status).toBe(400);
    expect((await call(new Request("https://grant.test/relays", { method: "POST", body: "nope" }))).status).toBe(400);
    expect((await env.RELAYS.list()).keys).toHaveLength(0);
  });

  it("answers 409 for a relay already registered", async () => {
    stubRelay("https://relay.example.com");
    expect((await register("https://relay.example.com")).status).toBe(201);
    const again = await register("https://relay.example.com/other");
    expect(again.status).toBe(409);
    expect(((await again.json()) as { error: string }).error).toMatch(/already registered/);
  });
});

describe("POST /grant", () => {
  async function registered(): Promise<string> {
    stubRelay("https://relay.example.com");
    return ((await (await register("https://relay.example.com")).json()) as { relayKey: string }).relayKey;
  }

  it("refuses an unknown or missing key", async () => {
    expect((await grant("a".repeat(43))).status).toBe(401);
    expect((await grant("short")).status).toBe(401);
    expect((await call(new Request("https://grant.test/grant", { method: "POST" }))).status).toBe(401);
  });

  it("signs a provider token Apple would accept, good for 50 minutes", async () => {
    const key = await registered();
    const before = Math.floor(Date.now() / 1000);
    const res = await grant(key);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { token: string; keyId: string; teamId: string; topic: string; issuedAt: number; expiresAt: number };
    expect(body).toMatchObject({ keyId: "TESTKEYID", teamId: "7VM43528YK", topic: "org.guysinc.brazier" });
    expect(body.issuedAt).toBeGreaterThanOrEqual(before);
    expect(body.expiresAt - body.issuedAt).toBe(3000);
    const [h, c, s] = body.token.split(".");
    expect(JSON.parse(new TextDecoder().decode(fromB64url(h)))).toEqual({ alg: "ES256", kid: "TESTKEYID" });
    expect(JSON.parse(new TextDecoder().decode(fromB64url(c)))).toEqual({ iss: "7VM43528YK", iat: body.issuedAt });
    const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, fromB64url(s), new TextEncoder().encode(`${h}.${c}`));
    expect(valid).toBe(true);
    const record = (await env.RELAYS.list()).keys.find((k) => k.name.startsWith("relays/"))!;
    expect(await env.RELAYS.get(record.name, "json")).toMatchObject({ url: "https://relay.example.com", grants: 1, last: body.issuedAt });
  });

  it("allows one grant a minute per key", async () => {
    const key = await registered();
    expect((await grant(key)).status).toBe(200);
    const again = await grant(key);
    expect(again.status).toBe(429);
    expect(Number(again.headers.get("retry-after"))).toBeGreaterThan(0);
  });

  it("answers 503 without the key loaded", async () => {
    const key = await registered();
    const saved = testEnv.APNS_KEY;
    testEnv.APNS_KEY = undefined;
    const res = await grant(key);
    testEnv.APNS_KEY = saved;
    expect(res.status).toBe(503);
  });
});

it("answers 404 elsewhere", async () => {
  expect((await call(new Request("https://grant.test/nope"))).status).toBe(404);
});

