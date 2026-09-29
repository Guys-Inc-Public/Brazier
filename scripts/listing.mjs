#!/usr/bin/env node
// Writes docs/reference/listing.md to App Store Connect. Idempotent: every call is a PATCH or a create-once.
//   node scripts/listing.mjs            # everything but the demo account
//   DEMO_USER=… DEMO_PASSWORD=… node scripts/listing.mjs   # also the review demo account
import { readFileSync } from "node:fs";
import { call } from "/root/.config/brazier/asc.mjs";

const APP = "6817156133";
const md = readFileSync(new URL("../docs/reference/listing.md", import.meta.url), "utf8");
const section = (name) => {
  const m = new RegExp(`^## ${name}\\n+([\\s\\S]*?)(?=\\n## |$)`, "m").exec(md);
  if (!m) throw new Error(`no section ${name}`);
  return m[1].trim();
};
const limit = (name, text, max) => { if (text.length > max) throw new Error(`${name} is ${text.length} chars, max ${max}`); return text; };

async function must(method, path, body) {
  const { status, body: out } = await call(method, path, body);
  if (status >= 300) throw new Error(`${method} ${path} → ${status} ${JSON.stringify(out).slice(0, 400)}`);
  return out;
}

// The version and info records this listing fills.
const app = await must("GET", `/v1/apps/${APP}?include=appInfos,appStoreVersions&fields[appStoreVersions]=platform,versionString,appVersionState&fields[appInfos]=state`);
const version = app.included.find((i) => i.type === "appStoreVersions" && i.attributes.platform === "IOS");
const info = app.included.find((i) => i.type === "appInfos");
console.log(`iOS version ${version.attributes.versionString} (${version.attributes.appVersionState}), appInfo ${info.id}`);

// 1. App info localization: subtitle and privacy policy.
const infoLocs = await must("GET", `/v1/appInfos/${info.id}/appInfoLocalizations`);
const infoLoc = infoLocs.data.find((l) => l.attributes.locale === "en-US");
await must("PATCH", `/v1/appInfoLocalizations/${infoLoc.id}`, { data: { type: "appInfoLocalizations", id: infoLoc.id, attributes: {
  subtitle: limit("subtitle", section("Subtitle"), 30), privacyPolicyUrl: section("Privacy policy URL") } } });
console.log("app info localization: subtitle, privacy URL");

// 2. Categories.
const [primary, secondary] = section("Categories").split(",").map((s) => s.trim());
await must("PATCH", `/v1/appInfos/${info.id}`, { data: { type: "appInfos", id: info.id, relationships: {
  primaryCategory: { data: { type: "appCategories", id: primary } }, secondaryCategory: { data: { type: "appCategories", id: secondary } } } } });
console.log(`categories: ${primary}, ${secondary}`);

// 3. Age rating: nothing applies. The attribute set changes over time, so read it and answer every key
// with its "none": enums get NONE, booleans false; overrides NONE; Korea/GRAC and the info URL are left alone.
{
  const decl = await must("GET", `/v1/appInfos/${info.id}/ageRatingDeclaration`);
  const attrs = {};
  const booleans = new Set(["gambling", "unrestrictedWebAccess", "lootBox", "advertising", "messagingAndChat", "userGeneratedContent", "parentalControls",
    "healthOrWellnessTopics", "ageAssurance", "socialMedia", "socialMediaAgeRestricted", "seventeenPlus"]);
  const skip = new Set(["kidsAgeBand", "koreaAgeRatingOverride", "gracRatingClassificationNumber", "developerAgeRatingInfoUrl", "ageRatingOverride"]);
  for (const k of Object.keys(decl.data.attributes)) {
    if (skip.has(k)) continue;
    attrs[k] = booleans.has(k) ? false : "NONE";
  }
  await must("PATCH", `/v1/ageRatingDeclarations/${decl.data.id}`, { data: { type: "ageRatingDeclarations", id: decl.data.id, attributes: attrs } });
  console.log(`age rating: none (${Object.keys(attrs).length} answers)`);
}

