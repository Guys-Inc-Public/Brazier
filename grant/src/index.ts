/** Brazier push grant: lends a self-hosted relay a short-lived APNs provider token for the Brazier app,
 *  so the key that can push to Brazier phones never leaves Guys Inc (decision 0005). Routes:
 *    POST /relays   { relay: "https://…" }  register a relay: it must answer /.well-known/brazier like one;
 *                                           answers the relay key, shown once
 *    POST /grant    Authorization: Bearer <relay key>  a provider token good for 50 minutes
 *    GET  /health   liveness, version, whether the key is loaded, how many relays are registered
 */
import { type Env, VERSION, GRANT_SECONDS, GRANT_INTERVAL_SECONDS, json, keyConfigured } from "./env";
import { signProviderToken } from "./sign";
import { countRelays, looksLikeRelay, lookupRelay, registerRelay, registeredHash, relayOrigin, saveRelay } from "./relays";

async function handleRegister(req: Request, env: Env): Promise<Response> {
  let body: { relay?: unknown };
  try {
    body = (await req.json()) as typeof body;
  } catch {
    return json({ error: "body is not JSON" }, 400);
  }
  const parsed = relayOrigin(body?.relay);
  if ("error" in parsed) return json({ error: parsed.error }, 400);
  if (await registeredHash(env.RELAYS, parsed.origin)) {
    return json({ error: `${parsed.origin} is already registered; delete the old key first` }, 409);
  }
  const check = await looksLikeRelay(parsed.origin);
  if (!check.ok) return json({ error: check.why }, 422);
  const relayKey = await registerRelay(env.RELAYS, parsed.origin);
  console.log(JSON.stringify({ registered: parsed.origin, relay: check.version }));
  return json({ ok: true, relayKey, topic: env.APNS_TOPIC, relay: parsed.origin }, 201);
}

async function handleGrant(req: Request, env: Env): Promise<Response> {
  if (!keyConfigured(env)) return json({ error: "grant has no APNS_KEY" }, 503);
  const m = /^Bearer\s+(\S+)$/i.exec(req.headers.get("authorization") ?? "");
  const found = m ? await lookupRelay(env.RELAYS, m[1]) : null;
  if (!found) return json({ error: "unknown relay key" }, 401);
  const now = Math.floor(Date.now() / 1000);
  const { hash, record } = found;
  if (record.last !== undefined && now - record.last < GRANT_INTERVAL_SECONDS) {
    const wait = GRANT_INTERVAL_SECONDS - (now - record.last);
    return json({ error: `one grant a minute; try again in ${wait} s` }, 429, { "retry-after": String(wait) });
  }
  const token = await signProviderToken(env.APNS_KEY as string, env.APNS_KEY_ID, env.APNS_TEAM_ID, now);
  await saveRelay(env.RELAYS, hash, { ...record, grants: record.grants + 1, last: now });
  console.log(JSON.stringify({ grant: record.url, grants: record.grants + 1 }));
  return json({ token, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC, issuedAt: now, expiresAt: now + GRANT_SECONDS });
}

async function handleHealth(env: Env): Promise<Response> {
  let relays = -1;
  let ok = true;
  try {
    relays = await countRelays(env.RELAYS);
  } catch {
    ok = false;
  }
  return json({ ok, version: VERSION, apns: keyConfigured(env), relays }, ok ? 200 : 503);
}

export default {
  async fetch(req: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    if (req.method === "GET" && path === "/health") return handleHealth(env);
    if (req.method === "POST" && path === "/relays") return handleRegister(req, env);
    if (req.method === "POST" && path === "/grant") return handleGrant(req, env);
    if (path === "/") return new Response(`brazier-grant ${VERSION}\n`, { headers: { "content-type": "text/plain" } });
    return json({ error: "not found" }, 404);
  },
} satisfies ExportedHandler<Env>;
