/** Test-only crypto: a P-256 key to play our APNs key, and a Grafana webhook fixture. */

const enc = new TextEncoder();

export function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** A PKCS#8 PEM for a fresh P-256 key, shaped like Apple's .p8 file. */
export async function makeApnsKeyPem(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let s = "";
  for (const b of der) s += String.fromCharCode(b);
  const b64 = btoa(s).replace(/(.{64})/g, "$1\n");
  return `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`;
}

/** A Grafana webhook body with one or more alerts, in the shape Grafana 13.2 sends (see grafana-webhook-capture.log). */
export function grafanaWebhook(alerts: Array<Partial<GrafanaAlertFixture>>, receiver = "brazier"): Record<string, unknown> {
  const full = alerts.map((a, i) => ({
    status: "firing",
    labels: { alertname: "Disk above 85 percent", grafana_folder: "Estate", host: "mitochondria", severity: "page", site: "home" },
    annotations: { summary: "mitochondria /mnt/Plex1 is over 85% full" },
    startsAt: "2026-09-28T23:53:50Z",
    endsAt: "0001-01-01T00:00:00Z",
    generatorURL: "https://grafana.gicloud.org/alerting/grafana/estate-disk-filling/view?orgId=1",
    fingerprint: `b69ade466fb0e99${i}`,
    silenceURL: "https://grafana.gicloud.org/alerting/silence/new?alertmanager=grafana&matcher=host%3Dmitochondria",
    ...a,
  }));
  return {
    receiver,
    status: full.some((a) => a.status === "firing") ? "firing" : "resolved",
    alerts: full,
    groupLabels: {},
    commonLabels: {},
    commonAnnotations: {},
    externalURL: "https://grafana.gicloud.org/",
    appVersion: "13.2.1",
    version: "1",
    groupKey: "{}:{alertname=\"Disk above 85 percent\"}",
    truncatedAlerts: 0,
    orgId: 1,
    title: "[FIRING:1] Disk above 85 percent",
    state: "alerting",
    message: "",
  };
}

export interface GrafanaAlertFixture {
  status: "firing" | "resolved";
  labels: Record<string, string>;
  annotations: Record<string, string>;
  startsAt: string;
  endsAt: string;
  generatorURL: string;
  fingerprint: string;
  silenceURL: string;
}
