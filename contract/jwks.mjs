// Writes a fresh ES256 key pair for one run: jwks.json (mounted into Grafana) and key.pem (for the tests).
import { generateKeyPairSync } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
const dir = process.argv[2];
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwk = publicKey.export({ format: "jwk" });
writeFileSync(join(dir, "jwks.json"), JSON.stringify({ keys: [{ ...jwk, kid: "contract", use: "sig", alg: "ES256" }] }));
writeFileSync(join(dir, "key.pem"), privateKey.export({ format: "pem", type: "pkcs8" }));
