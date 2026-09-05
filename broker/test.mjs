import assert from "node:assert/strict";
import worker from "./src/index.js";

class MemoryKV {
  constructor() {
    this.rows = new Map();
  }

  async put(key, value) {
    this.rows.set(key, value);
  }

  async get(key, type) {
    const value = this.rows.get(key);
    if (value === undefined) return null;
    return type === "json" ? JSON.parse(value) : value;
  }

  async delete(key) {
    this.rows.delete(key);
  }
}

const kv = new MemoryKV();
const env = {
  COINBASE_CLIENT_ID: "test-client",
  COINBASE_CLIENT_SECRET: "test-secret",
  SESSIONS: kv,
};

async function request(path, init = {}) {
  return worker.fetch(new Request(`https://broker.example${path}`, init), env);
}

let response = await request("/health");
assert.equal(response.status, 200);
assert.equal(response.headers.get("cache-control"), "no-store");
assert.equal(response.headers.get("x-content-type-options"), "nosniff");

assert.equal((await request("/oauth/start")).status, 404);
response = await request("/oauth/start", { method: "POST" });
assert.equal(response.status, 200);
const started = await response.json();
assert.match(started.session_id, /^[A-Za-z0-9_-]{43}$/);
const authorize = new URL(started.authorize_url);
const state = authorize.searchParams.get("state");
assert.match(state, /^[A-Za-z0-9_-]{24}$/);
assert.notEqual(state, started.session_id);
assert.equal(authorize.origin, "https://login.coinbase.com");
assert.equal(
  authorize.searchParams.get("scope"),
  "wallet:user:read,wallet:accounts:read,offline_access",
);

assert.equal((await request(`/oauth/session/${started.session_id}`)).status, 404);
response = await request("/oauth/session", { method: "POST" });
assert.equal(response.status, 415);
response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: "x".repeat(17000) }),
});
assert.equal(response.status, 413);
response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: "not-valid" }),
});
assert.equal(response.status, 400);
response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: started.session_id }),
});
assert.equal(response.status, 202);
assert.deepEqual(await response.json(), { status: "pending" });

await kv.put(
  `oauth-session:${started.session_id}`,
  JSON.stringify({ status: "complete", access_token: "access", refresh_token: "refresh" }),
);
response = await request(`/oauth/callback?state=${state}&code=replay`);
assert.equal(response.status, 200);
assert.match(await response.text(), /already been used/);
assert.equal((await kv.get(`oauth-session:${started.session_id}`, "json")).access_token, "access");
assert.equal(await kv.get(`oauth-state:${state}`, "json"), null);

response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: started.session_id }),
});
assert.equal(response.status, 200);
assert.equal((await response.json()).access_token, "access");
assert.equal(await kv.get(`oauth-session:${started.session_id}`, "json"), null);

response = await request("/oauth/start", { method: "POST" });
const denied = await response.json();
const deniedState = new URL(denied.authorize_url).searchParams.get("state");
response = await request(`/oauth/callback?state=${deniedState}&error=access_denied`);
assert.match(await response.text(), /access_denied/);
assert.equal(await kv.get(`oauth-state:${deniedState}`, "json"), null);
response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: denied.session_id }),
});
assert.equal(response.status, 400);
assert.equal((await response.json()).status, "error");

assert.equal((await request("/oauth/refresh", { method: "POST" })).status, 415);
assert.equal((await request("/oauth/revoke", { method: "POST" })).status, 415);
assert.equal((await request("/oauth/claim", { method: "POST" })).status, 404);
assert.equal((await request("/oauth/debug")).status, 404);

const blockedEnv = {
  ...env,
  OAUTH_START_LIMITER: { limit: async () => ({ success: false }) },
};
response = await worker.fetch(
  new Request("https://broker.example/oauth/start", { method: "POST" }),
  blockedEnv,
);
assert.equal(response.status, 429);
assert.equal(response.headers.get("retry-after"), "60");

console.log("broker security tests passed");
