/** Grafana's webhook signature: HMAC-SHA256 over the raw body, hex encoded, in a header.
 *  With a timestamp header configured, the signed content is `<timestamp>:<body>`. */

const enc = new TextEncoder();

async function hmacHex(secret: string, content: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, content);
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

/** Constant-time equality of two hex strings. */
function equalHex(a: string, b: string): boolean {
  if (a.length !== b.length || a.length === 0) return false;
  const ea = enc.encode(a);
  const eb = enc.encode(b);
  return crypto.subtle.timingSafeEqual(ea, eb);
}

/**
 * Verify a Grafana webhook signature.
 * @param body raw request body
 * @param signature value of the signature header (hex); a `v1=` prefixed form is also accepted
 * @param timestamp value of the timestamp header, if Grafana sent one
 */
export async function verifyGrafanaSignature(
  secret: string,
  body: Uint8Array,
  signature: string | null,
  timestamp: string | null,
): Promise<boolean> {
  if (!signature) return false;
  const given = signature.trim().replace(/^(sha256=|v1=)/, "").toLowerCase();
  const content = timestamp ? concat(enc.encode(`${timestamp}:`), body) : body;
  const expected = await hmacHex(secret, content);
  return equalHex(expected, given);
}

/** Sign the way Grafana does. Used by the tests and by anyone sending by hand. */
export async function signLikeGrafana(secret: string, body: Uint8Array, timestamp?: string): Promise<string> {
  const content = timestamp ? concat(enc.encode(`${timestamp}:`), body) : body;
  return hmacHex(secret, content);
}
