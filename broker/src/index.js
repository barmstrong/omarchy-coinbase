const AUTH_URL = "https://login.coinbase.com/oauth2/auth";
const TOKEN_URL = "https://login.coinbase.com/oauth2/token";
const REVOKE_URL = "https://login.coinbase.com/oauth2/revoke";
const SCOPES = [
  "wallet:user:read",
  "wallet:accounts:read",
  "offline_access",
].join(",");
const SESSION_TTL = 600;
const HANDOFF_TTL = 60;
const HANDOFF_WAIT_MS = 30000;
const READ_ONLY_SCOPES = new Set(SCOPES.split(","));

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/health" && request.method === "GET") return json({ ok: true });
      if (url.pathname === "/oauth/start" && request.method === "POST") {
        if (!(await allowed(env.OAUTH_START_LIMITER, request))) return limited();
        return await start(env, url);
      }
      if (url.pathname === "/oauth/callback" && request.method === "GET") {
        if (!(await allowed(env.OAUTH_CALLBACK_LIMITER, request))) return limited();
        return await callback(request, env, url);
      }
      if (url.pathname === "/oauth/session" && request.method === "POST") {
        return await session(request, env);
      }
      if (url.pathname === "/oauth/refresh" && request.method === "POST") {
        if (!(await allowed(env.OAUTH_TOKEN_LIMITER, request))) return limited();
        return await refresh(request, env);
      }
      if (url.pathname === "/oauth/revoke" && request.method === "POST") {
        if (!(await allowed(env.OAUTH_TOKEN_LIMITER, request))) return limited();
        return await revoke(request, env);
      }
      return json({ error: "not found" }, 404);
    } catch (err) {
      return json({ error: String(err.message || err) }, 500);
    }
  },
};

function json(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
      "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
      ...extraHeaders,
    },
  });
}

async function allowed(limiter, request) {
  // Authentication endpoints should not silently lose abuse protection when
  // a deployment omits a binding from wrangler.jsonc.
  if (!limiter || typeof limiter.limit !== "function") return false;
  const key = `ip:${request.headers.get("cf-connecting-ip") || "unknown"}`;
  return allowedKey(limiter, key);
}

async function allowedKey(limiter, key) {
  if (!limiter || typeof limiter.limit !== "function") return false;
  const result = await limiter.limit({ key });
  return result.success === true;
}

function limited() {
  return json({ error: "too many requests" }, 429, { "retry-after": "60" });
}

function html(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
      "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
      "cross-origin-opener-policy": "same-origin",
      "cross-origin-resource-policy": "same-origin",
    },
  });
}

function requireSecrets(env) {
  if (!env.COINBASE_CLIENT_ID || !env.COINBASE_CLIENT_SECRET)
    throw new Error("broker is missing COINBASE_CLIENT_ID / COINBASE_CLIENT_SECRET");
}

