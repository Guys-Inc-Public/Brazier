/** Brazier relay: Grafana's webhook in, Apple's push out. Routes:
 *    POST   /grafana           webhook from a Grafana contact point: HMAC-signed (Grafana 11+), or
 *                              HTTP Basic with the shared secret as the password (older Grafanas)
 *    POST   /devices           register this device; the caller proves who they are with the same
 *                              credential the app uses for Grafana (headers, see identity.ts)
 *    GET    /devices           the caller's devices, with their preferences
 *    PUT    /devices/:token/preferences  what that device wants: orgs, a severity floor, quiet hours
 *    DELETE /devices/:token    forget one
 *    GET    /health            liveness, version, whether APNs (own key or push grant) and the secret are configured
 *    GET    /.well-known/brazier  discovery: this relay's address, the Grafanas it serves and how the app
 *                              signs in to them. Also served on each Grafana's own hostname through a
 *                              Worker route, so the app finds everything from the Grafana address alone.
 */
import { type Env, VERSION, json, apnsConfigured, pushSource } from "./env";
import { verifyGrafanaSignature, verifyBasicSecret } from "./hmac";
import { parseWebhook, deliver } from "./notify";
import { listDevices, normaliseToken, putDevice, removeDevice, setPrefs, type Device, type Prefs } from "./devices";
import { HHMM, isLevel } from "./severity";
import { allowedOrigins, readCredential, whoAmI, type GrafanaUser } from "./identity";

const SIGNATURE_HEADER = "x-grafana-alerting-signature";
const TIMESTAMP_HEADER = "x-grafana-alerting-timestamp";

