/** Who is calling? The Grafana instance the app signed in to says so.
 *  The app forwards the same credential it uses for Grafana, in headers; the relay asks that Grafana
 *  `/api/user` and files the device under the login it answers with. No identity provider to configure,
 *  so any Grafana works: password, SSO, service-account token, or an OIDC token through Grafana's JWT auth. */

export interface GrafanaUser {
  login: string;
  email: string;
  name: string;
  origin: string;
}

export type Credential =
  | { kind: "bearer"; value: string }
  | { kind: "cookie"; value: string }
  | { kind: "jwt"; value: string };

/** The Grafana origins this relay serves, from the GRAFANA_URLS var (comma separated). */
export function allowedOrigins(raw: string | undefined): Set<string> {
  const out = new Set<string>();
  for (const part of (raw ?? "").split(",")) {
    const s = part.trim();
    if (!s) continue;
    try {
      out.add(new URL(s).origin);
    } catch {
      throw new Error(`GRAFANA_URLS entry "${s}" is not a URL`);
    }
  }
  return out;
}

/** Read the credential and the Grafana origin from the request headers. */
export function readCredential(req: Request): { origin: string; credential: Credential } | { error: string } {
  const raw = req.headers.get("x-grafana-url");
  if (!raw) return { error: "X-Grafana-Url header required" };
  let origin: string;
  try {
    const u = new URL(raw);
    if (u.protocol !== "https:" && u.hostname !== "localhost" && u.hostname !== "127.0.0.1") return { error: "Grafana address must be https" };
    origin = u.origin;
  } catch {
    return { error: "X-Grafana-Url is not a URL" };
  }
  const auth = req.headers.get("authorization");
  const cookie = req.headers.get("cookie");
  const jwt = req.headers.get("x-jwt-assertion");
  const bearer = auth ? /^Bearer\s+(.+)$/i.exec(auth)?.[1]?.trim() : undefined;
  const session = cookie ? /(?:^|;\s*)grafana_session=([^;]+)/.exec(cookie)?.[1] : undefined;
  const given = [bearer && { kind: "bearer" as const, value: bearer }, session && { kind: "cookie" as const, value: session }, jwt && { kind: "jwt" as const, value: jwt.trim() }].filter(Boolean) as Credential[];
  if (given.length !== 1) return { error: "exactly one of Authorization: Bearer, Cookie: grafana_session or X-JWT-Assertion is required" };
  return { origin, credential: given[0] };
}

/** Ask the Grafana at `origin` who this credential belongs to. Throws with a short reason. */
export async function whoAmI(origin: string, credential: Credential): Promise<GrafanaUser> {
  const headers: Record<string, string> = { accept: "application/json", "user-agent": "brazier-relay" };
  if (credential.kind === "bearer") headers.authorization = `Bearer ${credential.value}`;
  else if (credential.kind === "cookie") headers.cookie = `grafana_session=${credential.value}`;
  else headers["x-jwt-assertion"] = credential.value;
  let res: Response;
  try {
    res = await fetch(`${origin}/api/user`, { headers, redirect: "manual" });
  } catch (e) {
    throw new Error(`grafana unreachable: ${(e as Error).message}`);
  }
  if (res.status === 401 || res.status === 403) throw new Error("grafana rejected the credential");
  if (res.status !== 200) throw new Error(`grafana answered ${res.status}`);
  const body = (await res.json()) as { login?: string; email?: string; name?: string };
  const login = (body.login ?? "").trim().toLowerCase();
  if (!login) throw new Error("grafana user has no login");
  return { login, email: (body.email ?? "").trim().toLowerCase(), name: body.name ?? "", origin };
}
