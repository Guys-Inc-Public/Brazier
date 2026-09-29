/** Turn a Grafana webhook payload into pushes: dedupe, route, filter per device, send, drop dead devices. */
import type { Env } from "./env";
import { SENT_TTL_SECONDS, apnsConfigured } from "./env";
import { parseRoutes, routeUsers } from "./routing";
import { listDevices, removeDevice, resolveUser, type Prefs } from "./devices";
import { apnsSource, sendPush } from "./apns";
import { inQuietHours, level, meets } from "./severity";

/** The parts of Grafana's webhook body the relay reads. */
export interface GrafanaAlert {
  status: "firing" | "resolved";
  labels: Record<string, string>;
  annotations?: Record<string, string>;
  startsAt?: string;
  endsAt?: string;
  generatorURL?: string;
  fingerprint: string;
  silenceURL?: string;
  dashboardURL?: string;
  panelURL?: string;
  valueString?: string;
  /** the Grafana organization the rule lives in (Grafana 9+ sends it per alert and on the body) */
  orgId?: number;
}

export interface GrafanaWebhook {
  receiver?: string;
  status?: string;
  alerts: GrafanaAlert[];
  externalURL?: string;
  groupKey?: string;
  version?: string;
  orgId?: number;
}

export interface Outcome {
  received: number;
  pushed: number;
  skipped: number;
  unrouted: number;
  /** device sends skipped by that device's org or severity preferences */
  filtered: number;
  /** pushes delivered silently because the device was in its quiet hours */
  quiet: number;
  dropped: number;
  failed: number;
  apns: boolean;
}

export function parseWebhook(text: string): GrafanaWebhook {
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new Error("body is not JSON");
  }
  if (!body || typeof body !== "object" || !Array.isArray((body as GrafanaWebhook).alerts)) {
    throw new Error("body has no alerts[]");
  }
  const wh = body as GrafanaWebhook;
  for (const a of wh.alerts) {
    if (typeof a.fingerprint !== "string" || !a.fingerprint) throw new Error("alert without fingerprint");
    if (a.status !== "firing" && a.status !== "resolved") throw new Error(`alert status ${String(a.status)}`);
    if (!a.labels || typeof a.labels !== "object") throw new Error("alert without labels");
  }
  return wh;
}

/** The org an alert belongs to: its own field, else the body's, else 0 for a Grafana that sends none. */
export function orgOf(alert: GrafanaAlert, wh: GrafanaWebhook): number {
  if (typeof alert.orgId === "number") return alert.orgId;
  if (typeof wh.orgId === "number") return wh.orgId;
  return 0;
}

/** `ORGS`: org id → display name, for the lock screen. Bad JSON is logged and ignored, never fails a webhook. */
export function parseOrgs(raw: string | undefined): Record<string, string> {
  if (!raw) return {};
  try {
    const obj = JSON.parse(raw) as unknown;
    if (!obj || typeof obj !== "object" || Array.isArray(obj)) throw new Error("not an object");
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(obj as Record<string, unknown>)) if (typeof v === "string" && v) out[k] = v;
    return out;
  } catch (e) {
    console.log(`ORGS ignored: ${(e as Error).message}`);
    return {};
  }
}

/** The lock-screen text and the data the app needs to open and silence the alert. */
export function buildPayload(alert: GrafanaAlert, externalURL: string | undefined, orgId?: number, orgName?: string): Record<string, unknown> {
  const l = alert.labels;
  const an = alert.annotations ?? {};
  const name = l.alertname ?? "Alert";
  const resolved = alert.status === "resolved";
  const page = l.severity === "page" && !resolved;
  // Grafana raises DatasourceError and DatasourceNoData itself when a rule's query fails or comes back
  // empty. Their annotations are the rule's own, templated with no labels ("[no value]"), so the text is
  // built from what the synthetic alert does carry: the rule's name, the datasource and the error.
  const synthetic = name === "DatasourceError" || name === "DatasourceNoData";
  let title: string;
  let subtitle: string | undefined;
  let body: string;
  if (synthetic) {
    const failed = name === "DatasourceError";
    const rule = l.rulename ?? "A rule";
    const source = l.datasource_uid ?? "its datasource";
    const why = (an.Error ?? "").replace(/\s+/g, " ").trim().slice(0, 180);
    title = `${rule} · ${failed ? "query failed" : "no data"}`;
    subtitle = orgName ? `${orgName} · ${source}` : source;
    body = failed
      ? why ? `Grafana could not query ${source}: ${why}` : `Grafana could not query ${source}.`
      : `The query on ${source} returned nothing.`;
  } else {
    const firstPair = Object.entries(l).find(([k]) => k !== "alertname" && k !== "grafana_folder");
    title = name;
    subtitle = [orgName, l.site, l.host].filter(Boolean).join(" · ") || undefined;
    body = an.summary ?? (firstPair ? `${firstPair[0]}=${firstPair[1]}` : "");
  }
  return {
    aps: {
      alert: {
        title: resolved ? `Resolved: ${title}` : title,
        subtitle,
        body,
      },
      sound: resolved ? undefined : "default",
      "thread-id": l.grafana_folder ?? "alerts",
      category: "ALERT",
      "interruption-level": page ? "time-sensitive" : "active",
      "relevance-score": page ? 1 : resolved ? 0.2 : synthetic ? 0.4 : 0.6,
    },
    brazier: {
      fingerprint: alert.fingerprint,
      status: alert.status,
      alertname: name,
      rulename: l.rulename,
      labels: l,
      annotations: an,
      startsAt: alert.startsAt,
      endsAt: alert.endsAt,
      generatorURL: alert.generatorURL,
      silenceURL: alert.silenceURL,
      externalURL,
      folder: l.grafana_folder,
      orgId,
      org: orgName,
    },
  };
}

