#!/usr/bin/env node
// Writes TestFlight's "What to Test" for one build: node scripts/testflight-notes.mjs <build number> <notes file>
// The notes go to the build's en-US beta build localization (created if missing). Never submits anything.
import { readFileSync } from "node:fs";
import { call } from "/root/.config/brazier/asc.mjs";
const APP = "6817156133";
const [buildNumber, file] = process.argv.slice(2);
if (!buildNumber || !file) throw new Error("usage: testflight-notes.mjs <build number> <notes file>");
const whatsNew = readFileSync(file, "utf8").trim().slice(0, 4000);
async function must(method, path, body) {
  const { status, body: out } = await call(method, path, body);
  if (status >= 300) throw new Error(`${method} ${path} → ${status} ${JSON.stringify(out).slice(0, 400)}`);
  return out;
}
const builds = await must("GET", `/v1/builds?filter[app]=${APP}&filter[version]=${buildNumber}&limit=5&fields[builds]=version,processingState`);
const build = builds.data[0];
if (!build) throw new Error(`no build ${buildNumber}`);
const locs = await must("GET", `/v1/builds/${build.id}/betaBuildLocalizations?fields[betaBuildLocalizations]=locale,whatsNew`);
let loc = locs.data.find((l) => l.attributes.locale === "en-US");
if (loc) {
  await must("PATCH", `/v1/betaBuildLocalizations/${loc.id}`, { data: { type: "betaBuildLocalizations", id: loc.id, attributes: { whatsNew } } });
} else {
  loc = (await must("POST", "/v1/betaBuildLocalizations", { data: { type: "betaBuildLocalizations", attributes: { locale: "en-US", whatsNew }, relationships: { build: { data: { type: "builds", id: build.id } } } } })).data;
}
console.log(`build ${buildNumber} (${build.attributes.processingState}): what to test set, ${whatsNew.length} chars`);
