/** The device registry in KV: `devices/<login>` holds that user's devices; `alias/<email>` points at the login
 *  so ROUTES may name a person by either. */
import type { Level, Quiet } from "./severity";

/** What one phone wants to hear. Set by the app's Notifications screen, applied by the relay at send time. */
export interface Prefs {
  /** Grafana org ids this device wants; absent or null = every org */
  orgs?: number[] | null;
  /** lowest severity to push (see severity.ts); absent = everything */
  minSeverity?: Level;
  /** quiet hours in the device's own time zone; pushes in the window are delivered silently */
  quiet?: Quiet | null;
}

export interface Device {
  token: string;
  platform: "ios";
  environment: "production" | "sandbox";
  name: string;
  added: string;
  /** which Grafana the user signed in to when registering */
  grafana?: string;
  prefs?: Prefs;
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

/** Resolve a ROUTES name (login or email) to the login the devices are filed under. */
export async function resolveUser(kv: KVNamespace, name: string): Promise<string> {
  const n = name.toLowerCase();
  const alias = await kv.get(`alias/${n}`);
  return alias ?? n;
}

export async function listDevices(kv: KVNamespace, user: string): Promise<Device[]> {
  const raw = await kv.get(key(user), "json");
  return Array.isArray(raw) ? (raw as Device[]) : [];
}

/** Add or replace by token; remember the email as an alias. A re-registration without `prefs` keeps the
 *  preferences already filed for that token. Returns the list after the change. */
export async function putDevice(kv: KVNamespace, login: string, email: string, device: Device): Promise<Device[]> {
  const current = await listDevices(kv, login);
  const previous = current.find((d) => d.token === device.token);
  const next = current.filter((d) => d.token !== device.token);
  const merged: Device = { ...device };
  if (merged.prefs === undefined && previous?.prefs !== undefined) merged.prefs = previous.prefs;
  if (merged.prefs === undefined) delete merged.prefs;
  next.push(merged);
  await kv.put(key(login), JSON.stringify(next));
  if (email && email !== login.toLowerCase()) await kv.put(`alias/${email.toLowerCase()}`, login.toLowerCase());
  return next;
}

/** Replace the preferences on one of the user's devices. Null when no device with that token is filed under them. */
export async function setPrefs(kv: KVNamespace, user: string, token: string, prefs: Prefs): Promise<Device | null> {
  const current = await listDevices(kv, user);
  const i = current.findIndex((d) => d.token === token);
  if (i < 0) return null;
  current[i] = { ...current[i], prefs };
  await kv.put(key(user), JSON.stringify(current));
  return current[i];
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