// 4. Version text.
const locs = await must("GET", `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`);
const loc = locs.data.find((l) => l.attributes.locale === "en-US");
{
  const attributes = {
    description: limit("description", section("Description"), 4000),
    keywords: limit("keywords", section("Keywords"), 100),
    promotionalText: limit("promotional text", section("Promotional text"), 170),
    supportUrl: section("Support URL"), marketingUrl: section("Marketing URL"),
  };
  // "What's new" exists only from the second version on; Apple refuses it on a first release.
  const withNews = await call("PATCH", `/v1/appStoreVersionLocalizations/${loc.id}`, { data: { type: "appStoreVersionLocalizations", id: loc.id, attributes: { ...attributes, whatsNew: section("What's new") } } });
  if (withNews.status >= 300) {
    await must("PATCH", `/v1/appStoreVersionLocalizations/${loc.id}`, { data: { type: "appStoreVersionLocalizations", id: loc.id, attributes } });
    console.log("version text: description, keywords, promotional, URLs (what's new not editable on a first release)");
  } else console.log("version text: description, keywords, promotional, what's new, URLs");
}

// 5. Version attributes: copyright, manual release.
await must("PATCH", `/v1/appStoreVersions/${version.id}`, { data: { type: "appStoreVersions", id: version.id, attributes: { copyright: section("Copyright"), releaseType: "MANUAL" } } });
console.log("version: copyright, manual release");

// 6. Content rights.
await must("PATCH", `/v1/apps/${APP}`, { data: { type: "apps", id: APP, attributes: { contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT" } } });
console.log("content rights: no third-party content");

// 7. Price: free, base USA. Create once.
{
  const { status } = await call("GET", `/v1/apps/${APP}/appPriceSchedule`);
  if (status === 404) {
    const points = await must("GET", `/v1/apps/${APP}/appPricePoints?filter[territory]=USA&limit=1`);
    const free = points.data.find((p) => p.attributes.customerPrice === "0.0") ?? points.data[0];
    await must("POST", "/v1/appPriceSchedules", {
      data: { type: "appPriceSchedules", relationships: { app: { data: { type: "apps", id: APP } }, baseTerritory: { data: { type: "territories", id: "USA" } }, manualPrices: { data: [{ type: "appPrices", id: "${free}" }] } } },
      included: [{ type: "appPrices", id: "${free}", attributes: { startDate: null }, relationships: { appPricePoint: { data: { type: "appPricePoints", id: free.id } } } }],
    });
    console.log("price: free, base USA");
  } else console.log("price: already scheduled");
}

// 8. Availability: every territory, including new ones. Create once.
{
  const { status } = await call("GET", `/v1/apps/${APP}/appAvailabilityV2`);
  if (status === 404) {
    const territories = await must("GET", "/v1/territories?limit=200");
    const ids = territories.data.map((t) => t.id);
    await must("POST", "/v2/appAvailabilities", {
      data: { type: "appAvailabilities", attributes: { availableInNewTerritories: true }, relationships: { app: { data: { type: "apps", id: APP } },
        territoryAvailabilities: { data: ids.map((id) => ({ type: "territoryAvailabilities", id: `\${${id}}` })) } } },
      included: ids.map((id) => ({ type: "territoryAvailabilities", id: `\${${id}}`, attributes: { available: true }, relationships: { territory: { data: { type: "territories", id } } } })),
    });
    console.log(`availability: ${ids.length} territories`);
  } else console.log("availability: already set");
}

// 9. Review detail: contact, notes, demo account. Apple requires a phone number to create it, so this
// step runs only with REVIEW_PHONE set (CJ's, never written down here); DEMO_USER/DEMO_PASSWORD add the account.
if (process.env.REVIEW_PHONE) {
  const attributes = { contactFirstName: "Cameron", contactLastName: "Jackson", contactEmail: "CJ@guysinc.org", contactPhone: process.env.REVIEW_PHONE,
    notes: limit("review notes", section("Review notes"), 4000), demoAccountRequired: true };
  if (process.env.DEMO_USER) { attributes.demoAccountName = process.env.DEMO_USER; attributes.demoAccountPassword = process.env.DEMO_PASSWORD; }
  const existing = await must("GET", `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`);
  if (existing.data) await must("PATCH", `/v1/appStoreReviewDetails/${existing.data.id}`, { data: { type: "appStoreReviewDetails", id: existing.data.id, attributes } });
  else await must("POST", "/v1/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes, relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version.id } } } } });
  console.log(`review detail: contact, notes${process.env.DEMO_USER ? ", demo account" : ""}`);
} else console.log("review detail: skipped, set REVIEW_PHONE (and DEMO_USER/DEMO_PASSWORD) to file it");
console.log("done");