function b64url(bytes) {
  let binary = "";
  const view = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : bytes;
  for (let i = 0; i < view.length; i++) binary += String.fromCharCode(view[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function pkce() {
  const raw = crypto.getRandomValues(new Uint8Array(32));
  const verifier = b64url(raw);
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return { verifier, challenge: b64url(hash) };
}

async function digest(value) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return b64url(hash);
}

function sessionNamespace(env) {
  if (!env.OAUTH_SESSIONS || typeof env.OAUTH_SESSIONS.idFromName !== "function")
    throw new Error("broker is missing OAUTH_SESSIONS Durable Object binding");
  return env.OAUTH_SESSIONS;
}

function sessionStub(env, state) {
  const namespace = sessionNamespace(env);
  return namespace.get(namespace.idFromName(state));
}

async function durablePost(stub, path, body) {
  return stub.fetch(`https://oauth-session.internal${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function parseSessionHandle(value) {
  const match = /^([A-Za-z0-9_-]{43})\.([A-Za-z0-9_-]{43})$/.exec(String(value || ""));
  return match ? { state: match[1], claim: match[2] } : null;
}

async function start(env, url) {
  requireSecrets(env);
  if (url.protocol !== "https:") return json({ error: "https required" }, 400);
  const state = b64url(crypto.getRandomValues(new Uint8Array(32)));
  const claim = b64url(crypto.getRandomValues(new Uint8Array(32)));
  const { verifier, challenge } = await pkce();
  const redirectUri = `${url.origin}/oauth/callback`;
  const initialized = await durablePost(sessionStub(env, state), "/init", {
    claimHash: await digest(claim),
    verifier,
    redirectUri,
  });
  if (!initialized.ok) throw new Error("could not initialize OAuth session");
  const authorize = new URL(AUTH_URL);
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("client_id", env.COINBASE_CLIENT_ID);
  authorize.searchParams.set("redirect_uri", redirectUri);
  authorize.searchParams.set("scope", SCOPES);
  authorize.searchParams.set("state", state);
  authorize.searchParams.set("code_challenge", challenge);
  authorize.searchParams.set("code_challenge_method", "S256");
  return json({
    session_id: `${state}.${claim}`,
    authorize_url: authorize.toString(),
    redirect_uri: redirectUri,
  });
}

async function tokenRequest(env, body) {
  const payload = new URLSearchParams(body);
  payload.set("client_id", env.COINBASE_CLIENT_ID);
  payload.set("client_secret", env.COINBASE_CLIENT_SECRET);
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    // Cloudflare Workers supports only "follow" and "manual". Keep redirects
    // manual so credentials are never forwarded to a different endpoint.
    redirect: "manual",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: payload.toString(),
  });
  if (response.status >= 300 && response.status < 400)
    throw new Error("token endpoint redirected unexpectedly");
  const data = await response.json().catch(() => ({}));
  if (!response.ok)
    throw new Error(data.error_description || data.error || `token http ${response.status}`);
  if (typeof data.access_token !== "string" || !data.access_token || data.access_token.length > 8192)
    throw new Error("token response missing a valid access token");
  if (data.refresh_token && (typeof data.refresh_token !== "string" || data.refresh_token.length > 8192))
    throw new Error("token response contained an invalid refresh token");
  const tokenType = String(data.token_type || "bearer").trim().toLowerCase();
  if (tokenType !== "bearer") throw new Error("token response used an unsupported token type");
  const granted = String(data.scope || "")
    .split(/[\s,]+/)
    .filter(Boolean);
  if (granted.some((scope) => !READ_ONLY_SCOPES.has(scope)))
    throw new Error("Coinbase returned permissions outside this read-only app's requested scopes");
  return data;
}

async function callback(request, env, url) {
  requireSecrets(env);
  const state = url.searchParams.get("state") || "";
  const code = url.searchParams.get("code") || "";
  const error = url.searchParams.get("error") || "";
  if (!/^[A-Za-z0-9_-]{43}$/.test(state))
    return donePage(false, "This sign-in session expired. Return to Omarchy and try again.");
  const response = await durablePost(sessionStub(env, state), "/callback", {
    code,
    error,
    redirectUri: `${url.origin}/oauth/callback`,
  });
  const result = await response.json().catch(() => ({}));
  return donePage(result.ok === true, result.message || "Sign-in failed.");
}

async function session(request, env) {
  const parsed = await readJson(request);
  if (parsed.response) return parsed.response;
  const body = parsed.body;
  const handle = parseSessionHandle(body.session_id);
  if (!handle) return json({ error: "invalid session" }, 400);
  if (!(await allowed(env.OAUTH_SESSION_LIMITER, request))) return limited();
  if (!(await allowedKey(env.OAUTH_SESSION_ID_LIMITER, `session:${handle.state}`))) return limited();
  const response = await durablePost(sessionStub(env, handle.state), "/claim", {
    claim: handle.claim,
  });
  const result = await response.json().catch(() => ({ status: "error", error: "invalid response" }));
  return json(result, response.status);
}

async function refresh(request, env) {
  requireSecrets(env);
  const parsed = await readJson(request);
  if (parsed.response) return parsed.response;
  const body = parsed.body;
  const refreshToken = String(body.refresh_token || "");
  if (!refreshToken || refreshToken.length > 4096)
    return json({ error: "valid refresh_token required" }, 400);
  if (!(await allowedKey(env.OAUTH_CREDENTIAL_LIMITER, `refresh:${await digest(refreshToken)}`)))
    return limited();
  const tokens = await tokenRequest(env, {
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });
  return json({
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token || refreshToken,
    expires_in: tokens.expires_in || 3600,
    token_type: tokens.token_type || "bearer",
    scope: tokens.scope || "",
  });
}

async function revoke(request, env) {
  requireSecrets(env);
  const parsed = await readJson(request);
  if (parsed.response) return parsed.response;
  const body = parsed.body;
  const token = String(body.access_token || "");
  if (!token || token.length > 4096) return json({ error: "valid access_token required" }, 400);
  if (!(await allowedKey(env.OAUTH_CREDENTIAL_LIMITER, `revoke:${await digest(token)}`)))
    return limited();
  const payload = new URLSearchParams({
    token,
    client_id: env.COINBASE_CLIENT_ID,
    client_secret: env.COINBASE_CLIENT_SECRET,
  });
  const response = await fetch(REVOKE_URL, {
    method: "POST",
    redirect: "manual",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      authorization: `Bearer ${token}`,
    },
    body: payload.toString(),
  });
  if (response.status >= 300 && response.status < 400)
    throw new Error("revoke endpoint redirected unexpectedly");
  if (!response.ok) throw new Error(`revoke http ${response.status}`);
  return json({ ok: true });
}

export class OAuthSession {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.pendingTokens = null;
    this.claimWaiter = null;
    this.claimTimer = null;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (request.method !== "POST") return json({ error: "not found" }, 404);
    if (url.pathname === "/init") return this.initialize(request);
    if (url.pathname === "/callback") return this.complete(request);
    if (url.pathname === "/claim") return this.claim(request);
    return json({ error: "not found" }, 404);
  }

  async current() {
    const row = await this.ctx.storage.get("session");
    if (!row || Number(row.expiresAt || 0) <= Date.now()) {
      if (row) await this.ctx.storage.deleteAll();
      return null;
    }
    return row;
  }

  async store(row, lifetimeSeconds) {
    row.expiresAt = Date.now() + lifetimeSeconds * 1000;
    await this.ctx.storage.put("session", row);
    await this.ctx.storage.setAlarm(row.expiresAt);
  }

  async initialize(request) {
    const parsed = await readJson(request);
    if (parsed.response) return parsed.response;
    if (await this.current()) return json({ error: "session already exists" }, 409);
    const { claimHash, verifier, redirectUri } = parsed.body;
    if (
      !/^[A-Za-z0-9_-]{43}$/.test(String(claimHash || "")) ||
      !/^[A-Za-z0-9_-]{43}$/.test(String(verifier || "")) ||
      typeof redirectUri !== "string" ||
      !redirectUri.startsWith("https://") ||
      redirectUri.length > 2048
    )
      return json({ error: "invalid session data" }, 400);
    await this.store(
      {
        status: "pending",
        claimHash,
        verifier,
        redirectUri,
        createdAt: Date.now(),
      },
      SESSION_TTL,
    );
    return json({ ok: true });
  }

  async fail(row, message) {
    await this.store(
      {
        status: "error",
        claimHash: row.claimHash,
        error: String(message || "Sign-in failed.").slice(0, 500),
      },
      120,
    );
  }

  waitForClaim() {
    return new Promise((resolve) => {
      this.claimWaiter = resolve;
      this.claimTimer = setTimeout(() => this.resolveClaim(false), HANDOFF_WAIT_MS);
    });
  }

  resolveClaim(claimed) {
    if (this.claimTimer !== null) clearTimeout(this.claimTimer);
    this.claimTimer = null;
    const resolve = this.claimWaiter;
    this.claimWaiter = null;
    if (resolve) resolve(claimed);
  }

  async complete(request) {
    const parsed = await readJson(request);
    if (parsed.response) return parsed.response;
    const row = await this.current();
    if (!row)
      return json({ ok: false, message: "This sign-in session expired. Return to Omarchy and try again." });
    if (row.status !== "pending")
      return json({ ok: false, message: "This sign-in session has already been used." });
    if (row.redirectUri !== parsed.body.redirectUri) {
      await this.ctx.storage.deleteAll();
      return json({ ok: false, message: "This sign-in session has already been used." });
    }
    const error = String(parsed.body.error || "");
    if (error) {
      const message = error.slice(0, 200);
      await this.fail(row, message);
      return json({ ok: false, message });
    }
    const code = String(parsed.body.code || "");
    if (!code || code.length > 4096) {
      const message = "Coinbase did not return an authorization code.";
      await this.fail(row, message);
      return json({ ok: false, message });
    }

    // Persist this transition before the network request. A second callback
    // is then rejected even while the authorization code exchange is running.
    await this.ctx.storage.put("session", { ...row, status: "exchanging" });
    try {
      const tokens = await tokenRequest(this.env, {
        grant_type: "authorization_code",
        code,
        redirect_uri: row.redirectUri,
        code_verifier: row.verifier,
      });
      const claimed = this.waitForClaim();
      this.pendingTokens = {
        status: "complete",
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token || "",
        expires_in: tokens.expires_in || 3600,
        token_type: tokens.token_type || "bearer",
        scope: tokens.scope || "",
      };
      // Only readiness is durable. Bearer credentials remain in this live
      // object's memory while the desktop's pending poll collects them.
      await this.store({ status: "ready", claimHash: row.claimHash }, HANDOFF_TTL);
      if (await claimed)
        return json({ ok: true, message: "You can close this tab and return to Omarchy." });
      this.pendingTokens = null;
      const message = "The desktop did not collect this sign-in. Return to Omarchy and try again.";
      await this.fail(row, message);
      return json({ ok: false, message });
    } catch (err) {
      this.pendingTokens = null;
      this.resolveClaim(false);
      const message = String(err.message || err).slice(0, 500);
      await this.fail(row, message);
      return json({ ok: false, message });
    }
  }

  async claim(request) {
    const parsed = await readJson(request);
    if (parsed.response) return parsed.response;
    const claim = String(parsed.body.claim || "");
    const row = await this.current();
    if (!row || !/^[A-Za-z0-9_-]{43}$/.test(claim) || (await digest(claim)) !== row.claimHash)
      return json({ status: "missing" }, 404);
    if (row.status === "pending" || row.status === "exchanging")
      return json({ status: "pending" }, 202);
    if (row.status === "error")
      return json({ status: "error", error: row.error || "failed" }, 400);
    if (row.status !== "ready" || !this.pendingTokens) {
      await this.ctx.storage.deleteAll();
      return json({ status: "error", error: "sign-in handoff was interrupted; try again" }, 400);
    }
    const result = this.pendingTokens;
    this.pendingTokens = null;
    // SQLite-backed Durable Object deletion is strongly consistent and
    // atomic, so this credential handoff cannot be claimed a second time.
    await this.ctx.storage.deleteAll();
    this.resolveClaim(true);
    return json(result);
  }

  async alarm() {
    this.pendingTokens = null;
    this.resolveClaim(false);
    await this.ctx.storage.deleteAll();
  }
}

function isJson(request) {
  return (request.headers.get("content-type") || "").toLowerCase().startsWith("application/json");
}

async function readJson(request, maxBytes = 16384) {
  if (!isJson(request)) return { response: json({ error: "application/json required" }, 415) };
  const declared = Number(request.headers.get("content-length") || 0);
  if (Number.isFinite(declared) && declared > maxBytes)
    return { response: json({ error: "request body too large" }, 413) };
  if (!request.body) return { response: json({ error: "invalid JSON body" }, 400) };
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let size = 0;
  let text = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel();
      return { response: json({ error: "request body too large" }, 413) };
    }
    text += decoder.decode(value, { stream: true });
  }
  text += decoder.decode();
  try {
    const body = JSON.parse(text);
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("not an object");
    return { body };
  } catch {
    return { response: json({ error: "invalid JSON body" }, 400) };
  }
}

function donePage(ok, message) {
  const title = ok ? "Signed in" : "Sign-in did not finish";
  return html(`<!doctype html>
<meta charset="utf-8">
<title>${title}</title>
<body style="margin:0;font-family:ui-sans-serif,system-ui,sans-serif;background:#111;color:#eee;display:grid;min-height:100vh;place-items:center">
  <main style="max-width:28rem;padding:2rem">
    <h1 style="font-size:1.5rem;margin:0 0 .75rem">${title}</h1>
    <p style="opacity:.8;line-height:1.5">${escapeHtml(message)}</p>
  </main>
</body>`);
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
