import assert from "node:assert/strict";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";

function parsePositiveInteger(value, label) {
  const normalized = String(value ?? "").trim();
  if (!/^[1-9][0-9]*$/.test(normalized)) {
    throw new Error(`${label} must be a positive integer.`);
  }
  return Number(normalized);
}

export function evaluateBuildNumber(candidateValue, existingValues) {
  const candidate = parsePositiveInteger(candidateValue, "Candidate build number");
  const existing = existingValues
    .map((value) => String(value ?? "").trim())
    .filter((value) => /^[1-9][0-9]*$/.test(value))
    .map(Number);

  if (existing.includes(candidate)) {
    throw new Error(`Build ${candidate} already exists in App Store Connect.`);
  }

  const latest = existing.length === 0 ? null : Math.max(...existing);
  if (latest !== null && candidate <= latest) {
    throw new Error(
      `Build ${candidate} is not newer than App Store Connect build ${latest}.`,
    );
  }

  return { candidate, latest };
}

function base64URL(value) {
  return Buffer.from(value).toString("base64url");
}

function createAppStoreConnectToken({ keyID, issuerID, privateKey }) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: keyID, typ: "JWT" }));
  const payload = base64URL(
    JSON.stringify({
      iss: issuerID,
      iat: now - 30,
      exp: now + 10 * 60,
      aud: "appstoreconnect-v1",
    }),
  );
  const signingInput = `${header}.${payload}`;
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${base64URL(signature)}`;
}

async function fetchExistingBuildNumbers({ appID, token }) {
  const initialURL = new URL("https://api.appstoreconnect.apple.com/v1/builds");
  initialURL.searchParams.set("filter[app]", appID);
  initialURL.searchParams.set("sort", "-uploadedDate");
  initialURL.searchParams.set("limit", "200");

  const versions = [];
  let nextURL = initialURL.toString();
  while (nextURL) {
    const response = await fetch(nextURL, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) {
      throw new Error(
        `App Store Connect build lookup failed with HTTP ${response.status}.`,
      );
    }

    const payload = await response.json();
    for (const build of payload.data ?? []) {
      versions.push(build.attributes?.version);
    }
    nextURL = payload.links?.next ?? null;
  }
  return versions;
}

function requiredEnvironment(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}.`);
  }
  return value;
}

function runSelfTest() {
  assert.deepEqual(evaluateBuildNumber("14", ["13", "12"]), {
    candidate: 14,
    latest: 13,
  });
  assert.throws(
    () => evaluateBuildNumber("13", ["13", "12"]),
    /already exists/,
  );
  assert.throws(
    () => evaluateBuildNumber("12", ["13", "12"]),
    /already exists/,
  );
  assert.throws(
    () => evaluateBuildNumber("11", ["13", "12"]),
    /not newer/,
  );
  assert.throws(() => evaluateBuildNumber("1.4", ["13"]), /positive integer/);
  console.log("TestFlight build-number guard self-test passed.");
}

async function main() {
  if (process.argv[2] === "--self-test") {
    runSelfTest();
    return;
  }

  const candidate = process.argv[2];
  const keyID = requiredEnvironment("APP_STORE_CONNECT_API_KEY_ID");
  const issuerID = requiredEnvironment("APP_STORE_CONNECT_API_ISSUER_ID");
  const appID = requiredEnvironment("APP_STORE_CONNECT_APP_ID");
  const privateKey = Buffer.from(
    requiredEnvironment("APP_STORE_CONNECT_API_KEY_BASE64"),
    "base64",
  ).toString("utf8");

  const token = createAppStoreConnectToken({ keyID, issuerID, privateKey });
  const existing = await fetchExistingBuildNumbers({ appID, token });
  const result = evaluateBuildNumber(candidate, existing);
  const prior = result.latest === null ? "none" : String(result.latest);
  console.log(
    `Verified candidate Build ${result.candidate}; latest App Store Connect build is ${prior}.`,
  );
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
