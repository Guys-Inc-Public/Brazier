import { describe, it, expect, beforeEach, afterEach } from "vitest";
import worker from "../src/index";

const env = { ORIGIN: "http://198.51.100.7:3011", RELAY_URL: "https://relay.example", DEMO_KEY: "k-secret" };
type Call = { url: string; init?: RequestInit };
let calls: Call[];
let answer: (url: string, init?: RequestInit) => Response | Promise<Response>;
const realFetch = globalThis.fetch;

beforeEach(() => {
  calls = [];
  answer = () => new Response("{}", { status: 200 });
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    calls.push({ url, init });
    return answer(url, init);
  }) as typeof fetch;
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

const req = (path: string, init?: RequestInit) => new Request(`https://demo.brazier.gicloud.org${path}`, init);

describe("the front door", () => {
  it("passes the relay's discovery document through", async () => {
    answer = () => new Response(JSON.stringify({ relay: { url: "https://relay.example", version: "0.5.0" }, grafana: {} }), { headers: { "content-type": "application/json" } });
    const res = await worker.fetch(req("/.well-known/brazier"), env);
    expect(res.status).toBe(200);
    expect(calls[0].url).toBe("https://relay.example/.well-known/brazier");
    expect(new Headers(calls[0].init?.headers).get("user-agent")).toBe("brazier-demo");
    expect(((await res.json()) as { relay: { version: string } }).relay.version).toBe("0.5.0");
    expect(res.headers.get("cache-control")).toContain("max-age");
  });

  it("forwards everything else to the origin with the demo key and forwarded headers", async () => {
    answer = () => new Response("ok", { status: 201, headers: { "set-cookie": "grafana_session=abc; Path=/; Secure", "content-type": "application/json" } });
    const res = await worker.fetch(req("/login?x=1", { method: "POST", body: '{"user":"reviewer"}', headers: { "content-type": "application/json", cookie: "a=b" } }), env);
    expect(res.status).toBe(201);
    expect(calls[0].url).toBe("http://198.51.100.7:3011/login?x=1");
    const h = new Headers(calls[0].init?.headers);
    expect(h.get("x-demo-key")).toBe("k-secret");
    expect(h.get("x-forwarded-proto")).toBe("https");
    expect(h.get("x-forwarded-host")).toBe("demo.brazier.gicloud.org");
    expect(h.get("cookie")).toBe("a=b");
    expect(calls[0].init?.method).toBe("POST");
    expect(calls[0].init?.redirect).toBe("manual");
    expect(res.headers.get("set-cookie")).toContain("grafana_session=abc");
  });

  it("hands Grafana's redirects to the caller unchanged", async () => {
    answer = () => new Response(null, { status: 302, headers: { location: "https://demo.brazier.gicloud.org/login" } });
    const res = await worker.fetch(req("/"), env);
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toBe("https://demo.brazier.gicloud.org/login");
  });

  it("answers 502 in plain words when the box is down", async () => {
    answer = () => {
      throw new Error("connect timeout");
    };
    const res = await worker.fetch(req("/api/health"), env);
    expect(res.status).toBe(502);
    expect(await res.text()).toContain("not reachable");
  });

  it("refuses with 503 when no key is configured, and keeps robots out", async () => {
    const res = await worker.fetch(req("/api/health"), { ...env, DEMO_KEY: undefined });
    expect(res.status).toBe(503);
    const robots = await worker.fetch(req("/robots.txt"), env);
    expect(await robots.text()).toContain("Disallow: /");
    expect(calls.length).toBe(0);
  });
});
