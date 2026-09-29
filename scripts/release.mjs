#!/usr/bin/env node
// Attaches the newest processed TestFlight build of the store version to that version, and prints what
// still stands between it and Submit. Never submits: node scripts/release.mjs
import { call } from "/root/.config/brazier/asc.mjs";
const APP = "6817156133";
async function must(method, path, body) {
  const { status, body: out } = await call(method, path, body);
  if (status >= 300) throw new Error(`${method} ${path} → ${status} ${JSON.stringify(out).slice(0, 500)}`);
  return out;
}
const app = await must("GET", `/v1/apps/${APP}?include=appStoreVersions&fields[appStoreVersions]=platform,versionString,appVersionState`);
const version = app.included.find((i) => i.type === "appStoreVersions" && i.attributes.platform === "IOS");
const builds = await must("GET", `/v1/builds?filter[app]=${APP}&filter[preReleaseVersion.version]=${version.attributes.versionString}&sort=-uploadedDate&limit=5&fields[builds]=version,processingState,uploadedDate,expired`);
const ready = builds.data.find((b) => b.attributes.processingState === "VALID" && !b.attributes.expired);
console.log(`store version ${version.attributes.versionString} (${version.attributes.appVersionState}); builds of it: ${builds.data.map((b) => `${b.attributes.version}:${b.attributes.processingState}`).join(", ") || "none"}`);
if (!ready) { console.log("no processed build to attach yet"); process.exit(0); }
await must("PATCH", `/v1/appStoreVersions/${version.id}/relationships/build`, { data: { type: "builds", id: ready.id } });
console.log(`attached build ${ready.attributes.version} to version ${version.attributes.versionString}`);
const detail = await must("GET", `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`);
const sets = await must("GET", `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?include=appScreenshotSets`);
const shots = (sets.included ?? []).map((s) => s.attributes.screenshotDisplayType);
console.log(`review detail: ${detail.data ? "filed" : "MISSING (REVIEW_PHONE + demo account via scripts/listing.mjs)"}`);
console.log(`screenshot sets: ${shots.join(", ") || "none"}`);
console.log("still CJ's in the portal: App Privacy answers (Data Not Collected), then Submit for Review.");
