/** Verify a Keystone (or any OIDC) RS256 JWT against a JWKS URL. No library: WebCrypto only. */

export interface Claims {
  iss?: string;
  sub?: string;
  aud?: string | string[];
  exp?: number;
  iat?: number;
  nbf?: number;
  email?: string;
  preferred_username?: string;
  [k: string]: unknown;
}

interface Jwk extends JsonWebKey {
  kid?: string;
}

const JWKS_TTL_MS = 10 * 60 * 1000;
const cache = new Map<string, { at: number; keys: Jwk[] }>();

function b64urlToBytes(s: string): Uint8Array {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

function decodeJson<T>(part: string): T {
  return JSON.parse(new TextDecoder().decode(b64urlToBytes(part))) as T;
}

async function fetchJwks(url: string, force = false): Promise<Jwk[]> {
  const hit = cache.get(url);
  if (!force && hit && Date.now() - hit.at < JWKS_TTL_MS) return hit.keys;
  const res = await fetch(url, { headers: { accept: "application/json" } });
  if (!res.ok) throw new Error(`jwks ${res.status}`);
  const body = (await res.json()) as { keys?: Jwk[] };
  const keys = body.keys ?? [];
  cache.set(url, { at: Date.now(), keys });
  return keys;
}

export interface VerifyOptions {
  jwksUrl: string;
  issuer: string;
  audience?: string;
  now?: number;
}

/** Returns the claims when the token is valid, otherwise throws with a short reason. */
export async function verifyJwt(token: string, opts: VerifyOptions): Promise<Claims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed");
  const header = decodeJson<{ alg?: string; kid?: string }>(parts[0]);
  if (header.alg !== "RS256") throw new Error("alg");
  const claims = decodeJson<Claims>(parts[1]);

  let keys = await fetchJwks(opts.jwksUrl);
  let jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) {
    keys = await fetchJwks(opts.jwksUrl, true); // rotated? refetch once
    jwk = keys.find((k) => k.kid === header.kid);
  }
  if (!jwk) throw new Error("kid");

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const data = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64urlToBytes(parts[2]), data);
  if (!ok) throw new Error("signature");

  const now = opts.now ?? Math.floor(Date.now() / 1000);
  if (claims.iss !== opts.issuer) throw new Error("issuer");
  if (typeof claims.exp !== "number" || claims.exp <= now - 30) throw new Error("expired");
  if (typeof claims.nbf === "number" && claims.nbf > now + 30) throw new Error("not yet valid");
  if (opts.audience) {
    const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (!aud.includes(opts.audience)) throw new Error("audience");
  }
  return claims;
}

/** The registry key for a user: their username, else the opaque subject. */
export function userKey(claims: Claims): string {
  const u = claims.preferred_username;
  if (typeof u === "string" && u.length > 0) return u;
  if (typeof claims.sub === "string" && claims.sub.length > 0) return claims.sub;
  throw new Error("no subject");
}
