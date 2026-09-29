/** Turn a Grafana webhook payload into pushes: dedupe, route, send, drop dead devices. */
import type { Env } from "./env";
import { SENT_TTL_SECONDS, apnsConfigured } from "./env";
import { parseRoutes, routeUsers } from "./routing";
import { listDevices, removeDevice, resolveUser } from "./devices";
import { sendPush, type ApnsConfig } from "./apns";

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
}

export interface GrafanaWebhook {
  receiver?: string;
  status?: string;
  alerts: GrafanaAlert[];
  externalURL?: string;
  groupKey?: string;
  version?: string;
}

export interface Outcome {
  received: number;
  pushed: number;
  skipped: number;
  unrouted: number;
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

/** The lock-screen text and the data the app needs to open and silence the alert. */
export function buildPayload(alert: GrafanaAlert, externalURL: string | undefined): Record<string, unknown> {
  const l = alert.labels;
  const an = alert.annotations ?? {};
  const name = l.alertname ?? "Alert";
  const firstPair = Object.entries(l).find(([k]) => k !== "alertname" && k !== "grafana_folder");
  const summary = an.summary ?? (firstPair ? `${firstPair[0]}=${firstPair[1]}` : "");
  const resolved = alert.status === "resolved";
  const where = [l.site, l.host].filter(Boolean).join(" · ");
  const page = l.severity === "page" && !resolved;
  return {
    aps: {
      alert: {
        title: resolved ? `Resolved: ${name}` : name,
        subtitle: where || undefined,
        body: summary,
      },
      sound: resolved ? undefined : "default",
      "thread-id": l.grafana_folder ?? "alerts",
      category: "ALERT",
      "interruption-level": page ? "time-sensitive" : "active",
      "relevance-score": page ? 1 : resolved ? 0.2 : 0.6,
    },
    brazier: {
      fingerprint: alert.fingerprint,
      status: alert.status,
      alertname: name,
      labels: l,
      annotations: an,
      startsAt: alert.startsAt,
      endsAt: alert.endsAt,
      generatorURL: alert.generatorURL,
      silenceURL: alert.silenceURL,
      externalURL,
      folder: l.grafana_folder,
    },
  };
}

function sentKey(a: GrafanaAlert): string {
  return `sent/${a.fingerprint}:${a.status}:${a.startsAt ?? ""}`;
}

export async function deliver(env: Env, wh: GrafanaWebhook): Promise<Outcome> {
  const out: Outcome = { received: wh.alerts.length, pushed: 0, skipped: 0, unrouted: 0, dropped: 0, failed: 0, apns: apnsConfigured(env) };
  const routes = parseRoutes(env.ROUTES);
  const cfg: ApnsConfig | null = out.apns
    ? { key: env.APNS_KEY as string, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC }
    : null;

  for (const alert of wh.alerts) {
    if (await env.DEVICES.get(sentKey(alert))) {
      out.skipped++;
      continue;
    }
    const users = routeUsers(routes, alert.labels);
    if (users.length === 0) {
      out.unrouted++;
      continue;
    }
    if (!cfg) continue; // accepted, nothing to send with yet
    const payload = buildPayload(alert, wh.externalURL);
    let accepted = 0;
    for (const name of users) {
      const user = await resolveUser(env.DEVICES, name);
      for (const device of await listDevices(env.DEVICES, user)) {
        const r = await sendPush(cfg, device.token, device.environment, { collapseId: alert.fingerprint, payload });
        if (r.status === 200) {
          accepted++;
          out.pushed++;
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
    if (accepted > 0) await env.DEVICES.put(sentKey(alert), "1", { expirationTtl: SENT_TTL_SECONDS });
  }
  return out;
}