/** The same push with no sound and a passive interruption level: it lands in the list, it does not wake anyone. */
export function quieten(payload: Record<string, unknown>): Record<string, unknown> {
  const aps = { ...(payload.aps as Record<string, unknown>) };
  delete aps.sound;
  aps["interruption-level"] = "passive";
  return { ...payload, aps };
}

/** Does this device want the alert at all? Org and severity floors drop it; quiet hours only soften it. */
export function wanted(prefs: Prefs | undefined, orgId: number, severity: string | undefined): boolean {
  if (!prefs) return true;
  if (Array.isArray(prefs.orgs) && prefs.orgs.length > 0 && !prefs.orgs.includes(orgId)) return false;
  return meets(severity, prefs.minSeverity);
}

/** Inside quiet hours and not a page the device asked to hear anyway. */
export function softened(prefs: Prefs | undefined, severity: string | undefined, now: Date): boolean {
  if (!prefs?.quiet || !inQuietHours(prefs.quiet, now)) return false;
  return !(level(severity) === "page" && prefs.quiet.allowPage !== false);
}

/** Dedupe key: one push per org, fingerprint, state and start time. Fingerprints are hashes of the labels, so
 *  two orgs with the same rule and labels collide without the org in front. */
export function sentKey(a: GrafanaAlert, orgId: number): string {
  return `sent/${orgId}:${a.fingerprint}:${a.status}:${a.startsAt ?? ""}`;
}

export async function deliver(env: Env, wh: GrafanaWebhook, now = new Date()): Promise<Outcome> {
  const out: Outcome = { received: wh.alerts.length, pushed: 0, skipped: 0, unrouted: 0, filtered: 0, quiet: 0, dropped: 0, failed: 0, apns: apnsConfigured(env) };
  const routes = parseRoutes(env.ROUTES);
  const orgs = parseOrgs(env.ORGS);
  const cfg = apnsSource(env);

  for (const alert of wh.alerts) {
    const orgId = orgOf(alert, wh);
    if (await env.DEVICES.get(sentKey(alert, orgId))) {
      out.skipped++;
      continue;
    }
    const users = routeUsers(routes, alert.labels);
    if (users.length === 0) {
      out.unrouted++;
      continue;
    }
    if (!cfg) continue; // accepted, nothing to send with yet
    const payload = buildPayload(alert, wh.externalURL, orgId, orgs[String(orgId)]);
    const severity = alert.labels.severity;
    let accepted = 0;
    for (const name of users) {
      const user = await resolveUser(env.DEVICES, name);
      for (const device of await listDevices(env.DEVICES, user)) {
        if (!wanted(device.prefs, orgId, severity)) {
          out.filtered++;
          continue;
        }
        const soft = softened(device.prefs, severity, now);
        let r;
        try {
          r = await sendPush(cfg, device.token, device.environment, { collapseId: alert.fingerprint, payload: soft ? quieten(payload) : payload });
        } catch (e) {
          // No provider token (the grant refused or is down) or Apple unreachable: the device is kept, the send is a failure.
          out.failed++;
          console.log(`push failed for ${user} ${device.name}: ${(e as Error).message}`);
          continue;
        }
        if (r.status === 200) {
          accepted++;
          out.pushed++;
          if (soft) out.quiet++;
        } else if (r.drop) {
          out.dropped++;
          await removeDevice(env.DEVICES, user, device.token);
          console.log(`drop ${user} ${device.name}: ${r.status} ${r.reason ?? ""}`);
        } else {
          out.failed++;
          console.log(`apns ${r.status} ${r.reason ?? ""} for ${user} ${device.name}`);
        }
      }
    }
    if (accepted > 0) await env.DEVICES.put(sentKey(alert, orgId), "1", { expirationTtl: SENT_TTL_SECONDS });
  }
  return out;
}
