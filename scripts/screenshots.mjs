#!/usr/bin/env node
// Uploads App Store screenshots: node scripts/screenshots.mjs <dir>  where <dir> holds iphone69/ and ipad13/
// with NN-name.png files (1320×2868 and 2064×2752). Replaces each display type's set on the iOS version's
// en-US localization. Apple's display type for the 6.9-inch iPhone is APP_IPHONE_67; for the 13-inch iPad
// APP_IPAD_PRO_3GEN_129.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { call } from "/root/.config/brazier/asc.mjs";

const APP = "6817156133";
const dir = process.argv[2];
if (!dir) throw new Error("usage: screenshots.mjs <dir>");
const SETS = { iphone69: "APP_IPHONE_67", ipad13: "APP_IPAD_PRO_3GEN_129" };

async function must(method, path, body, opts) {
  const { status, body: out } = await call(method, path, body, opts);
  if (status >= 300) throw new Error(`${method} ${path} → ${status} ${JSON.stringify(out).slice(0, 500)}`);
  return out;
}
const app = await must("GET", `/v1/apps/${APP}?include=appStoreVersions&fields[appStoreVersions]=platform,versionString`);
const version = app.included.find((i) => i.type === "appStoreVersions" && i.attributes.platform === "IOS");
const locs = await must("GET", `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`);
const loc = locs.data.find((l) => l.attributes.locale === "en-US");
const existing = await must("GET", `/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`);

for (const [folder, displayType] of Object.entries(SETS)) {
  let files;
  try { files = readdirSync(join(dir, folder)).filter((f) => f.endsWith(".png")).sort(); } catch { console.log(`${folder}: no folder, skipped`); continue; }
  if (files.length === 0) { console.log(`${folder}: empty, skipped`); continue; }
  const old = existing.data.find((s) => s.attributes.screenshotDisplayType === displayType);
  if (old) { await must("DELETE", `/v1/appScreenshotSets/${old.id}`); console.log(`${displayType}: removed the old set`); }
  const set = await must("POST", "/v1/appScreenshotSets", { data: { type: "appScreenshotSets", attributes: { screenshotDisplayType: displayType },
    relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc.id } } } } });
  const ids = [];
  for (const file of files) {
    const path = join(dir, folder, file);
    const data = readFileSync(path);
    const shot = await must("POST", "/v1/appScreenshots", { data: { type: "appScreenshots", attributes: { fileName: file, fileSize: statSync(path).size },
      relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set.data.id } } } } });
    for (const op of shot.data.attributes.uploadOperations) {
      const chunk = data.subarray(op.offset, op.offset + op.length);
      const headers = Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value]));
      const res = await fetch(op.url, { method: op.method, headers, body: chunk });
      if (!res.ok) throw new Error(`upload ${file} chunk at ${op.offset}: ${res.status}`);
    }
    await must("PATCH", `/v1/appScreenshots/${shot.data.id}`, { data: { type: "appScreenshots", id: shot.data.id, attributes: { uploaded: true, sourceFileChecksum: createHash("md5").update(data).digest("hex") } } });
    ids.push(shot.data.id);
    console.log(`${displayType}: ${file} uploaded (${data.length} bytes)`);
  }
  // Wait for Apple to accept every file.
  for (const id of ids) {
    for (let i = 0; i < 30; i++) {
      const s = await must("GET", `/v1/appScreenshots/${id}?fields[appScreenshots]=assetDeliveryState,fileName`);
      const st = s.data.attributes.assetDeliveryState;
      if (st.state === "COMPLETE") { console.log(`  ${s.data.attributes.fileName}: complete`); break; }
      if (st.state === "FAILED") throw new Error(`${s.data.attributes.fileName}: ${JSON.stringify(st.errors)}`);
      await new Promise((r) => setTimeout(r, 4000));
    }
  }
}
console.log("done");
