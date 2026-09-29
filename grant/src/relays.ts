/** The register of relays allowed to ask for a token, keyed by the hash of the key each holds. */
import { newRelayKey, sha256Hex } from "./sign";

export interface RelayRecord {
  url: string;
  created: string;
  grants: number;
  /** epoch seconds of the last grant, for the rate limit */
  last?: number;
}

const PRIVATE_HOST = /^(localhost|.*\.localhost|.*\.local|.*\.internal|.*\.home\.arpa)$/i;
const PRIVATE_V4 = /^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.)/;

/** The origin of a relay someone may register: https, a public name, nothing else. */
export function relayOrigin(raw: unknown): { origin: string } | { error: string } {
  if (typeof raw !== "string" || !raw.trim()) return { error: "relay must be the relay's https address" };
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    return { error: "relay is not a URL" };
  }
  if (url.protocol !== "https:") return { error: "relay must be https" };
  if (url.username || url.password) return { error: "relay must not carry credentials" };
  const host = url.hostname.toLowerCase();
  if (PRIVATE_HOST.test(host) || PRIVATE_V4.test(host) || host.startsWith("[")) return { error: "relay must be reachable from the internet" };
  if (!host.includes(".")) return { error: "relay must be a public hostname" };
  return { origin: url.origin };
}

/** Is that a Brazier relay? Its discovery document says so. */
export async function looksLikeRelay(origin: string): Promise<{ ok: true; version: string } | { ok: false; why: string }> {
  let res: Response;
  try {
    res = await fetch(`${origin}/.well-known/brazier`, {
      headers: { accept: "application/json", "user-agent": "brazier-grant" },
      signal: AbortSignal.timeout(5000),
      redirect: "manual",
    });
  } catch (e) {
    return { ok: false, why: `could not reach ${origin}: ${(e as Error).message}` };
  }
  if (res.status !== 200) return { ok: false, why: `${origin}/.well-known/brazier answered ${res.status}` };
  let body: { relay?: { version?: unknown } };
  try {
    body = (await res.json()) as typeof body;
  } catch {
    return { ok: false, why: `${origin}/.well-known/brazier is not JSON` };
  }
  const version = body?.relay?.version;
  if (typeof version !== "string" || !version) return { ok: false, why: `${origin} does not answer like a Brazier relay` };
  return { ok: true, version };
}

export async function registeredHash(kv: KVNamespace, origin: string): Promise<string | null> {
  return kv.get(`url/${origin}`);
}

/** File a relay and hand back the one copy of its key. */
export async function registerRelay(kv: KVNamespace, origin: string, now = new Date()): Promise<string> {
  const key = newRelayKey();
  const hash = await sha256Hex(key);
  await kv.put(`relays/${hash}`, JSON.stringify({ url: origin, created: now.toISOString(), grants: 0 } satisfies RelayRecord));
  await kv.put(`url/${origin}`, hash);
  return key;
}

export async function lookupRelay(kv: KVNamespace, key: string): Promise<{ hash: string; record: RelayRecord } | null> {
  if (!/^[A-Za-z0-9_-]{40,50}$/.test(key)) return null;
  const hash = await sha256Hex(key);
  const record = await kv.get<RelayRecord>(`relays/${hash}`, "json");
  return record ? { hash, record } : null;
}

export async function saveRelay(kv: KVNamespace, hash: string, record: RelayRecord): Promise<void> {
  await kv.put(`relays/${hash}`, JSON.stringify(record));
}

export async function countRelays(kv: KVNamespace): Promise<number> {
  const list = await kv.list({ prefix: "relays/", limit: 1000 });
  return list.keys.length;
}
