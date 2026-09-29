// Shared helpers for the Grafana contract tests: one Grafana per run, reached at GRAFANA_URL.
import { createServer } from "node:http";
import { generateKeyPairSync, createSign, createHmac } from "node:crypto";

export const base = (process.env.GRAFANA_URL ?? "http://127.0.0.1:3000").replace(/\/+$/, "");
export const admin = { user: process.env.GRAFANA_ADMIN_USER ?? "admin", password: process.env.GRAFANA_ADMIN_PASSWORD ?? "contract" };
export const basic = "Basic " + Buffer.from(`${admin.user}:${admin.password}`).toString("base64");

/** fetch against Grafana; `auth` is a header value, `null` for none (default: the admin's Basic); `org` adds X-Grafana-Org-Id. */
export async function api(method, path, { body, auth = basic, org, headers = {}, redirect = "manual" } = {}) {
  if (auth === undefined) auth = basic;
  const h = { Accept: "application/json", "User-Agent": "brazier-contract", ...headers };
  if (auth) h.Authorization = auth;
  if (org) h["X-Grafana-Org-Id"] = String(org);
  if (body !== undefined) h["Content-Type"] = "application/json";
  const res = await fetch(base + path, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body), redirect });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = undefined; }
  return { status: res.status, json, text, headers: res.headers };
}

export function version() {
  return api("GET", "/api/health").then((r) => r.json?.version ?? "0");
}
export function major(v) { return Number(String(v).split(".")[0]); }

export async function waitFor(what, fn, { timeoutMs = 90_000, everyMs = 2_000 } = {}) {
  const until = Date.now() + timeoutMs;
  let last;
  while (Date.now() < until) {
    last = await fn();
    if (last) return last;
    await new Promise((r) => setTimeout(r, everyMs));
  }
  throw new Error(`timed out waiting for ${what}`);
}

/** A local HTTP receiver the container reaches at host.docker.internal:<port>. Collects every request. */
export function receiver() {
  const hits = [];
  const server = createServer((req, res) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => {
      hits.push({ path: req.url, headers: req.headers, body: data });
      res.writeHead(200, { "content-type": "application/json" });
      res.end("{}");
    });
  });
  return new Promise((resolve) => {
    server.listen(0, "0.0.0.0", () => resolve({ port: server.address().port, hits, close: () => server.close() }));
  });
}

export function hmacHex(secret, timestamp, body) {
  return createHmac("sha256", secret).update(`${timestamp}:${body}`).digest("hex");
}

/** An ES256 key pair as a JWKS (for Grafana's jwk_set_file) and a signer for test ID tokens. */
export function jwtKit() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = publicKey.export({ format: "jwk" });
  const jwks = { keys: [{ ...jwk, kid: "contract", use: "sig", alg: "ES256" }] };
  const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
  const sign = (claims) => {
    const head = b64({ alg: "ES256", kid: "contract", typ: "JWT" });
    const now = Math.floor(Date.now() / 1000);
    const body = b64({ iat: now, exp: now + 600, ...claims });
    const s = createSign("sha256"); s.update(`${head}.${body}`); s.end();
    return `${head}.${body}.${s.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
  };
  return { jwks, sign };
}
