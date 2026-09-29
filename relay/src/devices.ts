/** The device registry in KV: `devices/<user>` holds that user's devices as a JSON array. */

export interface Device {
  token: string;
  platform: "ios";
  environment: "production" | "sandbox";
  name: string;
  added: string;
}

const TOKEN_RE = /^[0-9a-f]{32,400}$/;

export function normaliseToken(token: unknown): string | null {
  if (typeof token !== "string") return null;
  const t = token.trim().toLowerCase();
  return TOKEN_RE.test(t) ? t : null;
}

function key(user: string): string {
  return `devices/${user.toLowerCase()}`;
}

export async function listDevices(kv: KVNamespace, user: string): Promise<Device[]> {
  const raw = await kv.get(key(user), "json");
  return Array.isArray(raw) ? (raw as Device[]) : [];
}

/** Add or replace by token. Returns the list after the change. */
export async function putDevice(kv: KVNamespace, user: string, device: Device): Promise<Device[]> {
  const current = await listDevices(kv, user);
  const next = current.filter((d) => d.token !== device.token);
  next.push(device);
  await kv.put(key(user), JSON.stringify(next));
  return next;
}

/** Remove by token. Returns true when something was removed. */
export async function removeDevice(kv: KVNamespace, user: string, token: string): Promise<boolean> {
  const current = await listDevices(kv, user);
  const next = current.filter((d) => d.token !== token);
  if (next.length === current.length) return false;
  if (next.length === 0) await kv.delete(key(user));
  else await kv.put(key(user), JSON.stringify(next));
  return true;
}
