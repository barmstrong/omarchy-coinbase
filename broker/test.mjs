import assert from "node:assert/strict";
import worker, { OAuthSession } from "./src/index.js";

class MemoryStorage {
  constructor() {
    this.rows = new Map();
    this.alarmAt = null;
  }

  async put(key, value) {
    this.rows.set(key, value);
  }

  async get(key) {
    return this.rows.get(key);
  }

  async delete(key) {
    this.rows.delete(key);
  }

  async setAlarm(when) {
    this.alarmAt = when;
  }

  async deleteAll() {
    this.rows.clear();
    this.alarmAt = null;
  }
}

class MemoryDurableObjects {
  constructor(env) {
    this.env = env;
    this.objects = new Map();
  }

  idFromName(name) {
    return { name };
  }

  object(name) {
    if (!this.objects.has(name)) {
      const storage = new MemoryStorage();
      const instance = new OAuthSession({ storage }, this.env);
      this.objects.set(name, { storage, instance });
    }
    return this.objects.get(name);
  }

  get(id) {
    const target = this.object(id.name);
    return { fetch: (url, init) => target.instance.fetch(new Request(url, init)) };
  }
}

const allowLimiter = { limit: async () => ({ success: true }) };
const env = {
  COINBASE_CLIENT_ID: "test-client",
  COINBASE_CLIENT_SECRET: "test-secret",
  OAUTH_START_LIMITER: allowLimiter,
  OAUTH_CALLBACK_LIMITER: allowLimiter,
  OAUTH_TOKEN_LIMITER: allowLimiter,
  OAUTH_SESSION_LIMITER: allowLimiter,
  OAUTH_SESSION_ID_LIMITER: allowLimiter,
  OAUTH_CREDENTIAL_LIMITER: allowLimiter,
};
const sessions = new MemoryDurableObjects(env);
env.OAUTH_SESSIONS = sessions;

async function request(path, init = {}) {
  return worker.fetch(new Request(`https://broker.example${path}`, init), env);
}

let response = await request("/health");
assert.equal(response.status, 200);
assert.equal(response.headers.get("cache-control"), "no-store");
assert.equal(response.headers.get("x-content-type-options"), "nosniff");
assert.match(response.headers.get("permissions-policy"), /payment=\(\)/);

response = await worker.fetch(
  new Request("https://broker.example/oauth/start", { method: "POST" }),
  { ...env, OAUTH_START_LIMITER: undefined },
);
assert.equal(response.status, 429);

assert.equal((await request("/oauth/start")).status, 404);
response = await request("/oauth/start", { method: "POST" });
assert.equal(response.status, 200);
const started = await response.json();
assert.match(started.session_id, /^[A-Za-z0-9_-]{43}\.[A-Za-z0-9_-]{43}$/);
const authorize = new URL(started.authorize_url);
const state = authorize.searchParams.get("state");
assert.match(state, /^[A-Za-z0-9_-]{43}$/);
assert.notEqual(state, started.session_id);
assert.equal(started.session_id.split(".")[0], state);
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
response = await worker.fetch(
  new Request("https://broker.example/oauth/session", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ session_id: started.session_id }),
  }),
  { ...env, OAUTH_SESSION_ID_LIMITER: undefined },
);
assert.equal(response.status, 429);
response = await worker.fetch(
  new Request(`https://broker.example/oauth/callback?state=${state}&code=blocked`, { method: "GET" }),
  { ...env, OAUTH_CALLBACK_LIMITER: undefined },
);
assert.equal(response.status, 429);

const replayStorage = sessions.object(state).storage;
const replayObject = sessions.object(state).instance;
const replayRow = await replayStorage.get("session");
await replayStorage.put("session", {
  ...replayRow,
  status: "ready",
});
replayObject.pendingTokens = {
  status: "complete",
  access_token: "access",
  refresh_token: "refresh",
};
response = await request(`/oauth/callback?state=${state}&code=replay`);
assert.equal(response.status, 200);
assert.match(await response.text(), /already been used/);
assert.equal((await replayStorage.get("session")).status, "ready");

response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: started.session_id }),
});
assert.equal(response.status, 200);
assert.equal((await response.json()).access_token, "access");
assert.equal(await replayStorage.get("session"), undefined);
response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: started.session_id }),
});
assert.equal(response.status, 404);

