/** Test-only crypto: an RSA key pair to play Keystone, a P-256 key to play our APNs key. */

const enc = new TextEncoder();

export function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export interface Issuer {
  jwks: { keys: JsonWebKey[] };
  sign: (claims: Record<string, unknown>, kid?: string) => Promise<string>;
}

export async function makeIssuer(kid = "test-key"): Promise<Issuer> {
  const pair = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const pub = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
  const jwks = { keys: [{ kty: pub.kty, n: pub.n, e: pub.e, alg: "RS256", use: "sig", kid }] };
  return {
    jwks,
    async sign(claims, useKid = kid) {
      const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", kid: useKid, typ: "JWT" })));
      const body = b64url(enc.encode(JSON.stringify(claims)));
      const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, enc.encode(`${header}.${body}`));
      return `${header}.${body}.${b64url(new Uint8Array(sig))}`;
    },
  };
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
