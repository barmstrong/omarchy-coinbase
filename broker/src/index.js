const AUTH_URL = "https://login.coinbase.com/oauth2/auth";
const TOKEN_URL = "https://login.coinbase.com/oauth2/token";
const REVOKE_URL = "https://login.coinbase.com/oauth2/revoke";
const SCOPES = [
  "wallet:user:read",
  "wallet:accounts:read",
  "offline_access",
].join(",");
const SESSION_TTL = 600;
const COMPLETE_TTL = 600;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/health" && request.method === "GET") return json({ ok: true });
      if (url.pathname === "/oauth/start" && request.method === "POST") {
        if (!(await allowed(env.OAUTH_START_LIMITER, request))) return limited();
        return start(env, url);
      }
      if (url.pathname === "/oauth/callback" && request.method === "GET")
        return callback(request, env, url);
      if (url.pathname === "/oauth/session" && request.method === "POST") {
        if (!(await allowed(env.OAUTH_SESSION_LIMITER, request))) return limited();
        return session(request, env);
      }
      if (url.pathname === "/oauth/refresh" && request.method === "POST") {
        if (!(await allowed(env.OAUTH_TOKEN_LIMITER, request))) return limited();
        return refresh(request, env);
      }
      if (url.pathname === "/oauth/revoke" && request.method === "POST") {
        if (!(await allowed(env.OAUTH_TOKEN_LIMITER, request))) return limited();
        return revoke(request, env);
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
      ...extraHeaders,
    },
  });
}

async function allowed(limiter, request) {
  if (!limiter || typeof limiter.limit !== "function") return true;
  const key = request.headers.get("cf-connecting-ip") || "unknown";
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

async function start(env, url) {
  requireSecrets(env);
  if (url.protocol !== "https:") return json({ error: "https required" }, 400);
  const state = b64url(crypto.getRandomValues(new Uint8Array(18)));
  const id = b64url(crypto.getRandomValues(new Uint8Array(32)));
  const { verifier, challenge } = await pkce();
  const redirectUri = `${url.origin}/oauth/callback`;
  await env.SESSIONS.put(
    `oauth-state:${state}`,
    JSON.stringify({ status: "pending", verifier, sessionId: id, createdAt: Date.now() }),
    { expirationTtl: SESSION_TTL },
  );
  await env.SESSIONS.put(
    `oauth-session:${id}`,
    JSON.stringify({ status: "pending", createdAt: Date.now() }),
    { expirationTtl: SESSION_TTL },
  );
  const authorize = new URL(AUTH_URL);
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("client_id", env.COINBASE_CLIENT_ID);
  authorize.searchParams.set("redirect_uri", redirectUri);
  authorize.searchParams.set("scope", SCOPES);
  authorize.searchParams.set("state", state);
  authorize.searchParams.set("code_challenge", challenge);
  authorize.searchParams.set("code_challenge_method", "S256");
  return json({ session_id: id, authorize_url: authorize.toString(), redirect_uri: redirectUri });
}

async function tokenRequest(env, body) {
  const payload = new URLSearchParams(body);
  payload.set("client_id", env.COINBASE_CLIENT_ID);
  payload.set("client_secret", env.COINBASE_CLIENT_SECRET);
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    redirect: "error",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: payload.toString(),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok)
    throw new Error(data.error_description || data.error || `token http ${response.status}`);
  if (typeof data.access_token !== "string" || !data.access_token || data.access_token.length > 8192)
    throw new Error("token response missing a valid access token");
  if (data.refresh_token && (typeof data.refresh_token !== "string" || data.refresh_token.length > 8192))
    throw new Error("token response contained an invalid refresh token");
  return data;
}

