/** Brazier relay: Grafana's webhook in, Apple's push out. Routes:
 *    POST   /grafana           HMAC-signed webhook from a Grafana contact point
 *    POST   /devices           register this device (Bearer: the app's OIDC ID token)
 *    DELETE /devices/:token    forget it
 *    GET    /health            liveness, version, whether APNs is configured
 */
import { type Env, VERSION, json, apnsConfigured } from "./env";
import { verifyGrafanaSignature } from "./hmac";
import { verifyJwt, userKey } from "./jwt";
import { parseWebhook, deliver } from "./notify";
import { listDevices, normaliseToken, putDevice, removeDevice, type Device } from "./devices";

const SIGNATURE_HEADER = "x-grafana-alerting-signature";
const TIMESTAMP_HEADER = "x-grafana-alerting-timestamp";

async function authUser(req: Request, env: Env): Promise<string | Response> {
  const auth = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) return json({ error: "bearer token required" }, 401, { "www-authenticate": "Bearer" });
  try {
    const claims = await verifyJwt(m[1].trim(), { jwksUrl: env.JWKS_URL, issuer: env.JWT_ISSUER, audience: env.JWT_AUDIENCE || undefined });
    return userKey(claims).toLowerCase();
  } catch (e) {
    return json({ error: `token rejected: ${(e as Error).message}` }, 401, { "www-authenticate": "Bearer" });
  }
}

async function handleGrafana(req: Request, env: Env): Promise<Response> {
  if (!env.WEBHOOK_SECRET) return json({ error: "relay has no WEBHOOK_SECRET" }, 503);
  const body = new Uint8Array(await req.arrayBuffer());
  const ok = await verifyGrafanaSignature(env.WEBHOOK_SECRET, body, req.headers.get(SIGNATURE_HEADER), req.headers.get(TIMESTAMP_HEADER));
  if (!ok) return json({ error: "bad signature" }, 401);
  let wh;
  try {
    wh = parseWebhook(new TextDecoder().decode(body));
  } catch (e) {
    return json({ error: (e as Error).message }, 400);
  }
  const outcome = await deliver(env, wh);
  console.log(JSON.stringify({ webhook: wh.receiver, ...outcome }));
  return json(outcome, 200);
}

async function handleRegister(req: Request, env: Env): Promise<Response> {
  const user = await authUser(req, env);
  if (user instanceof Response) return user;
  let body: Partial<Device>;
  try {
    body = (await req.json()) as Partial<Device>;
  } catch {
    return json({ error: "body is not JSON" }, 400);
  }
  const token = normaliseToken(body.token);
  if (!token) return json({ error: "token must be the APNs device token in hex" }, 400);
  const environment = body.environment === "sandbox" ? "sandbox" : "production";
  const name = typeof body.name === "string" ? body.name.slice(0, 80) : "iPhone";
  const devices = await putDevice(env.DEVICES, user, { token, platform: "ios", environment, name, added: new Date().toISOString() });
  return json({ ok: true, user, devices: devices.length });
}

async function handleForget(req: Request, env: Env, rawToken: string): Promise<Response> {
  const user = await authUser(req, env);
  if (user instanceof Response) return user;
  const token = normaliseToken(rawToken);
  if (!token) return json({ error: "bad token" }, 400);
  const removed = await removeDevice(env.DEVICES, user, token);
  return json({ ok: true, removed });
}

async function handleList(req: Request, env: Env): Promise<Response> {
  const user = await authUser(req, env);
  if (user instanceof Response) return user;
  const devices = await listDevices(env.DEVICES, user);
  return json({ user, devices: devices.map((d) => ({ name: d.name, environment: d.environment, added: d.added, token: `…${d.token.slice(-6)}` })) });
}

async function handleHealth(env: Env): Promise<Response> {
  let kv = "ok";
  try {
    await env.DEVICES.get("health");
  } catch {
    kv = "error";
  }
  const ok = kv === "ok";
  return json({ ok, version: VERSION, kv, apns: apnsConfigured(env), webhook: Boolean(env.WEBHOOK_SECRET) }, ok ? 200 : 503);
}

export default {
  async fetch(req: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    if (req.method === "GET" && path === "/health") return handleHealth(env);
    if (req.method === "POST" && path === "/grafana") return handleGrafana(req, env);
    if (req.method === "POST" && path === "/devices") return handleRegister(req, env);
    if (req.method === "GET" && path === "/devices") return handleList(req, env);
    const m = /^\/devices\/([^/]+)$/.exec(path);
    if (req.method === "DELETE" && m) return handleForget(req, env, decodeURIComponent(m[1]));
    if (path === "/") return new Response(`brazier-relay ${VERSION}\n`, { headers: { "content-type": "text/plain" } });
    return json({ error: "not found" }, 404);
  },
} satisfies ExportedHandler<Env>;
