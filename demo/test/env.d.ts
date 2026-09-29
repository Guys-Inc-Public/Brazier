import type { Env as DemoEnv } from "../src/index";

declare global {
  namespace Cloudflare {
    interface Env extends DemoEnv {}
  }
}