async function callback(request, env, url) {
  requireSecrets(env);
  const state = url.searchParams.get("state") || "";
  const code = url.searchParams.get("code") || "";
  const error = url.searchParams.get("error") || "";
  const row = /^[A-Za-z0-9_-]{24}$/.test(state)
    ? await env.SESSIONS.get(`oauth-state:${state}`, "json")
    : null;
  if (!row)
    return donePage(false, "This sign-in session expired. Return to Omarchy and try again.");
  const sessionKey = `oauth-session:${row.sessionId || ""}`;
  const sessionRow = row.sessionId ? await env.SESSIONS.get(sessionKey, "json") : null;
  if (row.status !== "pending" || !row.verifier || !sessionRow || sessionRow.status !== "pending") {
    await env.SESSIONS.delete(`oauth-state:${state}`);
    return donePage(false, "This sign-in session has already been used.");
  }
  if (error) {
    const message = error.slice(0, 200);
    await env.SESSIONS.put(sessionKey, JSON.stringify({ status: "error", error: message }), { expirationTtl: 120 });
    await env.SESSIONS.delete(`oauth-state:${state}`);
    return donePage(false, message);
  }
  if (!code || code.length > 4096) {
    const message = "Coinbase did not return an authorization code.";
    await env.SESSIONS.put(
      sessionKey,
      JSON.stringify({ status: "error", error: message }),
      { expirationTtl: 120 },
    );
    await env.SESSIONS.delete(`oauth-state:${state}`);
    return donePage(false, "Coinbase did not return an authorization code.");
  }
  await env.SESSIONS.delete(`oauth-state:${state}`);
  try {
    const tokens = await tokenRequest(env, {
      grant_type: "authorization_code",
      code,
      redirect_uri: `${url.origin}/oauth/callback`,
      code_verifier: row.verifier,
    });
    const complete = {
      status: "complete",
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token || "",
      expires_in: tokens.expires_in || 3600,
      token_type: tokens.token_type || "bearer",
      scope: tokens.scope || "",
    };
    await env.SESSIONS.put(sessionKey, JSON.stringify(complete), { expirationTtl: COMPLETE_TTL });
    return donePage(true, "You can close this tab and return to Omarchy.");
  } catch (err) {
    const message = String(err.message || err).slice(0, 500);
    const current = await env.SESSIONS.get(sessionKey, "json");
    if (!current || current.status !== "complete")
      await env.SESSIONS.put(
        sessionKey,
        JSON.stringify({ status: "error", error: message }),
        { expirationTtl: 120 },
      );
    return donePage(false, message);
  }
}

async function session(request, env) {
  const parsed = await readJson(request);
  if (parsed.response) return parsed.response;
  const body = parsed.body;
  const id = String(body.session_id || "");
  if (!/^[A-Za-z0-9_-]{43}$/.test(id)) return json({ error: "invalid session" }, 400);
  const key = `oauth-session:${id}`;
  const row = await env.SESSIONS.get(key, "json");
  if (!row) return json({ status: "missing" }, 404);
  if (row.status === "pending") return json({ status: "pending" }, 202);
  if (row.status === "error") return json({ status: "error", error: row.error || "failed" }, 400);
  if (row.status !== "complete" || !row.access_token) {
    await env.SESSIONS.delete(key);
    return json({ status: "error", error: "invalid session state" }, 400);
  }
  await env.SESSIONS.delete(key);
  return json({
    status: "complete",
    access_token: row.access_token,
    refresh_token: row.refresh_token,
    expires_in: row.expires_in,
    token_type: row.token_type,
    scope: row.scope,
  });
}

async function refresh(request, env) {
  requireSecrets(env);
  const parsed = await readJson(request);
  if (parsed.response) return parsed.response;
  const body = parsed.body;
  const refreshToken = String(body.refresh_token || "");
  if (!refreshToken || refreshToken.length > 4096)
    return json({ error: "valid refresh_token required" }, 400);
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
  const payload = new URLSearchParams({
    token,
    client_id: env.COINBASE_CLIENT_ID,
    client_secret: env.COINBASE_CLIENT_SECRET,
  });
  const response = await fetch(REVOKE_URL, {
    method: "POST",
    redirect: "error",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      authorization: `Bearer ${token}`,
    },
    body: payload.toString(),
  });
  if (!response.ok) throw new Error(`revoke http ${response.status}`);
  return json({ ok: true });
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
