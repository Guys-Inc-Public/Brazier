/** brazier-demo: the public face of the demo Grafana. Every request is forwarded to the box that runs
 *  it with the key its gate insists on, so the box's port is useless to anyone else. Two paths are
 *  answered here: /.well-known/brazier (the relay's discovery document, so the app finds the relay
 *  from the demo address alone) and robots.txt. */
export interface Env {
  ORIGIN: string;
  RELAY_URL: string;
  DEMO_KEY?: string;
}

export const HOST = "demo.brazier.gicloud.org";

function text(body: string, status = 200): Response {
  return new Response(body, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}

async function wellKnown(env: Env): Promise<Response> {
  try {
    const r = await fetch(`${env.RELAY_URL.replace(/\/+$/, "")}/.well-known/brazier`, {
      headers: { "user-agent": "brazier-demo", accept: "application/json" },
    });
    return new Response(r.body, {
      status: r.status,
      headers: {
        "content-type": r.headers.get("content-type") ?? "application/json; charset=utf-8",
        "cache-control": "public, max-age=300",
        "access-control-allow-origin": "*",
      },
    });
  } catch {
    return text("The relay's discovery document is not reachable right now.\n", 502);
  }
}

async function proxy(req: Request, env: Env): Promise<Response> {
  if (!env.DEMO_KEY) return text("The demo has no DEMO_KEY set.\n", 503);
  const url = new URL(req.url);
  const target = new URL(env.ORIGIN);
  target.pathname = url.pathname;
  target.search = url.search;
  const headers = new Headers(req.headers);
  headers.set("x-demo-key", env.DEMO_KEY);
  headers.set("x-forwarded-proto", "https");
  headers.set("x-forwarded-host", HOST);
  const body = req.method === "GET" || req.method === "HEAD" ? undefined : req.body;
  try {
    const r = await fetch(target.toString(), { method: req.method, headers, body, redirect: "manual" });
    return new Response(r.body, { status: r.status, statusText: r.statusText, headers: r.headers });
  } catch {
    return text("The demo Grafana is not reachable right now.\n", 502);
  }
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    if (req.method === "GET" && path === "/robots.txt") return text("User-agent: *\nDisallow: /\n");
    if (req.method === "GET" && path === "/.well-known/brazier") return wellKnown(env);
    return proxy(req, env);
  },
} satisfies ExportedHandler<Env>;
