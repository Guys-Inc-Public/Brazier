/** The APNs provider token (ES256 JWT over the .p8), relay keys and their hashes. */

const enc = new TextEncoder();

export function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/** A provider token as Apple wants it: `{"alg":"ES256","kid"}` over `{"iss": team, "iat"}`. */
export async function signProviderToken(pem: string, keyId: string, teamId: string, iat: number): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = b64url(enc.encode(JSON.stringify({ iss: teamId, iat })));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${header}.${claims}`));
  return `${header}.${claims}.${b64url(new Uint8Array(sig))}`;
}

/** 32 random bytes, base64url: what a relay keeps as its key. Only its hash is stored here. */
export function newRelayKey(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return b64url(bytes);
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", enc.encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
