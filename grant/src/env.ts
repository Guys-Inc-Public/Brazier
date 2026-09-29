/** Bindings and settings. Vars live in wrangler.jsonc, the key in `wrangler secret put APNS_KEY`. */
export interface Env {
  /** `relays/<sha256 of the relay key>` → RelayRecord; `url/<origin>` → that hash. */
  RELAYS: KVNamespace;
  APNS_KEY?: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
}

export const VERSION = "0.1.0";

/** How long a granted provider token is good for: 50 minutes, so a relay refreshes before Apple's 60. */
export const GRANT_SECONDS = 50 * 60;

/** A relay may ask for a fresh token this often. It needs one an hour; this leaves room for a retry. */
export const GRANT_INTERVAL_SECONDS = 60;

export function keyConfigured(env: Env): boolean {
  return Boolean(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_TOPIC);
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}
