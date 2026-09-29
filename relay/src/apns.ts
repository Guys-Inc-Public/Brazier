/** Apple Push Notification service over HTTP/2 with provider-token (ES256) authentication. */

export interface ApnsConfig {
  key: string; // the .p8 contents (PKCS#8 PEM)
  keyId: string;
  teamId: string;
  topic: string;
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

/** A provider token, cached for 50 minutes (Apple accepts up to 60). */
export async function providerToken(cfg: ApnsConfig, now = Date.now()): Promise<string> {
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
  const jwt = await providerToken(cfg);
  const res = await fetch(`${apnsHost(environment)}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": cfg.topic,
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
