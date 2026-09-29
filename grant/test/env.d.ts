import type { Env as GrantEnv } from "../src/env";

declare global {
  namespace Cloudflare {
    interface Env extends GrantEnv {}
  }
}
