/** ROUTES: a JSON object of label matchers to users. `"site=meade-manor": "dmeade"`, `"host=~ovh|oc-.*": ["a","b"]`,
 *  and `"*"` for the default owner. Usernames are compared lower case. */

export type Routes = Array<{ label: string; test: (value: string | undefined) => boolean; users: string[] }> & {
  fallback: string[];
};

function users(v: unknown): string[] {
  const list = Array.isArray(v) ? v : [v];
  return list.filter((u): u is string => typeof u === "string" && u.length > 0).map((u) => u.toLowerCase());
}

export function parseRoutes(raw: string | undefined): Routes {
  const routes = [] as unknown as Routes;
  routes.fallback = [];
  if (!raw) return routes;
  let obj: Record<string, unknown>;
  try {
    obj = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new Error("ROUTES is not JSON");
  }
  for (const [matcher, target] of Object.entries(obj)) {
    if (matcher === "*") {
      routes.fallback = users(target);
      continue;
    }
    const re = /^([A-Za-z_][A-Za-z0-9_]*)(=~|=)(.*)$/.exec(matcher);
    if (!re) throw new Error(`ROUTES matcher "${matcher}" is not label=value or label=~regex`);
    const [, label, op, value] = re;
    const test =
      op === "=~"
        ? ((rx) => (v: string | undefined) => v !== undefined && rx.test(v))(new RegExp(`^(?:${value})$`))
        : (v: string | undefined) => v === value;
    routes.push({ label, test, users: users(target) });
  }
  return routes;
}

/** Users who should hear about an alert with these labels. First matching route wins; else the default owner. */
export function routeUsers(routes: Routes, labels: Record<string, string>): string[] {
  for (const r of routes) {
    if (r.test(labels[r.label])) return [...new Set(r.users)];
  }
  return [...new Set(routes.fallback)];
}