response = await request("/oauth/start", { method: "POST" });
const wrongOrigin = await response.json();
const wrongOriginState = new URL(wrongOrigin.authorize_url).searchParams.get("state");
response = await worker.fetch(
  new Request(`https://other.example/oauth/callback?state=${wrongOriginState}&code=wrong-origin`),
  env,
);
assert.match(await response.text(), /already been used/);
assert.equal(await sessions.object(wrongOriginState).storage.get("session"), undefined);

response = await request("/oauth/start", { method: "POST" });
const denied = await response.json();
const deniedState = new URL(denied.authorize_url).searchParams.get("state");
response = await request(`/oauth/callback?state=${deniedState}&error=access_denied`);
assert.match(await response.text(), /access_denied/);
response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: denied.session_id }),
});
assert.equal(response.status, 400);
assert.equal((await response.json()).status, "error");

// Alarms erase even an abandoned session, so no user credential state is
// retained beyond the short handoff window.
response = await request("/oauth/start", { method: "POST" });
const abandoned = await response.json();
const abandonedState = new URL(abandoned.authorize_url).searchParams.get("state");
await sessions.object(abandonedState).instance.alarm();
response = await request("/oauth/session", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ session_id: abandoned.session_id }),
});
assert.equal(response.status, 404);

// Cloudflare Workers does not implement redirect: "error". Use "manual" and
// reject redirects before OAuth credentials can be sent anywhere else.
response = await request("/oauth/start", { method: "POST" });
const redirected = await response.json();
const redirectedState = new URL(redirected.authorize_url).searchParams.get("state");
const nativeFetch = globalThis.fetch;
let redirectMode = "";
globalThis.fetch = async (_url, init) => {
  redirectMode = init.redirect;
  return new Response("", { status: 302, headers: { location: "https://example.invalid" } });
};
try {
  response = await request(`/oauth/callback?state=${redirectedState}&code=test-code`);
  assert.equal(redirectMode, "manual");
  assert.match(await response.text(), /token endpoint redirected unexpectedly/);

  response = await request("/oauth/revoke", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ access_token: "test-token" }),
  });
  assert.equal(redirectMode, "manual");
  assert.equal(response.status, 500);
  assert.equal((await response.json()).error, "revoke endpoint redirected unexpectedly");
} finally {
  globalThis.fetch = nativeFetch;
}

response = await request("/oauth/start", { method: "POST" });
const successful = await response.json();
const successfulState = new URL(successful.authorize_url).searchParams.get("state");
globalThis.fetch = async () =>
  Response.json({
    access_token: "successful-access",
    refresh_token: "successful-refresh",
    expires_in: 3600,
    token_type: "bearer",
    scope: "wallet:user:read,wallet:accounts:read,offline_access",
  });
try {
  const callbackResponse = request(`/oauth/callback?state=${successfulState}&code=test-code`);
  await new Promise((resolve) => setTimeout(resolve, 0));
  const durableRow = await sessions.object(successfulState).storage.get("session");
  assert.equal(durableRow.status, "ready");
  assert.equal(durableRow.access_token, undefined);
  assert.equal(durableRow.refresh_token, undefined);
  response = await request("/oauth/session", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ session_id: successful.session_id }),
  });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).refresh_token, "successful-refresh");
  assert.match(await (await callbackResponse).text(), /Signed in/);
  assert.equal(await sessions.object(successfulState).storage.get("session"), undefined);
} finally {
  globalThis.fetch = nativeFetch;
}

response = await request("/oauth/start", { method: "POST" });
const broadGrant = await response.json();
const broadGrantState = new URL(broadGrant.authorize_url).searchParams.get("state");
globalThis.fetch = async () =>
  Response.json({
    access_token: "over-scoped-access",
    refresh_token: "over-scoped-refresh",
    token_type: "bearer",
    scope: "wallet:accounts:read,wallet:transactions:send",
  });
try {
  response = await request(`/oauth/callback?state=${broadGrantState}&code=test-code`);
  assert.match(await response.text(), /outside this read-only app/);
  const broadGrantSession = await sessions.object(broadGrantState).storage.get("session");
  assert.equal(broadGrantSession.status, "error");
  assert.equal(broadGrantSession.access_token, undefined);
} finally {
  globalThis.fetch = nativeFetch;
}

assert.equal((await request("/oauth/refresh", { method: "POST" })).status, 415);
assert.equal((await request("/oauth/revoke", { method: "POST" })).status, 415);
response = await worker.fetch(
  new Request("https://broker.example/oauth/refresh", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ refresh_token: "refresh" }),
  }),
  { ...env, OAUTH_CREDENTIAL_LIMITER: undefined },
);
assert.equal(response.status, 429);
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