/** Identify the caller through their Grafana, or answer why not. */
async function caller(req: Request, env: Env): Promise<GrafanaUser | Response> {
  const read = readCredential(req);
  if ("error" in read) return json({ error: read.error }, 401);
  let allowed: Set<string>;
  try {
    allowed = allowedOrigins(env.GRAFANA_URLS);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
  if (!allowed.has(read.origin)) return json({ error: `this relay does not serve ${read.origin}` }, 403);
  try {
    return await whoAmI(read.origin, read.credential);
  } catch (e) {
    const msg = (e as Error).message;
    return json({ error: msg }, msg.includes("rejected") ? 401 : 502);
  }
}

async function handleGrafana(req: Request, env: Env): Promise<Response> {
  if (!env.WEBHOOK_SECRET) return json({ error: "relay has no WEBHOOK_SECRET" }, 503);
  const body = new Uint8Array(await req.arrayBuffer());
  const signed = req.headers.has(SIGNATURE_HEADER)
    ? await verifyGrafanaSignature(env.WEBHOOK_SECRET, body, req.headers.get(SIGNATURE_HEADER), req.headers.get(TIMESTAMP_HEADER))
    : verifyBasicSecret(env.WEBHOOK_SECRET, req.headers.get("authorization"));
  if (!signed) return json({ error: "bad signature" }, 401);
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

/** A preferences object from the app, checked field by field. Throws with the reason. */
export function readPrefs(raw: unknown): Prefs {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) throw new Error("prefs must be an object");
  const p = raw as Record<string, unknown>;
  for (const k of Object.keys(p)) {
    if (k !== "orgs" && k !== "minSeverity" && k !== "quiet") throw new Error(`prefs.${k} is not a preference`);
  }
  const out: Prefs = {};
  if ("orgs" in p) {
    if (p.orgs === null) out.orgs = null;
    else if (Array.isArray(p.orgs) && p.orgs.every((n) => Number.isInteger(n) && (n as number) > 0)) out.orgs = [...new Set(p.orgs as number[])];
    else throw new Error("prefs.orgs must be a list of org ids, or null for every org");
  }
  if ("minSeverity" in p && p.minSeverity !== undefined) {
    if (!isLevel(p.minSeverity)) throw new Error("prefs.minSeverity must be info, warning, critical or page");
    out.minSeverity = p.minSeverity;
  }
  if ("quiet" in p) {
    if (p.quiet === null) out.quiet = null;
    else {
      const q = p.quiet as Record<string, unknown> | undefined;
      if (!q || typeof q !== "object" || Array.isArray(q)) throw new Error("prefs.quiet must be an object or null");
      if (typeof q.start !== "string" || !HHMM.test(q.start) || typeof q.end !== "string" || !HHMM.test(q.end)) throw new Error("prefs.quiet.start and end must be HH:MM");
      if (typeof q.tz !== "string" || !q.tz.trim() || q.tz.length > 64) throw new Error("prefs.quiet.tz must be an IANA zone name");
      if (q.allowPage !== undefined && typeof q.allowPage !== "boolean") throw new Error("prefs.quiet.allowPage must be true or false");
      out.quiet = { start: q.start, end: q.end, tz: q.tz.trim(), ...(q.allowPage === undefined ? {} : { allowPage: q.allowPage }) };
    }
  }
  return out;
}

async function handleRegister(req: Request, env: Env): Promise<Response> {
  const who = await caller(req, env);
  if (who instanceof Response) return who;
  let body: Partial<Device> & { prefs?: unknown };
  try {
    body = (await req.json()) as Partial<Device>;
  } catch {
    return json({ error: "body is not JSON" }, 400);
  }
  const token = normaliseToken(body.token);
  if (!token) return json({ error: "token must be the APNs device token in hex" }, 400);
  const environment = body.environment === "sandbox" ? "sandbox" : "production";
  const name = typeof body.name === "string" ? body.name.slice(0, 80) : "iPhone";
  let prefs: Prefs | undefined;
  if (body.prefs !== undefined) {
    try {
      prefs = readPrefs(body.prefs);
    } catch (e) {
      return json({ error: (e as Error).message }, 400);
    }
  }
  const devices = await putDevice(env.DEVICES, who.login, who.email, { token, platform: "ios", environment, name, added: new Date().toISOString(), grafana: who.origin, prefs });
  return json({ ok: true, user: who.login, devices: devices.length });
}

async function handlePreferences(req: Request, env: Env, rawToken: string): Promise<Response> {
  const who = await caller(req, env);
  if (who instanceof Response) return who;
  const token = normaliseToken(rawToken);
  if (!token) return json({ error: "bad token" }, 400);
  let prefs: Prefs;
  try {
    prefs = readPrefs(await req.json());
  } catch (e) {
    return json({ error: e instanceof SyntaxError ? "body is not JSON" : (e as Error).message }, 400);
  }
  const device = await setPrefs(env.DEVICES, who.login, token, prefs);
  if (!device) return json({ error: "no such device for this user" }, 404);
  return json({ ok: true, prefs: device.prefs ?? {} });
}

async function handleForget(req: Request, env: Env, rawToken: string): Promise<Response> {
  const who = await caller(req, env);
  if (who instanceof Response) return who;
  const token = normaliseToken(rawToken);
  if (!token) return json({ error: "bad token" }, 400);
  const removed = await removeDevice(env.DEVICES, who.login, token);
  return json({ ok: true, removed });
}

async function handleList(req: Request, env: Env): Promise<Response> {
  const who = await caller(req, env);
  if (who instanceof Response) return who;
  const devices = await listDevices(env.DEVICES, who.login);
  return json({ user: who.login, devices: devices.map((d) => ({ name: d.name, environment: d.environment, added: d.added, token: `…${d.token.slice(-6)}`, prefs: d.prefs ?? {} })) });
}

/** What the app needs before sign-in: the Grafanas served here and, per Grafana, the identity provider
 *  to sign in with (issuer + public client id), when the admin has set one. */
function handleWellKnown(env: Env, requestOrigin: string): Response {
  let allowed: Set<string>;
  try {
    allowed = allowedOrigins(env.GRAFANA_URLS);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
  let signIn: Record<string, { issuer?: string; clientId?: string; name?: string }> = {};
  if (env.SIGN_IN) {
    try {
      signIn = JSON.parse(env.SIGN_IN) as typeof signIn;
    } catch {
      return json({ error: "SIGN_IN is not JSON" }, 500);
    }
  }
  const grafana: Record<string, { signIn?: { issuer: string; clientId: string; name: string } }> = {};
  for (const origin of allowed) {
    const s = signIn[origin];
    grafana[origin] = s && s.issuer && s.clientId ? { signIn: { issuer: s.issuer, clientId: s.clientId, name: s.name ?? new URL(s.issuer).hostname } } : {};
  }
  const relayUrl = env.RELAY_URL || (allowed.has(requestOrigin) ? undefined : requestOrigin);
  return json({ relay: { url: relayUrl, version: VERSION }, grafana }, 200, { "cache-control": "public, max-age=300", "access-control-allow-origin": "*" });
}

async function handleHealth(env: Env): Promise<Response> {
  let kv = "ok";
  try {
    await env.DEVICES.get("health");
  } catch {
    kv = "error";
  }
  const ok = kv === "ok";
  return json({ ok, version: VERSION, kv, apns: apnsConfigured(env), push: pushSource(env), webhook: Boolean(env.WEBHOOK_SECRET), grafana: [...allowedOrigins(env.GRAFANA_URLS)] }, ok ? 200 : 503);
}

export default {
  async fetch(req: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    if (req.method === "GET" && path === "/health") return handleHealth(env);
    if (req.method === "GET" && path === "/.well-known/brazier") return handleWellKnown(env, url.origin);
    if (req.method === "POST" && path === "/grafana") return handleGrafana(req, env);
    if (req.method === "POST" && path === "/devices") return handleRegister(req, env);
    if (req.method === "GET" && path === "/devices") return handleList(req, env);
    const m = /^\/devices\/([^/]+)$/.exec(path);
    if (req.method === "DELETE" && m) return handleForget(req, env, decodeURIComponent(m[1]));
    const pm = /^\/devices\/([^/]+)\/preferences$/.exec(path);
    if (req.method === "PUT" && pm) return handlePreferences(req, env, decodeURIComponent(pm[1]));
    if (path === "/") return new Response(`brazier-relay ${VERSION}\n`, { headers: { "content-type": "text/plain" } });
    return json({ error: "not found" }, 404);
  },
} satisfies ExportedHandler<Env>;
