/** Apple Push Notification service over HTTP/2 with provider-token (ES256) authentication. The token is
 *  signed here when the relay holds a key, or borrowed from the Brazier push grant when it does not. */
import type { Env } from "./env";
import { pushSource } from "./env";

/** Our own key: the .p8 contents (PKCS#8 PEM) and what goes with it. */
export interface ApnsKey {
  kind: "key";
  key: string;
  keyId: string;
  teamId: string;
  topic: string;
}

/** The push grant: a service of Guys Inc's that signs tokens with the key we may not hand out. */
export interface ApnsGrant {
  kind: "grant";
  url: string;
  relayKey: string;
  kv: KVNamespace;
}

export type ApnsConfig = ApnsKey | ApnsGrant;

/** What a push needs in its headers. */
export interface ProviderAuth {
  token: string;
  topic: string;
}

/** What the grant answers and what the relay keeps in KV under `grant/token`. */
interface GrantedToken {
  token: string;
  keyId: string;
  teamId: string;
  topic: string;
  issuedAt: number;
  expiresAt: number;
}

export function apnsSource(env: Env): ApnsConfig | null {
  switch (pushSource(env)) {
    case "key":
      return { kind: "key", key: env.APNS_KEY as string, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC };
    case "grant":
      return { kind: "grant", url: (env.PUSH_GRANT_URL as string).replace(/\/+$/, ""), relayKey: env.PUSH_GRANT_KEY as string, kv: env.DEVICES };
    default:
      return null;
  }
}

export interface ApnsMessage {
  collapseId: string;
  payload: Record<string, unknown>;
  /** seconds since epoch; 0 = deliver once, now or never */
  expiration?: number;
  priority?: 5 | 10;
}

export interface ApnsResult {
  status: number;
  reason?: string;
  /** Apple says this token is gone: remove the device. */
  drop: boolean;
}

const enc = new TextEncoder();
const TOKEN_LIFETIME_MS = 50 * 60 * 1000;
const tokenCache = new Map<string, { at: number; jwt: string }>();

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/** Refresh a granted token when it has this long left. */
const GRANT_REFRESH_MS = 5 * 60 * 1000;
const GRANT_KEY = "grant/token";

/** A provider token, cached for 50 minutes (Apple accepts up to 60). */
export async function providerToken(cfg: ApnsKey, now = Date.now()): Promise<string> {
  const hit = tokenCache.get(cfg.keyId);
  if (hit && now - hit.at < TOKEN_LIFETIME_MS) return hit.jwt;
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(cfg.key), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: cfg.keyId })));
  const claims = b64url(enc.encode(JSON.stringify({ iss: cfg.teamId, iat: Math.floor(now / 1000) })));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(new Uint8Array(sig))}`;
  tokenCache.set(cfg.keyId, { at: now, jwt });
  return jwt;
}

/** A token from the push grant, kept in KV until five minutes before it lapses. */
export async function grantedToken(cfg: ApnsGrant, now = Date.now()): Promise<GrantedToken> {
  const kept = await cfg.kv.get<GrantedToken>(GRANT_KEY, "json");
  if (kept && kept.expiresAt * 1000 - now > GRANT_REFRESH_MS) return kept;
  const res = await fetch(`${cfg.url}/grant`, {
    method: "POST",
    headers: { authorization: `Bearer ${cfg.relayKey}`, accept: "application/json", "user-agent": "brazier-relay" },
  });
  if (res.status !== 200) {
    let why = "";
    try {
      why = ((await res.json()) as { error?: string }).error ?? "";
    } catch {
      /* no body */
    }
    throw new Error(`push grant answered ${res.status}${why ? `: ${why}` : ""}`);
  }
  const granted = (await res.json()) as GrantedToken;
  if (typeof granted.token !== "string" || typeof granted.expiresAt !== "number" || typeof granted.topic !== "string") {
    throw new Error("push grant answered without a token");
  }
  const ttl = Math.max(60, Math.floor(granted.expiresAt - now / 1000));
  await cfg.kv.put(GRANT_KEY, JSON.stringify(granted), { expirationTtl: ttl });
  return granted;
}

/** The bearer token and topic for a push, from whichever source the relay has. */
export async function providerAuth(cfg: ApnsConfig, now = Date.now()): Promise<ProviderAuth> {
  if (cfg.kind === "key") return { token: await providerToken(cfg, now), topic: cfg.topic };
  const granted = await grantedToken(cfg, now);
  return { token: granted.token, topic: granted.topic };
}

export function apnsHost(environment: "production" | "sandbox"): string {
  return environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
}

/** Reasons after which the token will never work again. */
const DROP_REASONS = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic", "ExpiredToken"]);

export async function sendPush(
  cfg: ApnsConfig,
  deviceToken: string,
  environment: "production" | "sandbox",
  msg: ApnsMessage,
): Promise<ApnsResult> {
  const auth = await providerAuth(cfg);
  const res = await fetch(`${apnsHost(environment)}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${auth.token}`,
      "apns-topic": auth.topic,
      "apns-push-type": "alert",
      "apns-priority": String(msg.priority ?? 10),
      "apns-expiration": String(msg.expiration ?? 0),
      "apns-collapse-id": msg.collapseId.slice(0, 64),
      "content-type": "application/json",
    },
    body: JSON.stringify(msg.payload),
  });
  if (res.status === 200) return { status: 200, drop: false };
  let reason: string | undefined;
  try {
    reason = ((await res.json()) as { reason?: string }).reason;
  } catch {
    /* no body */
  }
  const drop = res.status === 410 || (res.status === 400 && reason !== undefined && DROP_REASONS.has(reason));
  return { status: res.status, reason, drop };
}
