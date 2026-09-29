// Hand probe: does a dashboard page accept a Bearer token / a JWT header, and does ?auth_token= set a session cookie?
import { api, base } from "./lib.mjs";
import { readFileSync } from "node:fs"; import { createSign } from "node:crypto"; import { join } from "node:path";
function idToken(claims){ const key=readFileSync(join(process.env.CONTRACT_WORK,"key.pem"),"utf8"); const b64=o=>Buffer.from(typeof o==="string"?o:JSON.stringify(o)).toString("base64url"); const now=Math.floor(Date.now()/1000); const head=b64({alg:"ES256",kid:"contract",typ:"JWT"}); const body=b64({iss:"https://contract.invalid/",iat:now,exp:now+600,...claims}); const s=createSign("sha256"); s.update(`${head}.${body}`); s.end(); return `${head}.${body}.${s.sign({key,dsaEncoding:"ieee-p1363"}).toString("base64url")}`; }
const v = (await api("GET","/api/health")).json.version;
await api("POST", "/api/dashboards/db", { body: { dashboard: { title: "P", uid: "p1", panels: [] }, overwrite: true } });
const sa = await api("POST", "/api/serviceaccounts", { body: { name: "probe-sa", role: "Viewer" } });
const tok = (await api("POST", `/api/serviceaccounts/${sa.json.id}/tokens`, { body: { name: "t" } })).json.key;
async function page(label, headers, qs="") {
  const res = await fetch(`${base}/d/p1?orgId=1&kiosk${qs}`, { headers: { "User-Agent": "x", ...headers }, redirect: "manual" });
  const html = await res.text();
  const cookies = res.headers.getSetCookie().map(c=>c.split("=")[0]);
  console.log(`${v} ${label}: ${res.status} signedIn=${/"isSignedIn":(true|false)/.exec(html)?.[1]} login=${/"login":"([^"]*)"/.exec(html)?.[1]} location=${res.headers.get("location")??""} setCookie=${cookies}`);
}
await page("bearer page", { Authorization: `Bearer ${tok}` });
await page("jwt header page", { "X-JWT-Assertion": idToken({ sub: "contract-jwt", email: "jwt@contract.invalid" }) });
await page("url_login page", {}, `&auth_token=${idToken({ sub: "contract-jwt", email: "jwt@contract.invalid" })}`);
const ds = await api("GET", "/api/search?type=dash-db", { auth: `Bearer ${tok}` }); console.log(`${v} bearer api: ${ds.status}`);
