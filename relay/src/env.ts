/** Bindings and settings. Vars live in wrangler.jsonc, secrets in `wrangler secret put`. */
export interface Env {
  DEVICES: KVNamespace;
  /** Comma-separated Grafana origins this relay serves; device registration is refused for any other. */
  GRAFANA_URLS: string;
  /** Optional JSON: Grafana origin → { issuer, clientId, name }: how the app signs in to that Grafana through
   *  its identity provider (Grafana's JWT auth must trust that provider). Published at /.well-known/brazier. */
  SIGN_IN?: string;
  /** This relay's public address, published in the discovery document so the app finds it from the
   *  Grafana address alone. Defaults to the origin the document is requested on when that is not a Grafana. */
  RELAY_URL?: string;
  ROUTES: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
  APNS_KEY_ID: string;
  WEBHOOK_SECRET?: string;
  APNS_KEY?: string;
}

export const VERSION = "0.4.1";

/** Seven days, in seconds: how long a sent firing/resolved pair is remembered for dedupe. */
export const SENT_TTL_SECONDS = 7 * 24 * 60 * 60;

export function apnsConfigured(env: Env): boolean {
  return Boolean(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_TOPIC);
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}
