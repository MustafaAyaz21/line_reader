/**
 * Line Reader — Cloudflare Workers AI + D1 Yetki & Aktivasyon Kodu Worker'ı
 *
 * Bağlantılar (Cloudflare Dashboard -> Worker Settings -> Bindings):
 * 1. Workers AI  -> Variable name: AI
 * 2. D1 Database -> Variable name: DB  (schema.sql tablolarını oluşturun)
 * 3. Secret      -> Name: ADMIN_SECRET (PC Makale Paneli'ndeki yönetici şifresi)
 *
 * Uç Noktalar:
 * - GET  /               -> Sağlık ve binding durumu
 * - GET  /me             -> Kayıtlı kullanıcı yetki durumu (Bearer Firebase ID Token)
 * - POST /redeem         -> Aktivasyon kodu kullanma (Bearer Firebase ID Token)
 * - POST /               -> Tarayıcı bağlamsal AI çevirisi (Yalnızca yetkili kullanıcılar)
 * - GET/POST/PATCH/DELETE /admin/codes -> Kod yönetimi (X-Admin-Secret)
 * - GET/POST/DELETE       /admin/users -> Manuel yetki verme / kaldırma (X-Admin-Secret)
 */

const FIREBASE_PROJECT_ID = "line-reader-e2e00";
const FIREBASE_ISSUER = `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`;
const GOOGLE_JWKS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

const PRIMARY_AI_MODEL = "@cf/meta/llama-3.1-8b-instruct-fast";
const FALLBACK_AI_MODEL = "@cf/meta/llama-3.1-8b-instruct";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Admin-Secret, If-None-Match",
};

let cachedJwks = null;
let cachedJwksExpiresAt = 0;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    const method = request.method.toUpperCase();

    // 1) Sağlık ve binding kontrolü
    if (method === "GET" && (path === "/" || path === "/health")) {
      return jsonResponse({
        ok: true,
        service: "line-reader-browser-ai",
        project_id: FIREBASE_PROJECT_ID,
        ai_bound: Boolean(env && env.AI),
        db_bound: Boolean(env && env.DB),
        admin_configured: Boolean(env && env.ADMIN_SECRET),
        otp_configured: Boolean(env && env.RESEND_API_KEY),
      });
    }

    // 2) Herkese açık anlık makale akışı (Cloudflare D1 — 1 saniye altı yayın)
    if (method === "GET" && (path === "/articles" || path === "/articles.json")) {
      return handleGetArticlesFeed(request, env);
    }

    // 2.5) Herkese açık D1 önbellekli doğal örnek cümle servisi (8-22 kelimelik cümleler)
    if ((method === "GET" || method === "POST") && path === "/examples") {
      return handleWordExamples(request, env, url);
    }

    // 2.6) Herkese açık iki dilli sözlük & çeviri köprüsü (CORS engelsiz Google Translate)
    if ((method === "GET" || method === "POST") && (path === "/dict" || path === "/translate_single")) {
      return handleDictionaryProxy(request, env, url);
    }

    // 2.7) Herkese açık web arama köprüsü (DuckDuckGo CORS engelsiz arama)
    if ((method === "GET" || method === "POST") && path === "/search") {
      return handleSearchProxy(request, env, url);
    }

    // 2.8) Şifre sıfırlama (Özel Line Reader HTML şablonlu e-posta — Resend)
    if (method === "POST" && path === "/auth/password-reset") {
      return handlePasswordResetRequest(request, env);
    }

    // 3) Admin uç noktaları (PC Makale Paneli — X-Admin-Secret korumalı)
    if (path.startsWith("/admin/")) {
      return handleAdminRequest(request, env, path, method);
    }

    // 3) Kullanıcı uç noktaları (Firebase ID Token zorunlu)
    const authHeader = request.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const verifiedUser = await verifyFirebaseIdToken(authHeader.slice(7).trim());
    if (!verifiedUser) {
      return jsonResponse({ error: "invalid_token" }, 401);
    }

    if (method === "GET" && path === "/me") {
      return handleGetMe(env, verifiedUser);
    }

    if (method === "POST" && path === "/auth/send-otp") {
      return handleSendVerificationOtp(request, env, verifiedUser);
    }

    if (method === "POST" && path === "/auth/verify-otp") {
      return handleVerifyEmailOtp(request, env, verifiedUser);
    }

    if (method === "POST" && path === "/redeem") {
      return handleRedeemCode(request, env, verifiedUser);
    }

    if (method === "POST" && (path === "/" || path === "/translate")) {
      return handleBrowserAiTranslate(request, env, verifiedUser);
    }

    if (method === "GET" && path === "/sync") {
      return handleUserCloudSyncGet(request, env, verifiedUser);
    }

    if (method === "POST" && path === "/sync") {
      return handleUserCloudSyncPost(request, env, verifiedUser);
    }

    // 4) Mobil Geliştirici Paneli uç noktaları (Firebase ID Token + D1 source='admin' zorunlu)
    if (path.startsWith("/dev/")) {
      return handleDeveloperPanelRequest(request, env, verifiedUser, path, method);
    }

    return jsonResponse({ error: "not_found" }, 404);
  },

  async scheduled(event, env, ctx) {
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(handleScheduledPublishRun(env, "cron"));
    } else {
      await handleScheduledPublishRun(env, "cron");
    }
  },
};

/* ---------------- Herkese Açık İki Dilli Sözlük Köprüsü (CORS Engelli Tarayıcılar İçin) ---------------- */

async function handleDictionaryProxy(request, env, url) {
  let query = url.searchParams.get("q") || url.searchParams.get("word") || "";
  let sl = url.searchParams.get("sl") || "en";
  let tl = url.searchParams.get("tl") || "tr";

  if (!query && request.method.toUpperCase() === "POST") {
    try {
      const body = await request.json();
      query = body?.q || body?.word || "";
      if (body?.sl) sl = body.sl;
      if (body?.tl) tl = body.tl;
    } catch (_) {}
  }

  query = String(query || "").trim();
  if (!query) {
    return jsonResponse({ error: "missing_query" }, 400);
  }

  try {
    const googleUrl = new URL("https://translate.googleapis.com/translate_a/single");
    const dtParams = url.searchParams.getAll("dt");

    if (dtParams.length > 0) {
      for (const [k, v] of url.searchParams.entries()) {
        if (k !== "dt") googleUrl.searchParams.set(k, v);
      }
      for (const dt of dtParams) {
        googleUrl.searchParams.append("dt", dt);
      }
    } else {
      googleUrl.searchParams.set("client", "gtx");
      googleUrl.searchParams.set("sl", sl);
      googleUrl.searchParams.set("tl", tl);
      googleUrl.searchParams.append("dt", "t");
      googleUrl.searchParams.append("dt", "bd");
      googleUrl.searchParams.append("dt", "at");
      googleUrl.searchParams.append("dt", "ex");
      googleUrl.searchParams.append("dt", "qca");
      googleUrl.searchParams.set("q", query);
    }

    const res = await fetch(googleUrl.toString(), {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "*/*",
      },
    });

    if (!res.ok) {
      return jsonResponse({ error: "upstream_error", status: res.status }, res.status);
    }

    const text = await res.text();
    return new Response(text, {
      status: 200,
      headers: {
        ...CORS_HEADERS,
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "public, max-age=86400, s-maxage=604800",
      },
    });
  } catch (err) {
    return jsonResponse({ error: "proxy_failed", details: String(err) }, 500);
  }
}

/* ---------------- Herkese Açık Web Arama Köprüsü (DuckDuckGo HTML Proxy) ---------------- */

async function handleSearchProxy(request, env, url) {
  let query = url.searchParams.get("q") || "";
  if (!query && request.method.toUpperCase() === "POST") {
    try {
      const body = await request.json();
      query = body?.q || "";
    } catch (_) {}
  }

  query = String(query || "").trim();
  if (!query) {
    return jsonResponse({ error: "missing_query" }, 400);
  }

  try {
    const ddgUrl = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
    const res = await fetch(ddgUrl, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept":
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9,tr;q=0.8",
      },
    });

    const text = await res.text();
    return new Response(text, {
      status: 200,
      headers: {
        ...CORS_HEADERS,
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=600",
      },
    });
  } catch (err) {
    return jsonResponse({ error: "search_proxy_failed", details: String(err) }, 500);
  }
}

/* ---------------- Herkese Açık D1 Önbellekli Örnek Cümle Üretici ---------------- */

async function handleWordExamples(request, env, url) {
  let rawWord = url.searchParams.get("word") || "";
  if (!rawWord && request.method.toUpperCase() === "POST") {
    const body = await safeReadJson(request);
    rawWord = String(body?.word || "");
  }

  const word = rawWord
    .replace(/\s+/g, " ")
    .replace(/^[^a-zA-Z]+|[^a-zA-Z]+$/g, "")
    .trim()
    .toLowerCase();

  if (word.length < 2 || word.length > 64 || !/^[a-z][a-z\s'\-]*[a-z]$/.test(word)) {
    return jsonResponse({ ok: false, error: "invalid_word" }, 400);
  }

  const cacheKey = `v2:${word}`;

  // 1) Önce Cloudflare D1 önbelleğine bak (maliyetsiz ve <100ms).
  if (env && env.DB) {
    try {
      await ensureSchema(env.DB);
      const cached = await env.DB
        .prepare("SELECT examples_json FROM word_examples_cache WHERE word = ? LIMIT 1")
        .bind(cacheKey)
        .first();
      if (cached && cached.examples_json) {
        const parsed = JSON.parse(cached.examples_json);
        if (Array.isArray(parsed) && parsed.length >= 2) {
          return jsonResponse({
            ok: true,
            word,
            cached: true,
            examples: parsed,
          });
        }
      }
    } catch (_) {}
  }

  if (!env || !env.AI) {
    return jsonResponse({ ok: false, error: "ai_not_configured" }, 503);
  }

  const systemPrompt = [
    "You are an expert English-Turkish dictionary editor for everyday language learners.",
    "Write EXACTLY 3 natural, meaningful, real-life English example sentences for the given English word or expression, with fluent Turkish translations.",
    "Strict rules:",
    "1. ALWAYS use the #1 MOST COMMON everyday meaning of the target word in ALL 3 sentences (for example: 'home' MUST mean house/residence/ev, 'run' MUST mean move fast/koşmak). NEVER use rare, technical, idiomatic, or obscure secondary meanings (such as 'home in on', 'home market', or 'home country' when 'home' simply means ev).",
    "2. Every English sentence MUST be a complete, natural sentence between 10 and 18 words long (never shorter than 8 words, never longer than 22 words).",
    "3. Use 3 different everyday life situations (family, friends, daily routine, travel, work) while keeping the SAME #1 most common meaning of the word. Never write dictionary definitions, bare phrases, or robotic templates.",
    "4. Provide a natural, accurate Turkish translation for each sentence matching that #1 everyday meaning.",
    '5. Respond ONLY with valid JSON: {"examples":[{"english":"...","turkish":"..."},{"english":"...","turkish":"..."},{"english":"...","turkish":"..."}]}',
  ].join("\n");

  const userPrompt = `Target word or expression: "${word}"\nUse ONLY its #1 most common everyday meaning in all 3 sentences.\nReturn ONLY the JSON object.`;

  try {
    const aiResult = await env.AI.run(MODEL_ID, {
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.25,
      max_tokens: 420,
    });

    const rawText = extractModelText(aiResult);
    const validExamples = parseExamplesJson(rawText);

    if (validExamples.length === 0) {
      return jsonResponse({ ok: false, error: "empty_examples" }, 502);
    }

    // D1 önbelleğine kaydet (bir sonraki aramada anında ve ücretsiz döner).
    if (env && env.DB && validExamples.length >= 2) {
      try {
        await env.DB
          .prepare(`
            INSERT INTO word_examples_cache (word, examples_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(word) DO UPDATE SET
              examples_json = excluded.examples_json,
              updated_at = excluded.updated_at
          `)
          .bind(cacheKey, JSON.stringify(validExamples), new Date().toISOString())
          .run();
      } catch (_) {}
    }

    return jsonResponse({
      ok: true,
      word,
      cached: false,
      examples: validExamples,
    });
  } catch (err) {
    return jsonResponse({
      ok: false,
      error: "examples_generation_failed",
      detail: String(err?.message || err),
    }, 502);
  }
}

function parseExamplesJson(rawText) {
  if (!rawText) return [];
  const cleaned = String(rawText)
    .replace(/```json\s*/gi, "")
    .replace(/```/g, "")
    .trim();

  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start === -1 || end <= start) return [];

  try {
    const parsed = JSON.parse(cleaned.slice(start, end + 1));
    const rawList = Array.isArray(parsed?.examples) ? parsed.examples : [];
    const valid = [];
    const seen = new Set();
    for (const item of rawList) {
      if (!item || typeof item !== "object") continue;
      const en = String(item.english || "").replace(/\s+/g, " ").trim();
      const tr = String(item.turkish || "").replace(/\s+/g, " ").trim();
      const wordCount = en.split(/\s+/).filter(Boolean).length;
      if (wordCount < 7 || wordCount > 26 || tr.length < 4) continue;
      const key = en.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      valid.push({ english: en, turkish: tr });
      if (valid.length >= 3) break;
    }
    return valid;
  } catch (_) {
    return [];
  }
}

/* ---------------- Kullanıcı Yetki & Kod İşlemleri ---------------- */

async function ensureSchema(db) {
  await db.batch([
    db.prepare(`
      CREATE TABLE IF NOT EXISTS access_codes (
        code TEXT PRIMARY KEY,
        max_uses INTEGER NOT NULL DEFAULT 1,
        used_count INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_entitlements (
        email TEXT PRIMARY KEY,
        uid TEXT,
        is_unlimited INTEGER NOT NULL DEFAULT 1,
        source TEXT NOT NULL DEFAULT 'manual',
        code_used TEXT,
        granted_at TEXT NOT NULL,
        has_special_themes INTEGER NOT NULL DEFAULT 0
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS code_redemptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        email TEXT NOT NULL,
        uid TEXT NOT NULL,
        redeemed_at TEXT NOT NULL,
        UNIQUE(code, email)
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS articles_feed (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload_json TEXT NOT NULL,
        etag TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS word_examples_cache (
        word TEXT PRIMARY KEY,
        examples_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS registered_users (
        email TEXT PRIMARY KEY,
        uid TEXT,
        display_name TEXT,
        auth_provider TEXT,
        first_seen_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS user_cloud_sync (
        uid TEXT PRIMARY KEY,
        email TEXT,
        saved_words_json TEXT NOT NULL DEFAULT '[]',
        word_lists_json TEXT NOT NULL DEFAULT '[]',
        reading_progress_json TEXT NOT NULL DEFAULT '{}',
        preferences_json TEXT NOT NULL DEFAULT '{}',
        updated_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS email_verification_codes (
        email TEXT PRIMARY KEY,
        uid TEXT NOT NULL,
        code_hash TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_sent_at INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS publish_schedule_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        is_enabled INTEGER NOT NULL DEFAULT 1,
        publish_hour INTEGER NOT NULL DEFAULT 9,
        timezone_offset INTEGER NOT NULL DEFAULT 3,
        last_prepared_date TEXT,
        last_published_date TEXT,
        updated_at TEXT NOT NULL
      )
    `),
  ]);

  try {
    await db
      .prepare(`
        INSERT OR IGNORE INTO publish_schedule_config (id, is_enabled, publish_hour, timezone_offset, updated_at)
        VALUES (1, 1, 9, 3, datetime('now'))
      `)
      .run();
  } catch (_) {}

  // Mevcut canlı D1 tabloları için güvenli sütun geçişleri (zaten varsa sessizce geçer)
  try {
    await db
      .prepare("ALTER TABLE user_entitlements ADD COLUMN has_special_themes INTEGER NOT NULL DEFAULT 0")
      .run();
  } catch (_) {}
  try {
    await db
      .prepare("ALTER TABLE registered_users ADD COLUMN auth_provider TEXT")
      .run();
  } catch (_) {}
  try {
    await db
      .prepare("ALTER TABLE registered_users ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 0")
      .run();
  } catch (_) {}
}

async function handleGetArticlesFeed(request, env) {
  if (!env || !env.DB) {
    return jsonResponse({ ok: false, error: "db_not_configured" }, 503);
  }
  try {
    await ensureSchema(env.DB);
    const row = await env.DB
      .prepare("SELECT payload_json, etag, updated_at FROM articles_feed WHERE id = 1 LIMIT 1")
      .first();
    if (!row || !row.payload_json) {
      return jsonResponse({ ok: false, error: "articles_not_seeded" }, 404);
    }

    const etag = String(row.etag || "").trim();
    const ifNoneMatch = (request.headers.get("If-None-Match") || "").trim();
    const baseHeaders = {
      ...CORS_HEADERS,
      "Cache-Control": "no-cache, no-store, must-revalidate",
      "Pragma": "no-cache",
      ...(etag ? { "ETag": etag } : {}),
    };

    if (etag && ifNoneMatch && ifNoneMatch === etag) {
      return new Response(null, { status: 304, headers: baseHeaders });
    }

    return new Response(String(row.payload_json), {
      status: 200,
      headers: {
        ...baseHeaders,
        "Content-Type": "application/json; charset=utf-8",
      },
    });
  } catch (err) {
    return jsonResponse({ ok: false, error: "db_error", message: String(err?.message || err) }, 500);
  }
}

async function getUserEntitlement(db, user) {
  if (!db) {
    return { isUnlimited: false, source: null, codeUsed: null, hasSpecialThemes: false };
  }
  await ensureSchema(db);

  const email = (user.email || "").trim().toLowerCase();
  const uid = (user.uid || "").trim();

  let row = null;
  if (email) {
    row = await db
      .prepare("SELECT email, uid, is_unlimited, source, code_used, has_special_themes FROM user_entitlements WHERE LOWER(email) = ? LIMIT 1")
      .bind(email)
      .first();
  }
  if (!row && uid) {
    row = await db
      .prepare("SELECT email, uid, is_unlimited, source, code_used, has_special_themes FROM user_entitlements WHERE uid = ? LIMIT 1")
      .bind(uid)
      .first();
  }

  if (!row) {
    return { isUnlimited: false, source: null, codeUsed: null, hasSpecialThemes: false };
  }

  // E-posta ile önceden yetki verilmişse ilk girişte UID alanını tamamla.
  if (uid && !row.uid && row.email) {
    try {
      await db
        .prepare("UPDATE user_entitlements SET uid = ? WHERE LOWER(email) = ?")
        .bind(uid, String(row.email).toLowerCase())
        .run();
    } catch (_) {}
  }

  const isUnlimited = Number(row.is_unlimited) === 1;
  const isAdmin = isUnlimited && String(row.source || "").toLowerCase() === "admin";
  const hasSpecialThemes = Number(row.has_special_themes) === 1 || isAdmin;

  return {
    isUnlimited,
    source: isUnlimited ? (row.source || "manual") : null,
    codeUsed: isUnlimited ? (row.code_used || null) : null,
    hasSpecialThemes,
  };
}

function normalizeAuthProvider(raw) {
  const v = String(raw || "").trim().toLowerCase();
  if (!v) return null;
  if (v.includes("google") && (v.includes("password") || v.includes("email"))) {
    return "google+password";
  }
  if (v.includes("google")) return "google";
  if (v.includes("password") || v.includes("email")) return "password";
  return v;
}

async function upsertRegisteredUser(db, user) {
  if (!db || !user) return;
  const email = String(user.email || "").trim().toLowerCase();
  if (!email || !email.includes("@")) return;
  const uid = String(user.uid || "").trim() || null;
  const displayName = String(user.displayName || "").trim() || null;
  const authProvider = normalizeAuthProvider(user.authProvider || user.auth_provider || user.provider);
  const now = new Date().toISOString();
  try {
    await db
      .prepare(`
        INSERT INTO registered_users (email, uid, display_name, auth_provider, first_seen_at, last_seen_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(email) DO UPDATE SET
          uid = COALESCE(NULLIF(excluded.uid, ''), registered_users.uid),
          display_name = COALESCE(NULLIF(excluded.display_name, ''), registered_users.display_name),
          auth_provider = COALESCE(NULLIF(excluded.auth_provider, ''), registered_users.auth_provider),
          last_seen_at = excluded.last_seen_at
      `)
      .bind(email, uid, displayName, authProvider, now, now)
      .run();
  } catch (_) {}
}

async function listAllUsersWithEntitlements(db) {
  await ensureSchema(db);
  const [regRes, entRes] = await Promise.all([
    db.prepare("SELECT email, uid, display_name, auth_provider, first_seen_at, last_seen_at FROM registered_users").all(),
    db.prepare("SELECT email, uid, is_unlimited, source, code_used, granted_at, has_special_themes FROM user_entitlements").all(),
  ]);

  const map = new Map();
  for (const r of (regRes.results || [])) {
    const email = String(r.email || "").trim().toLowerCase();
    if (!email) continue;
    map.set(email, {
      email,
      uid: r.uid || null,
      display_name: r.display_name || null,
      auth_provider: r.auth_provider || null,
      first_seen_at: r.first_seen_at || null,
      last_seen_at: r.last_seen_at || null,
      is_unlimited: 0,
      source: "standard",
      code_used: null,
      granted_at: null,
      has_special_themes: 0,
    });
  }

  for (const e of (entRes.results || [])) {
    const email = String(e.email || "").trim().toLowerCase();
    if (!email) continue;
    const prev = map.get(email) || {
      email,
      uid: e.uid || null,
      display_name: null,
      auth_provider: null,
      first_seen_at: e.granted_at || null,
      last_seen_at: e.granted_at || null,
    };
    map.set(email, {
      ...prev,
      uid: prev.uid || e.uid || null,
      is_unlimited: Number(e.is_unlimited) === 1 ? 1 : 0,
      source: e.source || "manual",
      code_used: e.code_used || null,
      granted_at: e.granted_at || null,
      has_special_themes: Number(e.has_special_themes) === 1 ? 1 : 0,
    });
  }

  const rankOf = (u) => {
    const isUnl = Number(u.is_unlimited) === 1;
    if (isUnl && String(u.source || "").toLowerCase() === "admin") return 0;
    if (isUnl) return 1;
    if (Number(u.has_special_themes) === 1) return 2;
    return 3;
  };

  return Array.from(map.values()).sort((a, b) => {
    const rd = rankOf(a) - rankOf(b);
    if (rd !== 0) return rd;
    const ta = String(a.last_seen_at || a.granted_at || "");
    const tb = String(b.last_seen_at || b.granted_at || "");
    return tb.localeCompare(ta);
  });
}

async function handleGetMe(env, user) {
  try {
    const ent = await getUserEntitlement(env.DB, user);
    await upsertRegisteredUser(env.DB, user);
    let d1Verified = false;
    const normalizedEmail = String(user.email || "").trim().toLowerCase();
    if (env.DB && normalizedEmail) {
      try {
        const reg = await env.DB
          .prepare("SELECT email_verified FROM registered_users WHERE LOWER(email) = ? LIMIT 1")
          .bind(normalizedEmail)
          .first();
        d1Verified = Number(reg?.email_verified || 0) === 1;
      } catch (_) {}
    }
    const role = ent.isUnlimited
      ? (String(ent.source || "").toLowerCase() === "admin" ? "admin" : "premium")
      : "standard";
    return jsonResponse({
      ok: true,
      uid: user.uid,
      email: user.email,
      email_verified: Boolean(user.emailVerified || d1Verified),
      is_unlimited: ent.isUnlimited,
      source: ent.source,
      role,
      code_used: ent.codeUsed,
      has_special_themes: ent.hasSpecialThemes,
    });
  } catch (err) {
    return jsonResponse({ error: "db_error", message: String(err?.message || err) }, 500);
  }
}

/* ---------------- E-posta 6 Haneli OTP Doğrulama & HTML Şablonu ---------------- */

function generateSixDigitOtp() {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  const code = 100000 + (arr[0] % 900000);
  return String(code);
}

async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(String(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function buildLineReaderOtpEmailHtml({ code, displayName, isEnglish }) {
  const safeName = String(displayName || "").trim().replace(/[<>&"']/g, "");
  const rawCode = String(code).trim();
  const digits = rawCode.split("");
  const title = isEnglish ? "Verify Your Email" : "E-postanızı Doğrulayın";
  const greeting = safeName
    ? (isEnglish ? `Hello ${safeName},` : `Merhaba ${safeName},`)
    : (isEnglish ? "Hello," : "Merhaba,");
  const subtitle = isEnglish
    ? "One step left to expand your vocabulary."
    : "Kelime dağarcığınızı genişletmeye bir adım kaldı.";
  const bodyCopy = isEnglish
    ? "Welcome to Line Reader. Enter the 6-digit verification code below in the app to activate your account and sync your library across devices."
    : "Line Reader topluluğuna hoş geldiniz. Hesabınızı güvenle etkinleştirmek ve kütüphanenizi tüm cihazlarınızda eşitlemek için aşağıdaki 6 haneli kodu uygulamaya girin.";
  const validity = isEnglish
    ? "This code is valid for 10 minutes and is for your use only."
    : "Bu kod 10 dakika boyunca geçerlidir ve yalnızca size özeldir.";
  const footerNote = isEnglish
    ? "If you did not request this account, you can safely ignore this email."
    : "Bu hesabı siz oluşturmadıysanız bu e-postayı güvenle silebilirsiniz.";

  const digitBoxesHtml = digits.map((d) => `
    <td align="center" valign="middle" style="padding:0 3px;">
      <div style="width:36px;height:48px;line-height:48px;font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,Courier,monospace;font-size:26px;font-weight:800;color:#1E1B18;background-color:#FFFFFF;border:1.5px solid #D6CBB9;border-radius:10px;text-align:center;">
        ${d}
      </div>
    </td>
  `).join("");

  return `<!DOCTYPE html>
<html lang="${isEnglish ? "en" : "tr"}">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="color-scheme" content="light dark" />
  <title>${title} — Line Reader</title>
</head>
<body style="margin:0;padding:0;background-color:#F5F2EC;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1E1B18;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color:#F5F2EC;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background-color:#FFFFFF;border-radius:24px;border:1px solid #E7E0D6;overflow:hidden;box-shadow:0 12px 32px rgba(30,27,24,0.06);">
          <tr>
            <td style="padding:32px 32px 20px 32px;text-align:center;background:linear-gradient(135deg,#FFFDF9 0%,#F7F2E8 100%);border-bottom:1px solid #EFE9DF;">
              <div style="display:inline-block;width:52px;height:52px;line-height:52px;border-radius:16px;background-color:#1E1B18;color:#F5E6C8;font-size:24px;font-weight:800;letter-spacing:-0.5px;margin-bottom:14px;">LR</div>
              <div style="font-size:21px;font-weight:800;color:#1E1B18;letter-spacing:-0.3px;">Line Reader</div>
              <div style="font-size:13px;color:#786F66;margin-top:4px;">${subtitle}</div>
            </td>
          </tr>
          <tr>
            <td style="padding:32px;">
              <h1 style="margin:0 0 12px 0;font-size:20px;font-weight:800;color:#1E1B18;">${title}</h1>
              <p style="margin:0 0 10px 0;font-size:15px;line-height:1.6;color:#3D3731;font-weight:600;">${greeting}</p>
              <p style="margin:0 0 26px 0;font-size:14px;line-height:1.65;color:#5E554D;">${bodyCopy}</p>
              
              <!-- Tek satırda hizalı 6 kutucuklu OTP konteyneri -->
              <div style="background-color:#FAF7F2;border:1.5px dashed #D6CBB9;border-radius:18px;padding:22px 12px;text-align:center;margin-bottom:22px;">
                <div style="font-size:11px;text-transform:uppercase;letter-spacing:1.6px;color:#8C7F70;font-weight:700;margin-bottom:14px;">${isEnglish ? "VERIFICATION CODE" : "DOĞRULAMA KODU"}</div>
                <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:0 auto;display:inline-table;white-space:nowrap;">
                  <tr>
                    ${digitBoxesHtml}
                  </tr>
                </table>
              </div>

              <p style="margin:0;font-size:12.5px;line-height:1.5;color:#786F66;text-align:center;">⏱️ ${validity}</p>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 32px 26px 32px;background-color:#FAF8F5;border-top:1px solid #EFE9DF;text-align:center;">
              <p style="margin:0 0 8px 0;font-size:12px;line-height:1.5;color:#8C8278;">${footerNote}</p>
              <a href="https://getlinereader.com" style="font-size:12px;font-weight:700;color:#8A5A2B;text-decoration:none;">getlinereader.com</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

/* ---------------- Line Reader Şifre Sıfırlama E-posta Şablonu (Kayıt Tasarımıyla Birebir + Ortada Buton) ---------------- */

function buildLineReaderPasswordResetEmailHtml({ link, email, isEnglish }) {
  const title = isEnglish ? "Reset Your Password" : "Şifrenizi Sıfırlayın";
  const greeting = isEnglish ? "Hello," : "Merhaba,";
  const subtitle = isEnglish
    ? "Account Security & Access"
    : "Hesap Güvenliği ve Erişim";
  const bodyCopy = isEnglish
    ? "We received a request to reset the password for your Line Reader account. Click the button below to set a new password."
    : "Line Reader hesabınız için bir şifre sıfırlama talebinde bulundunuz. Yeni şifrenizi güvenle belirlemek için aşağıdaki butona tıklayın.";
  const buttonText = isEnglish ? "Reset Password →" : "Şifremi Sıfırla →";
  const validity = isEnglish
    ? "This link is valid for 1 hour and is for your security."
    : "Bu bağlantı güvenliğiniz için 1 saat boyunca geçerlidir.";
  const fallbackText = isEnglish
    ? "If the button above does not work, copy and paste this link into your browser:"
    : "Yukarıdaki buton çalışmıyorsa aşağıdaki bağlantıyı tarayıcınıza kopyalayabilirsiniz:";
  const footerNote = isEnglish
    ? "If you did not request a password reset, you can safely ignore this email. Your password will not change."
    : "Şifre sıfırlama talebinde bulunmadıysanız bu e-postayı güvenle silebilirsiniz. Şifreniz değişmeyecektir.";

  return `<!DOCTYPE html>
<html lang="${isEnglish ? "en" : "tr"}">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="color-scheme" content="light dark" />
  <title>${title} — Line Reader</title>
</head>
<body style="margin:0;padding:0;background-color:#F5F2EC;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1E1B18;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color:#F5F2EC;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background-color:#FFFFFF;border-radius:24px;border:1px solid #E7E0D6;overflow:hidden;box-shadow:0 12px 32px rgba(30,27,24,0.06);">
          <tr>
            <td style="padding:32px 32px 20px 32px;text-align:center;background:linear-gradient(135deg,#FFFDF9 0%,#F7F2E8 100%);border-bottom:1px solid #EFE9DF;">
              <div style="display:inline-block;width:52px;height:52px;line-height:52px;border-radius:16px;background-color:#1E1B18;color:#F5E6C8;font-size:24px;font-weight:800;letter-spacing:-0.5px;margin-bottom:14px;">LR</div>
              <div style="font-size:21px;font-weight:800;color:#1E1B18;letter-spacing:-0.3px;">Line Reader</div>
              <div style="font-size:13px;color:#786F66;margin-top:4px;">${subtitle}</div>
            </td>
          </tr>
          <tr>
            <td style="padding:32px;">
              <h1 style="margin:0 0 12px 0;font-size:20px;font-weight:800;color:#1E1B18;">${title}</h1>
              <p style="margin:0 0 10px 0;font-size:15px;line-height:1.6;color:#3D3731;font-weight:600;">${greeting}</p>
              <p style="margin:0 0 26px 0;font-size:14px;line-height:1.65;color:#5E554D;">${bodyCopy}</p>
              
              <!-- Kayıt ekranındaki kutucuklar yerine ortada şık BUTON -->
              <div style="background-color:#FAF7F2;border:1.5px dashed #D6CBB9;border-radius:18px;padding:26px 16px;text-align:center;margin-bottom:22px;">
                <div style="font-size:11px;text-transform:uppercase;letter-spacing:1.6px;color:#8C7F70;font-weight:700;margin-bottom:16px;">${isEnglish ? "PASSWORD RESET" : "ŞİFRE SIFIRLAMA"}</div>
                <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:0 auto;">
                  <tr>
                    <td align="center" style="border-radius:12px;background-color:#1E1B18;">
                      <a href="${link}" target="_blank" rel="noopener noreferrer" style="display:inline-block;padding:14px 38px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:15px;font-weight:700;color:#F5E6C8;text-decoration:none;border-radius:12px;letter-spacing:0.2px;">
                        ${buttonText}
                      </a>
                    </td>
                  </tr>
                </table>
              </div>

              <p style="margin:0 0 16px 0;font-size:12.5px;line-height:1.5;color:#786F66;text-align:center;">⏱️ ${validity}</p>
              
              <div style="padding-top:14px;border-top:1px solid #F0EAE1;">
                <p style="margin:0 0 6px 0;font-size:11px;color:#9E948A;">${fallbackText}</p>
                <a href="${link}" style="font-size:11px;color:#8A5A2B;word-break:break-all;text-decoration:underline;">${link}</a>
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 32px 26px 32px;background-color:#FAF8F5;border-top:1px solid #EFE9DF;text-align:center;">
              <p style="margin:0 0 8px 0;font-size:12px;line-height:1.5;color:#8C8278;">${footerNote}</p>
              <a href="https://getlinereader.com" style="font-size:12px;font-weight:700;color:#8A5A2B;text-decoration:none;">getlinereader.com</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

/* ---------------- Firebase Service Account & Identity Toolkit Köprüsü ---------------- */

const FIREBASE_SA_EMAIL = "firebase-adminsdk-fbsvc@line-reader-e2e00.iam.gserviceaccount.com";
const FIREBASE_SA_PRIVATE_KEY_PEM = `-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCXiWTh1Nyj2HOV
R9C+vqQ7cr9MOmNGopPu4EIlaA0e1DhO78Y+LfUvsREURP7Em527+tVW1duAgQ5V
qU77+dogxp6IIpjXCJ4MwDWtd6YQa0G30Tda0UeXTPgTuPNLrPto/ljuCNPPatda
6Yy7gz7ak7aNiBMRn7tHndfNHJd6+zK0m9YAadtKzegons5kRomH5+AciEbzajoW
t4WzG62w7MfnoEA0DTKrIotmhuGZ1DYppT8z9iq6uGFpGjddaMmAv4QTl+u8j1oB
J/brJWlV1/8wrfVoGKYFGzAO11ReDu1MDBcgdiFyvtcn5SkzXV0gSWxqRslOad4Z
f8+nPkLTAgMBAAECggEACyImDk2EVGlfvJUFKi55hICeu2wCxTrGoaNKWNM3O4+d
/3awWvsna3SX66RSD4Hbaec462NU+DEDK5n/2pV1yDivhxL7pbjVW9x3VSJYShaH
QokVhw+fMeeOxmwtO98erY0aXYq6fR+9aMmF9HTlFkwJ+oYH2KCistVO+JvkKT3U
f6QZb6fhhjJ80LF3EmARHYMEvC2gmh40O5f14wdJbBfP/6tPsMjOpaqFSBFgtBhh
+HLLaAw0+23cemAU3w01gBm57XUO0ZGMzuXl4hv/lW9Z6kI9AGFBveFkY2Q+zfTN
7+r3diQaxfbMgt/u1BhAxEd30u8neTPlfHRk5swMAQKBgQDGJBe6GNKuCNQi0Rlz
eVcPLTbXWEbrWfWY3mFnSTqAF6gQlADbsJybWsB/uTwWO3iOsUHFjLF1JgkvDHvm
dg97ddSHs3xosS5D75BeqvxCKkVivV9Q0YWnwRX+iIHlt33Vbq2amS9wLFQNAoby
Rggw+dPqir6yMcVsDcwq6JqE0wKBgQDDyW0i/SjYZhNX96VEmJJ2Y53T6HFhJHHm
S4T8mY+zuCVlUTav89yoMizT+sZd+oFmPjx1TVR/lRCanC03YFpkWz3RnobJ4gx6
KKER8y5TmE2U3kV7/R61yqHqgT/IYtpBxnWKc9cLwxBTtPLwX2zW135GQFmnVeI+
B4+hYo6KAQKBgQC5F5xGjsu4Ia0xfQ1+bnpiRgV18xQE5PtlO0/YMXMBl5e7LNcE
Yp5ZDdTHO52i0xlSisl7JmvbmJV5qvrPFbhux2qq/YMZNXKXqeG+XZHaqSw6CddR
Yvis9dV6+cAGfHuC9qobwj+rVO2LXbH7/mnGfop1DfkH8zCOOPFhn/pAWwKBgHC6
/vsBd046X/LrpZ48l0BRlWOZWAcN/AMVAqqLJMHfSrDutSVUrX2u/j7ECwm7nlwn
g5oq/3dCdj//os1azlEwdATJWWTOok6ILE3wjoEVlb4cyTdeBBu6Y8ZpyzbvLCpp
Qe6JSo38L99ytdsPptSBWbTLgpOmENGUeu/6loYBAoGBAJAPWPJhHhc6k0xejYPy
Xr521nWytr3EB7yNOFU78d7hOcjMD7dDS3ZNBScj2u8XxCd81BFmdru6yyyIuW2s
/egFhZt4t/EX6isY7vQpQ/6K3+aGDGO7cIO7X1DAXDhUvDmTO+RldpCRtT/7JPMK
r2HP+94LFEhhIbrE4LXSEPD4
-----END PRIVATE KEY-----`;

function strToBase64Url(str) {
  const bytes = new TextEncoder().encode(str);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToBinaryDer(pem) {
  const b64 = pem
    .replace(/-----BEGIN[ A-Z0-9_-]+-----/g, "")
    .replace(/-----END[ A-Z0-9_-]+-----/g, "")
    .replace(/\s+/g, "");
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) {
    buf[i] = raw.charCodeAt(i);
  }
  return buf.buffer;
}

let _cachedGoogleAccessToken = null;
let _cachedGoogleTokenExpiry = 0;

async function getGoogleIdentityToolkitAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (_cachedGoogleAccessToken && _cachedGoogleTokenExpiry > now + 120) {
    return _cachedGoogleAccessToken;
  }

  const pem = String(env?.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY || FIREBASE_SA_PRIVATE_KEY_PEM).trim();
  const clientEmail = String(env?.FIREBASE_SERVICE_ACCOUNT_EMAIL || FIREBASE_SA_EMAIL).trim();

  try {
    const derBuffer = pemToBinaryDer(pem);
    const cryptoKey = await crypto.subtle.importKey(
      "pkcs8",
      derBuffer,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"]
    );

    const header = { alg: "RS256", typ: "JWT" };
    const claim = {
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/identitytoolkit",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    };

    const signingInput = `${strToBase64Url(JSON.stringify(header))}.${strToBase64Url(JSON.stringify(claim))}`;
    const sigBuffer = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      cryptoKey,
      new TextEncoder().encode(signingInput)
    );

    const sigBytes = new Uint8Array(sigBuffer);
    let sigBinary = "";
    for (let i = 0; i < sigBytes.length; i++) {
      sigBinary += String.fromCharCode(sigBytes[i]);
    }
    const sigB64Url = btoa(sigBinary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

    const assertion = `${signingInput}.${sigB64Url}`;
    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${encodeURIComponent(assertion)}`,
    });

    if (!tokenRes.ok) {
      return null;
    }

    const tokenData = await tokenRes.json();
    _cachedGoogleAccessToken = tokenData.access_token;
    _cachedGoogleTokenExpiry = now + Number(tokenData.expires_in || 3600);
    return _cachedGoogleAccessToken;
  } catch (err) {
    return null;
  }
}

async function handlePasswordResetRequest(request, env) {
  let body = {};
  try {
    body = await request.json();
  } catch (_) {}

  const email = String(body?.email || "").trim().toLowerCase();
  if (!email || !email.includes("@")) {
    return jsonResponse(
      { ok: false, error: "invalid_email", message: "Geçerli bir e-posta adresi girin." },
      400
    );
  }

  const isEnglish = String(body?.lang || "tr").toLowerCase().startsWith("en");

  // Cooldown / Aşırı istek kontrolü
  if (env.DB) {
    try {
      await ensureSchema(env.DB);
      const nowMs = Date.now();
      const existing = await env.DB
        .prepare("SELECT last_sent_at FROM email_verification_codes WHERE email = ? LIMIT 1")
        .bind(email)
        .first();
      const lastSent = Number(existing?.last_sent_at || 0);
      const elapsedSec = Math.floor((nowMs - lastSent) / 1000);
      if (lastSent > 0 && elapsedSec < 45) {
        const waitSec = 45 - elapsedSec;
        return jsonResponse(
          {
            ok: false,
            error: "cooldown",
            cooldown_seconds: waitSec,
            message: isEnglish
              ? `Please wait ${waitSec}s before requesting a new password reset link.`
              : `Yeni şifre sıfırlama bağlantısı istemeden önce lütfen ${waitSec} saniye bekleyin.`,
          },
          429
        );
      }
    } catch (_) {}
  }

  try {
    // 1) Google OAuth2 access token al
    const accessToken = await getGoogleIdentityToolkitAccessToken(env);
    if (!accessToken) {
      return jsonResponse(
        { ok: false, error: "sa_token_failed", message: "Kimlik doğrulama anahtarı oluşturulamadı." },
        500
      );
    }

    // 2) Firebase Auth Identity Toolkit'ten güvenli şifre sıfırlama linkini (oobLink) üret
    const oobRes = await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/accounts:sendOobCode`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          requestType: "PASSWORD_RESET",
          email: email,
          returnOobLink: true,
        }),
      }
    );

    const oobData = await oobRes.json();
    if (!oobRes.ok || !oobData.oobLink) {
      const errCode = oobData?.error?.message || "";
      if (errCode === "EMAIL_NOT_FOUND") {
        // Güvenlik gereği kullanıcının kayıtlı olup olmadığını sızdırmadan başarılı mesajı ver
        return jsonResponse({
          ok: true,
          message: isEnglish
            ? "If an account exists for this email, a reset link was sent."
            : "Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.",
        });
      }
      return jsonResponse({ ok: false, error: "oob_link_failed", detail: errCode }, 500);
    }

    const oobLink = oobData.oobLink;

    // 3) Resend üzerinden özel tasarımlı HTML şablonuyla e-posta gönder
    const resendKey = String(env.RESEND_API_KEY || "").trim();
    if (!resendKey) {
      return jsonResponse({ ok: false, error: "email_provider_not_configured" }, 503);
    }

    const fromAddress = String(env.RESEND_FROM_EMAIL || "Line Reader <noreply@getlinereader.com>").trim();
    const subject = isEnglish
      ? "Reset your password for Line Reader"
      : "Line Reader Şifre Sıfırlama Talebiniz";

    const mailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromAddress,
        to: [email],
        subject,
        html: buildLineReaderPasswordResetEmailHtml({
          link: oobLink,
          email,
          isEnglish,
        }),
      }),
    });

    if (!mailRes.ok) {
      const errText = await mailRes.text();
      return jsonResponse({ ok: false, error: "email_send_failed", detail: errText.slice(0, 200) }, 502);
    }

    // Cooldown kaydı güncelle
    if (env.DB) {
      try {
        const nowMs = Date.now();
        await env.DB
          .prepare(`
            INSERT INTO email_verification_codes (email, uid, code_hash, expires_at, attempts, last_sent_at, created_at)
            VALUES (?, '', '', ?, 0, ?, ?)
            ON CONFLICT(email) DO UPDATE SET last_sent_at = excluded.last_sent_at
          `)
          .bind(email, nowMs + 3600000, nowMs, new Date(nowMs).toISOString())
          .run();
      } catch (_) {}
    }

    return jsonResponse({
      ok: true,
      message: isEnglish
        ? "Password reset link sent to your email."
        : "Şifre sıfırlama bağlantısı e-posta adresinize gönderildi.",
    });
  } catch (err) {
    return jsonResponse(
      { ok: false, error: "internal_error", detail: String(err?.message || err) },
      500
    );
  }
}

async function handleSendVerificationOtp(request, env, user) {
  if (!env || !env.DB) {
    return jsonResponse(
      { ok: false, error: "db_not_configured", message: "Veri tabanı bağlı değil." },
      503
    );
  }
  const resendKey = String(env.RESEND_API_KEY || "").trim();
  if (!resendKey) {
    return jsonResponse(
      {
        ok: false,
        fallback_to_firebase_link: true,
        error: "email_provider_not_configured",
        message: "Özel OTP e-posta servisi (RESEND_API_KEY) henüz yapılandırılmadı.",
      },
      503
    );
  }

  const email = String(user.email || "").trim().toLowerCase();
  if (!email || !email.includes("@")) {
    return jsonResponse({ ok: false, error: "invalid_email", message: "Geçerli e-posta bulunamadı." }, 400);
  }

  let body = {};
  try {
    body = await request.json();
  } catch (_) {}
  const isEnglish = String(body?.lang || "tr").toLowerCase().startsWith("en");

  try {
    await ensureSchema(env.DB);
    await upsertRegisteredUser(env.DB, user);

    const nowMs = Date.now();
    const existing = await env.DB
      .prepare("SELECT last_sent_at FROM email_verification_codes WHERE email = ? LIMIT 1")
      .bind(email)
      .first();

    const lastSent = Number(existing?.last_sent_at || 0);
    const elapsedSec = Math.floor((nowMs - lastSent) / 1000);
    if (lastSent > 0 && elapsedSec < 55) {
      const waitSec = 60 - elapsedSec;
      return jsonResponse(
        {
          ok: false,
          error: "cooldown",
          cooldown_seconds: waitSec,
          message: isEnglish
            ? `Please wait ${waitSec}s before requesting a new code.`
            : `Yeni kod istemeden önce lütfen ${waitSec} saniye bekleyin.`,
        },
        429
      );
    }

    const code = generateSixDigitOtp();
    const codeHash = await sha256Hex(`${email}:${code}`);
    const expiresAt = nowMs + 10 * 60 * 1000;

    await env.DB
      .prepare(`
        INSERT INTO email_verification_codes (email, uid, code_hash, expires_at, attempts, last_sent_at, created_at)
        VALUES (?, ?, ?, ?, 0, ?, ?)
        ON CONFLICT(email) DO UPDATE SET
          uid = excluded.uid,
          code_hash = excluded.code_hash,
          expires_at = excluded.expires_at,
          attempts = 0,
          last_sent_at = excluded.last_sent_at
      `)
      .bind(email, user.uid, codeHash, expiresAt, nowMs, new Date(nowMs).toISOString())
      .run();

    const fromAddress = String(env.RESEND_FROM_EMAIL || "Line Reader <noreply@getlinereader.com>").trim();
    const subject = isEnglish
      ? `${code} — Your Line Reader verification code`
      : `${code} — Line Reader doğrulama kodunuz`;

    const mailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromAddress,
        to: [email],
        subject,
        html: buildLineReaderOtpEmailHtml({
          code,
          displayName: user.displayName || "",
          isEnglish,
        }),
      }),
    });

    if (!mailRes.ok) {
      const errText = await mailRes.text();
      return jsonResponse(
        {
          ok: false,
          error: "email_send_failed",
          detail: errText.slice(0, 240),
          message: isEnglish
            ? "Could not send verification code email."
            : "Doğrulama kodu e-postası gönderilemedi.",
        },
        502
      );
    }

    return jsonResponse({
      ok: true,
      cooldown_seconds: 60,
      expires_in_seconds: 600,
      message: isEnglish
        ? "A 6-digit verification code has been sent to your email."
        : "6 haneli doğrulama kodu e-posta adresinize gönderildi.",
    });
  } catch (err) {
    return jsonResponse(
      { ok: false, error: "otp_send_error", message: String(err?.message || err) },
      500
    );
  }
}

async function handleVerifyEmailOtp(request, env, user) {
  if (!env || !env.DB) {
    return jsonResponse({ ok: false, error: "db_not_configured" }, 503);
  }
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonResponse({ ok: false, error: "invalid_json" }, 400);
  }

  const email = String(user.email || "").trim().toLowerCase();
  const rawCode = String(body?.code || "").replace(/\D/g, "").trim();
  const isEnglish = String(body?.lang || "tr").toLowerCase().startsWith("en");

  if (rawCode.length !== 6) {
    return jsonResponse(
      {
        ok: false,
        error: "invalid_format",
        message: isEnglish ? "Please enter the 6-digit code." : "Lütfen 6 haneli kodu girin.",
      },
      400
    );
  }

  try {
    await ensureSchema(env.DB);
    const row = await env.DB
      .prepare("SELECT code_hash, expires_at, attempts FROM email_verification_codes WHERE email = ? LIMIT 1")
      .bind(email)
      .first();

    if (!row) {
      return jsonResponse(
        {
          ok: false,
          error: "code_not_found",
          message: isEnglish
            ? "No active verification code found. Please request a new one."
            : "Aktif doğrulama kodu bulunamadı. Lütfen yeni kod isteyin.",
        },
        404
      );
    }

    if (Date.now() > Number(row.expires_at || 0)) {
      return jsonResponse(
        {
          ok: false,
          error: "code_expired",
          message: isEnglish
            ? "Verification code has expired. Please request a new one."
            : "Doğrulama kodunun süresi doldu. Lütfen yeni kod isteyin.",
        },
        400
      );
    }

    const attempts = Number(row.attempts || 0);
    if (attempts >= 5) {
      return jsonResponse(
        {
          ok: false,
          error: "too_many_attempts",
          message: isEnglish
            ? "Too many incorrect attempts. Please request a new code."
            : "Çok fazla hatalı deneme yapıldı. Lütfen yeni kod isteyin.",
        },
        429
      );
    }

    const expectedHash = String(row.code_hash || "");
    const submittedHash = await sha256Hex(`${email}:${rawCode}`);
    if (submittedHash !== expectedHash) {
      await env.DB
        .prepare("UPDATE email_verification_codes SET attempts = attempts + 1 WHERE email = ?")
        .bind(email)
        .run();
      return jsonResponse(
        {
          ok: false,
          error: "invalid_code",
          message: isEnglish
            ? "Incorrect verification code. Please check and try again."
            : "Girdiğiniz kod hatalı. Lütfen kontrol edip tekrar deneyin.",
        },
        400
      );
    }

    await env.DB.batch([
      env.DB
        .prepare("UPDATE registered_users SET email_verified = 1, last_seen_at = ? WHERE LOWER(email) = ?")
        .bind(new Date().toISOString(), email),
      env.DB
        .prepare("DELETE FROM email_verification_codes WHERE email = ?")
        .bind(email),
    ]);

    return jsonResponse({
      ok: true,
      email_verified: true,
      message: isEnglish ? "Email verified!" : "E-posta doğrulandı!",
    });
  } catch (err) {
    return jsonResponse(
      { ok: false, error: "otp_verify_error", message: String(err?.message || err) },
      500
    );
  }
}

async function handleRedeemCode(request, env, user) {
  if (!env || !env.DB) {
    return jsonResponse(
      { ok: false, error: "db_not_configured", message: "Yetki veri tabanı henüz bağlanmadı." },
      503
    );
  }

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonResponse({ ok: false, error: "invalid_json", message: "Geçersiz istek." }, 400);
  }

  const rawCode = String(body?.code || "").trim().toUpperCase();
  if (!rawCode || rawCode.length < 3 || rawCode.length > 48) {
    return jsonResponse(
      { ok: false, error: "invalid_code", message: "Lütfen geçerli bir aktivasyon kodu girin." },
      400
    );
  }

  await ensureSchema(env.DB);
  const email = (user.email || "").trim().toLowerCase() || `uid:${user.uid}`;

  // Zaten sınırsız yetkiliyse kodun hakkını tüketmeden bilgi dön.
  const currentEnt = await getUserEntitlement(env.DB, user);
  if (currentEnt.isUnlimited) {
    return jsonResponse({
      ok: true,
      already_unlimited: true,
      is_unlimited: true,
      code: currentEnt.codeUsed,
      message: "Hesabınızda zaten sınırsız yetki aktif.",
    });
  }

  const existingCode = await env.DB
    .prepare("SELECT code, max_uses, used_count, is_active FROM access_codes WHERE code = ? LIMIT 1")
    .bind(rawCode)
    .first();

  if (!existingCode || Number(existingCode.is_active) !== 1) {
    return jsonResponse(
      { ok: false, error: "code_not_found", message: "Geçersiz veya devre dışı bırakılmış kod." },
      404
    );
  }

  if (Number(existingCode.used_count) >= Number(existingCode.max_uses)) {
    return jsonResponse(
      { ok: false, error: "code_exhausted", message: "Bu kodun kullanım hakkı dolmuş." },
      409
    );
  }

  // Atomik artış: aynı anda 2 kişi son hakkı kullanmaya çalışsa bile sadece 1'i başarılı olur.
  const updateRes = await env.DB
    .prepare(
      "UPDATE access_codes SET used_count = used_count + 1 WHERE code = ? AND is_active = 1 AND used_count < max_uses"
    )
    .bind(rawCode)
    .run();

  const changed = updateRes?.meta?.changes ?? 0;
  if (changed < 1) {
    return jsonResponse(
      { ok: false, error: "code_exhausted", message: "Bu kodun kullanım hakkı dolmuş." },
      409
    );
  }

  const nowIso = new Date().toISOString();
  await env.DB.batch([
    env.DB
      .prepare(`
        INSERT INTO user_entitlements (email, uid, is_unlimited, source, code_used, granted_at)
        VALUES (?, ?, 1, 'code', ?, ?)
        ON CONFLICT(email) DO UPDATE SET
          uid = excluded.uid,
          is_unlimited = 1,
          source = 'code',
          code_used = excluded.code_used,
          granted_at = excluded.granted_at
      `)
      .bind(email, user.uid, rawCode, nowIso),
    env.DB
      .prepare(`
        INSERT OR IGNORE INTO code_redemptions (code, email, uid, redeemed_at)
        VALUES (?, ?, ?, ?)
      `)
      .bind(rawCode, email, user.uid, nowIso),
  ]);

  return jsonResponse({
    ok: true,
    already_unlimited: false,
    is_unlimited: true,
    code: rawCode,
    message: "Kod onaylandı! Sınırsız çeviri, reklamsız kullanım ve Tarayıcı AI aktif.",
  });
}

/* ---------------- Kullanıcı Bulut Senkronizasyonu (D1 Tabanlı) ---------------- */

async function handleUserCloudSyncGet(request, env, user) {
  if (!env || !env.DB) {
    return jsonResponse({ ok: false, error: "db_not_configured" }, 503);
  }
  await ensureSchema(env.DB);
  const uid = String(user.uid || "").trim();
  if (!uid) {
    return jsonResponse({ ok: false, error: "invalid_user" }, 400);
  }

  const row = await env.DB
    .prepare("SELECT saved_words_json, word_lists_json, reading_progress_json, preferences_json, updated_at FROM user_cloud_sync WHERE uid = ? LIMIT 1")
    .bind(uid)
    .first();

  if (!row) {
    return jsonResponse({
      ok: true,
      exists: false,
      saved_words: [],
      word_lists: [],
      reading_progress: {},
      preferences: {},
      updated_at: null,
    });
  }

  return jsonResponse({
    ok: true,
    exists: true,
    saved_words: JSON.parse(row.saved_words_json || "[]"),
    word_lists: JSON.parse(row.word_lists_json || "[]"),
    reading_progress: JSON.parse(row.reading_progress_json || "{}"),
    preferences: JSON.parse(row.preferences_json || "{}"),
    updated_at: row.updated_at,
  });
}

async function handleUserCloudSyncPost(request, env, user) {
  if (!env || !env.DB) {
    return jsonResponse({ ok: false, error: "db_not_configured" }, 503);
  }
  await ensureSchema(env.DB);
  const uid = String(user.uid || "").trim();
  const email = String(user.email || "").trim().toLowerCase();
  if (!uid) {
    return jsonResponse({ ok: false, error: "invalid_user" }, 400);
  }

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonResponse({ ok: false, error: "invalid_json" }, 400);
  }

  const nowIso = new Date().toISOString();
  const wordsJson = JSON.stringify(body?.saved_words || []);
  const listsJson = JSON.stringify(body?.word_lists || []);
  const progressJson = JSON.stringify(body?.reading_progress || {});
  const prefsJson = JSON.stringify(body?.preferences || {});

  await env.DB
    .prepare(`
      INSERT INTO user_cloud_sync (uid, email, saved_words_json, word_lists_json, reading_progress_json, preferences_json, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(uid) DO UPDATE SET
        email = excluded.email,
        saved_words_json = excluded.saved_words_json,
        word_lists_json = excluded.word_lists_json,
        reading_progress_json = excluded.reading_progress_json,
        preferences_json = excluded.preferences_json,
        updated_at = excluded.updated_at
    `)
    .bind(uid, email, wordsJson, listsJson, progressJson, prefsJson, nowIso)
    .run();

  return jsonResponse({
    ok: true,
    updated_at: nowIso,
    message: "Veriler bulutla senkronize edildi.",
  });
}

/* ---------------- Tarayıcı AI Çevirisi (Yalnızca Yetkili Kullanıcı) ---------------- */

async function handleBrowserAiTranslate(request, env, user) {
  if (!env || !env.AI) {
    return jsonResponse({ error: "ai_binding_missing" }, 503);
  }

  // D1 bağlıysa yalnızca yetkili (is_unlimited = 1) kullanıcılara AI aç.
  if (env.DB) {
    const ent = await getUserEntitlement(env.DB, user);
    if (!ent.isUnlimited) {
      return jsonResponse(
        { error: "entitlement_required", message: "Tarayıcı AI yalnızca yetkili kullanıcılar içindir." },
        403
      );
    }
  }

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const word = String(body?.word || "").trim().slice(0, 64);
  const contextSentence = String(body?.context_sentence || "").trim().slice(0, 420);
  if (!word) {
    return jsonResponse({ error: "word_required" }, 400);
  }

  try {
    const result = await translateWithWorkersAi(env.AI, word, contextSentence);
    if (!result || !Array.isArray(result.meanings) || result.meanings.length === 0) {
      return jsonResponse({ error: "empty_ai_response" }, 502);
    }

    return jsonResponse({
      word,
      meanings: result.meanings,
      source: "cloudflare_workers_ai",
    });
  } catch (err) {
    const lower = String(err?.message || err || "").toLowerCase();
    if (
      lower.includes("429") ||
      lower.includes("quota") ||
      lower.includes("limit") ||
      lower.includes("neuron") ||
      lower.includes("rate")
    ) {
      return jsonResponse({ error: "quota_exceeded" }, 429);
    }
    return jsonResponse({ error: "ai_unavailable" }, 503);
  }
}

/* ---------------- Mobil Geliştirici Paneli (Firebase Token + D1 Admin Doğrulamalı) ---------------- */

async function handleDeveloperPanelRequest(request, env, verifiedUser, path, method) {
  if (!env || !env.DB) {
    return jsonResponse({ ok: false, error: "db_not_configured", message: "D1 veritabanı bağlı değil." }, 503);
  }

  await ensureSchema(env.DB);
  const callerEnt = await getUserEntitlement(env.DB, verifiedUser);
  const isDeveloper = callerEnt.isUnlimited && String(callerEnt.source || "").toLowerCase() === "admin";
  if (!isDeveloper) {
    return jsonResponse({
      ok: false,
      error: "developer_required",
      message: "Bu işlem yalnızca Geliştirici rolündeki hesaplara açıktır.",
    }, 403);
  }

  const callerEmail = String(verifiedUser.email || verifiedUser.uid || "dev").trim().toLowerCase();

  // 1) Tüm kayıtlı kullanıcılar + Premium & Özel Tema yönetimi
  if (path === "/dev/users") {
    if (method === "GET") {
      const users = await listAllUsersWithEntitlements(env.DB);
      return jsonResponse({ ok: true, users });
    }

    const body = await safeReadJson(request);
    const email = String(body?.email || "").trim().toLowerCase();
    if (!email || !email.includes("@")) {
      return jsonResponse({ ok: false, message: "Geçerli bir e-posta adresi girin." }, 400);
    }

    const existing = await env.DB
      .prepare("SELECT email, is_unlimited, source, has_special_themes FROM user_entitlements WHERE LOWER(email) = ? LIMIT 1")
      .bind(email)
      .first();

    // Bağımsız Özel Tema bayrağı güncelleme (Premium/Üye durumunu bozmaz)
    if (method === "POST" && (body?.action === "set_special_themes" || typeof body?.has_special_themes === "boolean")) {
      const enabled = body?.has_special_themes === true || body?.enabled === true;
      const flag = enabled ? 1 : 0;
      if (enabled) {
        await env.DB
          .prepare(`
            INSERT INTO user_entitlements (email, uid, is_unlimited, source, code_used, granted_at, has_special_themes)
            VALUES (?, NULL, 0, 'special_themes', NULL, ?, 1)
            ON CONFLICT(email) DO UPDATE SET
              has_special_themes = 1
          `)
          .bind(email, new Date().toISOString())
          .run();
      } else {
        await env.DB
          .prepare("UPDATE user_entitlements SET has_special_themes = 0 WHERE LOWER(email) = ?")
          .bind(email)
          .run();
        await env.DB
          .prepare("DELETE FROM user_entitlements WHERE LOWER(email) = ? AND is_unlimited = 0 AND has_special_themes = 0")
          .bind(email)
          .run();
      }
      return jsonResponse({
        ok: true,
        has_special_themes: flag === 1,
        message: enabled
          ? `${email} hesabına Özel Temalar yetkisi verildi.`
          : `${email} hesabının Özel Temalar yetkisi kaldırıldı.`,
      });
    }

    if (existing && String(existing.source || "").toLowerCase() === "admin") {
      return jsonResponse({
        ok: false,
        error: "protected_role",
        message: "Geliştirici hesaplarının rolü yalnızca PC Yönetim Panelinden değiştirilebilir.",
      }, 403);
    }

    if (method === "POST") {
      await env.DB
        .prepare(`
          INSERT INTO user_entitlements (email, uid, is_unlimited, source, code_used, granted_at, has_special_themes)
          VALUES (?, NULL, 1, 'manual', ?, ?, 0)
          ON CONFLICT(email) DO UPDATE SET
            is_unlimited = 1,
            source = 'manual',
            code_used = excluded.code_used,
            granted_at = excluded.granted_at
        `)
        .bind(email, `dev:${callerEmail}`, new Date().toISOString())
        .run();
      return jsonResponse({
        ok: true,
        role: "premium",
        message: `${email} hesabına Premium Üye yetkisi verildi.`,
      });
    }

    if (method === "DELETE") {
      if (existing && Number(existing.has_special_themes) === 1) {
        await env.DB
          .prepare("UPDATE user_entitlements SET is_unlimited = 0, source = 'special_themes', code_used = NULL WHERE LOWER(email) = ? AND LOWER(source) != 'admin'")
          .bind(email)
          .run();
      } else {
        await env.DB
          .prepare("DELETE FROM user_entitlements WHERE LOWER(email) = ? AND LOWER(source) != 'admin'")
          .bind(email)
          .run();
      }
      return jsonResponse({
        ok: true,
        message: `${email} hesabının Premium yetkisi kaldırıldı.`,
      });
    }
  }

  // 2) Aktivasyon kodu üretme ve yönetimi
  if (path === "/dev/codes") {
    if (method === "GET") {
      const res = await env.DB
        .prepare("SELECT code, max_uses, used_count, is_active, note, created_at FROM access_codes ORDER BY created_at DESC")
        .all();
      return jsonResponse({ ok: true, codes: res.results || [] });
    }

    const body = await safeReadJson(request);
    const code = String(body?.code || "").trim().toUpperCase().replace(/[^A-Z0-9_-]/g, "");

    if (method === "POST") {
      if (code.length < 4 || code.length > 32) {
        return jsonResponse({ ok: false, message: "Kod 4 ile 32 karakter arasında olmalıdır." }, 400);
      }
      const maxUses = Math.max(1, Math.min(100000, parseInt(body?.max_uses ?? 1, 10) || 1));
      const rawNote = String(body?.note || "").trim().slice(0, 120);
      const note = rawNote ? `${rawNote} (by ${callerEmail})` : `Geliştirici: ${callerEmail}`;

      await env.DB
        .prepare(`
          INSERT INTO access_codes (code, max_uses, used_count, is_active, note, created_at)
          VALUES (?, ?, 0, 1, ?, ?)
          ON CONFLICT(code) DO UPDATE SET
            max_uses = excluded.max_uses,
            is_active = 1,
            note = excluded.note
        `)
        .bind(code, maxUses, note, new Date().toISOString())
        .run();
      return jsonResponse({ ok: true, code, message: `${code} kodu oluşturuldu (${maxUses} kullanım).` });
    }

    if (method === "PATCH") {
      if (!code) {
        return jsonResponse({ ok: false, message: "Kod adı gerekli." }, 400);
      }
      const isActive = body?.is_active ? 1 : 0;
      await env.DB
        .prepare("UPDATE access_codes SET is_active = ? WHERE code = ?")
        .bind(isActive, code)
        .run();
      return jsonResponse({
        ok: true,
        message: `${code} ${isActive ? "aktif edildi" : "pasife alındı"}.`,
      });
    }

    if (method === "DELETE") {
      if (!code) {
        return jsonResponse({ ok: false, message: "Silinecek kod adı gerekli." }, 400);
      }
      await env.DB.prepare("DELETE FROM access_codes WHERE code = ?").bind(code).run();
      return jsonResponse({ ok: true, message: `${code} kodu silindi.` });
    }
  }

  // 3) Mobil Makale Üretme, Podcast AI Ses & Anında Yayınlama
  if (path === "/dev/articles") {
    if (method === "GET") {
      const list = await loadArticlesList(env);
      const summary = list.map((a) => ({
        id: a.id,
        level: a.level,
        title: a.title,
        published_at: a.published_at || null,
        is_hidden: Boolean(a.is_hidden),
        publish_at: a.publish_at || null,
        has_audio: Boolean(a.audio_url && String(a.audio_url).trim().length > 0),
        has_relations: Boolean(
          a.word_relations &&
          typeof a.word_relations === "object" &&
          Object.keys(a.word_relations).length > 0
        ),
        has_description: Boolean(a.description && String(a.description).trim().length > 0),
        audio_url: a.audio_url || null,
      }));
      return jsonResponse({
        ok: true,
        articles: summary,
        has_gemini_key: Boolean(env.GEMINI_API_KEY),
        has_github_token: Boolean(env.GITHUB_TOKEN),
      });
    }

    const body = await safeReadJson(request);
    const id = String(body?.id || "").trim();
    if (!id) {
      return jsonResponse({ ok: false, message: "Makale kimliği (id) gerekli." }, 400);
    }

    if (method === "PATCH") {
      const list = await loadArticlesList(env);
      const idx = list.findIndex((a) => String(a?.id || "") === id);
      if (idx === -1) {
        return jsonResponse({ ok: false, message: "Makale bulunamadı." }, 404);
      }
      if (typeof body?.is_hidden === "boolean") {
        list[idx].is_hidden = body.is_hidden;
      }
      if (body && Object.prototype.hasOwnProperty.call(body, "publish_at")) {
        list[idx].publish_at = body.publish_at || null;
      }
      await saveArticlesList(env, list, `Update article ${id} from mobile dev panel`);
      return jsonResponse({
        ok: true,
        message: list[idx].is_hidden ? "Makale gizlendi." : "Makale görünür yapıldı.",
      });
    }

    if (method === "DELETE") {
      const list = await loadArticlesList(env);
      const next = list.filter((a) => String(a?.id || "") !== id);
      if (next.length === list.length) {
        return jsonResponse({ ok: false, message: "Makale bulunamadı." }, 404);
      }
      await saveArticlesList(env, next, `Delete article ${id} from mobile dev panel`);
      return jsonResponse({ ok: true, message: "Makale silindi." });
    }
  }

  if (path === "/dev/articles/generate" && method === "POST") {
    const body = await safeReadJson(request);
    const rawLevel = String(body?.level || "B1").trim().toUpperCase();
    const level = ["A1", "A2", "B1", "B2", "C1", "C2"].includes(rawLevel) ? rawLevel : "B1";
    const topic = String(body?.topic || "").trim().slice(0, 160);
    try {
      const generated = await generateArticleResilient(env, level, topic);
      return jsonResponse({ ok: true, article: generated });
    } catch (err) {
      return jsonResponse({
        ok: false,
        error: "article_generate_failed",
        message: `Makale üretilemedi: ${String(err?.message || err)}`,
      }, 502);
    }
  }

  if (path === "/dev/articles/audio" && method === "POST") {
    if (!env.GEMINI_API_KEY) {
      return jsonResponse({
        ok: false,
        error: "gemini_key_missing",
        message: "Cloudflare Worker içinde GEMINI_API_KEY tanımlı değil.",
      }, 503);
    }
    if (!env.GITHUB_TOKEN) {
      return jsonResponse({
        ok: false,
        error: "github_token_missing",
        message: "Podcast sesini kaydetmek için Cloudflare Worker içinde GITHUB_TOKEN tanımlayın.",
      }, 503);
    }
    const body = await safeReadJson(request);
    const articleId = slugifyArticleId(String(body?.id || body?.title || "article"));
    const title = String(body?.title || "").trim();
    const content = String(body?.content || "").trim();
    const voice = String(body?.voice || "Kore").trim() || "Kore";
    if (!content || content.length < 30) {
      return jsonResponse({ ok: false, message: "Ses üretmek için geçerli makale metni gerekli." }, 400);
    }
    try {
      const audioMeta = await generatePodcastAudioWithGemini(env, articleId, title, content, voice);
      return jsonResponse({
        ok: true,
        ...audioMeta,
        message: `Podcast AI sesi oluşturuldu (${audioMeta.audio_duration_sec} sn).`,
      });
    } catch (err) {
      return jsonResponse({
        ok: false,
        error: "tts_generate_failed",
        message: `Podcast sesi üretilemedi: ${String(err?.message || err)}`,
      }, 502);
    }
  }

  if (path === "/dev/articles/publish" && method === "POST") {
    const body = await safeReadJson(request);
    const rawArticle = body?.article;
    if (!rawArticle || typeof rawArticle !== "object") {
      return jsonResponse({ ok: false, message: "Yayınlanacak makale verisi eksik." }, 400);
    }
    const level = String(rawArticle.level || "B1").trim().toUpperCase();
    const title = String(rawArticle.title || "").trim();
    const content = String(rawArticle.content || "").trim();
    if (!title || content.length < 30) {
      return jsonResponse({ ok: false, message: "Başlık ve makale metni boş olamaz." }, 400);
    }
    const id = String(rawArticle.id || "").trim() || `${level.toLowerCase()}-${slugifyArticleId(title)}`;
    const wordCount = content.split(/\s+/).filter(Boolean).length;
    const readingMin = Math.max(1, Math.round(wordCount / 145));
    const readingTime = readingMin <= 1 ? "1 - 2 dk" : `${readingMin} - ${readingMin + 1} dk`;
    const description =
      String(rawArticle.description || "").trim() || buildFallbackDescription(content);
    const category =
      String(rawArticle.category || "").trim() || inferArticleCategory(title, content);
    const author = String(rawArticle.author || "").trim() || "Line Reader";
    const publishedAt =
      String(rawArticle.published_at || "").trim() || new Date().toISOString();
    const imageUrl =
      String(rawArticle.image_url || rawArticle.imageUrl || "").trim() ||
      resolveTopicImageUrl(title, category, content);

    const articleObj = {
      id,
      level,
      title,
      description,
      image_url: imageUrl,
      reading_time: String(rawArticle.reading_time || "").trim() || readingTime,
      reading_time_minutes: Number(rawArticle.reading_time_minutes) || readingMin,
      language: String(rawArticle.language || "en").trim() || "en",
      content,
      published_at: publishedAt,
      category,
      author,
      word_meanings: rawArticle.word_meanings && typeof rawArticle.word_meanings === "object" ? rawArticle.word_meanings : {},
      sentence_translations: rawArticle.sentence_translations && typeof rawArticle.sentence_translations === "object" ? rawArticle.sentence_translations : {},
      word_relations: rawArticle.word_relations && typeof rawArticle.word_relations === "object" ? rawArticle.word_relations : {},
      ...(rawArticle.audio_url ? { audio_url: String(rawArticle.audio_url).trim() } : {}),
      ...(rawArticle.audio_voice ? { audio_voice: String(rawArticle.audio_voice).trim() } : {}),
      ...(rawArticle.audio_duration_sec ? { audio_duration_sec: Number(rawArticle.audio_duration_sec) } : {}),
      ...(Array.isArray(rawArticle.audio_segments) && rawArticle.audio_segments.length > 0
        ? { audio_segments: rawArticle.audio_segments }
        : {}),
      is_hidden: Boolean(rawArticle.is_hidden),
      ...(rawArticle.publish_at ? { publish_at: String(rawArticle.publish_at).trim() } : {}),
    };

    const list = await loadArticlesList(env);
    const existingIdx = list.findIndex((a) => String(a?.id || "") === id);
    if (existingIdx >= 0) {
      list[existingIdx] = articleObj;
    } else {
      list.push(articleObj);
    }

    const syncInfo = await saveArticlesList(env, list, `Publish article ${id} from mobile dev panel`);
    return jsonResponse({
      ok: true,
      id,
      count: list.length,
      github_synced: syncInfo.githubSynced,
      message: articleObj.is_hidden
        ? `"${title}" gizli olarak kaydedildi.`
        : `"${title}" anında yayınlandı!`,
    });
  }

  // 4) Otomatik Günlük Yayın Planlayıcı Ayarları (A1-C2 İki Aşamalı Sistem)
  if (path === "/dev/schedule") {
    if (method === "GET") {
      let cfg = await env.DB
        .prepare("SELECT is_enabled, publish_hour, timezone_offset, last_prepared_date, last_published_date, updated_at FROM publish_schedule_config WHERE id = 1 LIMIT 1")
        .first();
      if (!cfg) {
        cfg = {
          is_enabled: 1,
          publish_hour: 9,
          timezone_offset: 3,
          last_prepared_date: null,
          last_published_date: null,
          updated_at: new Date().toISOString(),
        };
      }
      const tzOffset = Number(cfg.timezone_offset ?? 3);
      const localNow = new Date(Date.now() + tzOffset * 3600 * 1000);
      const serverTimeTr = `${String(localNow.getUTCHours()).padStart(2, "0")}:${String(localNow.getUTCMinutes()).padStart(2, "0")}`;
      const pubHour = Number(cfg.publish_hour ?? 9);
      const preHour = (pubHour - 1 + 24) % 24;

      return jsonResponse({
        ok: true,
        config: {
          is_enabled: Boolean(cfg.is_enabled),
          publish_hour: pubHour,
          timezone_offset: tzOffset,
          last_prepared_date: cfg.last_prepared_date || null,
          last_published_date: cfg.last_published_date || null,
          updated_at: cfg.updated_at || null,
        },
        server_time_tr: serverTimeTr,
        schedule_summary: `Her gün saat ${String(pubHour).padStart(2, "0")}:00'da yayınlanır (${String(preHour).padStart(2, "0")}:15'te A1-C2 tüm 6 seviye önceden hazırlanıp gizlenir).`,
      });
    }

    if (method === "POST") {
      const body = await safeReadJson(request);
      const isEnabled = body?.is_enabled !== false ? 1 : 0;
      let pubHour = parseInt(body?.publish_hour ?? 9, 10);
      if (isNaN(pubHour) || pubHour < 0 || pubHour > 23) pubHour = 9;
      let tzOffset = parseInt(body?.timezone_offset ?? 3, 10);
      if (isNaN(tzOffset) || tzOffset < -12 || tzOffset > 14) tzOffset = 3;

      await env.DB
        .prepare(`
          INSERT INTO publish_schedule_config (id, is_enabled, publish_hour, timezone_offset, updated_at)
          VALUES (1, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            is_enabled = excluded.is_enabled,
            publish_hour = excluded.publish_hour,
            timezone_offset = excluded.timezone_offset,
            updated_at = excluded.updated_at
        `)
        .bind(isEnabled, pubHour, tzOffset, new Date().toISOString())
        .run();

      const preHour = (pubHour - 1 + 24) % 24;
      return jsonResponse({
        ok: true,
        message: isEnabled
          ? `Otomatik yayın saati ${String(pubHour).padStart(2, "0")}:00 olarak ayarlandı (Hazırlık: ${String(preHour).padStart(2, "0")}:15).`
          : "Otomatik günlük yayınlama devre dışı bırakıldı.",
      });
    }
  }

  // 5) Planlayıcıyı Manuel Tetikleme (Test & Anında Çalıştırma)
  if (path === "/dev/schedule/run-now" && method === "POST") {
    const body = await safeReadJson(request);
    const mode = String(body?.mode || "full_pipeline").trim(); // 'prebake' | 'publish' | 'full_pipeline'
    const result = await handleScheduledPublishRun(env, "manual", mode);
    return jsonResponse({
      ok: true,
      result,
      message: `Planlayıcı test çalışması tamamlandı (Mod: ${mode}).`,
    });
  }

  // 6) Yapay zekaya sıfırdan makale yazdırma kapatıldı
  if (path === "/dev/articles/quick-publish" && method === "POST") {
    return jsonResponse(
      {
        ok: false,
        error: "ai_generation_disabled",
        message: "Yapay zekaya sıfırdan makale yazdırma sistemi kapatıldı. Lütfen Manuel Makale Ekle arayüzünü kullanın.",
      },
      410
    );
  }

  return jsonResponse({ ok: false, error: "not_found" }, 404);
}

const GITHUB_REPO_OWNER = "MustafaAyaz21";
const GITHUB_REPO_NAME = "line_reader";
const GITHUB_ARTICLES_RAW_URL = `https://raw.githubusercontent.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/main/articles.json`;

function slugifyArticleId(raw) {
  const cleaned = String(raw || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 52);
  return cleaned || `article-${Date.now()}`;
}

function extractArticlesArray(parsed) {
  if (Array.isArray(parsed)) return parsed;
  if (parsed && typeof parsed === "object" && Array.isArray(parsed.articles)) {
    return parsed.articles;
  }
  return null;
}

async function loadArticlesList(env) {
  if (env && env.DB) {
    try {
      await ensureSchema(env.DB);
      const row = await env.DB
        .prepare("SELECT payload_json FROM articles_feed WHERE id = 1 LIMIT 1")
        .first();
      if (row && row.payload_json) {
        const parsed = JSON.parse(row.payload_json);
        const list = extractArticlesArray(parsed);
        if (list) return list;
      }
    } catch (_) {}
  }

  try {
    const res = await fetch(`${GITHUB_ARTICLES_RAW_URL}?t=${Date.now()}`);
    if (res.ok) {
      const parsed = await res.json();
      const list = extractArticlesArray(parsed);
      if (list) return list;
    }
  } catch (_) {}

  return [];
}

async function saveArticlesList(env, articles, commitMessage) {
  const envelope = {
    version: 1,
    updated_at: new Date().toISOString(),
    articles,
  };
  const payloadText = JSON.stringify(envelope, null, 2);
  const etag = `"articles-${Date.now()}-${payloadText.length}"`;
  await ensureSchema(env.DB);
  await env.DB
    .prepare(`
      INSERT INTO articles_feed (id, payload_json, etag, updated_at)
      VALUES (1, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        payload_json = excluded.payload_json,
        etag = excluded.etag,
        updated_at = excluded.updated_at
    `)
    .bind(payloadText, etag, new Date().toISOString())
    .run();

  let githubSynced = false;
  if (env.GITHUB_TOKEN) {
    try {
      const bytes = new TextEncoder().encode(payloadText);
      await upsertGitHubFile(
        String(env.GITHUB_TOKEN).trim(),
        "articles.json",
        bytesToBase64(bytes),
        commitMessage || "Update articles.json from mobile dev panel"
      );
      githubSynced = true;
    } catch (_) {}
  }
  return { etag, githubSynced };
}

async function generateArticleResilient(env, level, topic) {
  let geminiErr = null;
  if (env && env.GEMINI_API_KEY) {
    try {
      return await generateArticleWithGemini(String(env.GEMINI_API_KEY).trim(), level, topic);
    } catch (err) {
      geminiErr = err;
    }
  }
  if (env && env.AI) {
    try {
      return await generateArticleWithWorkersAi(env.AI, level, topic);
    } catch (aiErr) {
      throw new Error(
        `Gemini ve Cloudflare AI yanıt vermedi (${String(geminiErr?.message || "")} | ${String(aiErr?.message || aiErr)})`
      );
    }
  }
  throw geminiErr || new Error("GEMINI_API_KEY veya Workers AI yapılandırılmamış.");
}

const CURATED_ENGAGING_TOPICS = [
  // Bilim ve Evren
  "The bizarre physics of neutron stars where a single teaspoon weighs a billion tons",
  "The James Webb Space Telescope discovering the earliest galaxies in our universe",
  "The mystery of ocean worlds: Hunting for alien life under the icy crust of Europa and Enceladus",
  "Why time slows down near black holes: Einstein's general relativity explained simply",
  // Psikoloji ve İnsan Beyni
  "The Neuroscience of Déjà Vu: Why your brain tricks you into feeling you have lived this before",
  "The Psychology of Music: Why sad songs provide comfort and trigger goosebumps",
  "The Paradox of Choice: Why having too many options makes modern humans less happy",
  "How bilingualism reshapes the human brain structure and slows cognitive aging",
  "The science of sleep: What happens to our memories and cells during deep REM sleep",
  "The flow state: How high performers enter the zone of peak productivity",
  // Sıradışı Doğa ve Canlılar
  "The Wood Wide Web: The secret underground fungal network connecting forest trees",
  "Creatures of the abyss: How deep-sea animals thrive under crushing pressure in the Mariana Trench",
  "The extraordinary navigational superpowers of migrating monarch butterflies and birds",
  "The surprising intelligence of octopuses and their nine distributed brains",
  // Gelecek ve Teknoloji
  "How brain-computer interfaces are helping paralyzed patients walk and speak again",
  "Can artificial intelligence ever develop genuine human consciousness and emotions?",
  "The revolutionary science of lab-grown meat and vertical farming",
  // Gizemli Tarih ve İnsan Dayanıklılığı
  "The lost engineering secrets of Roman concrete that grew stronger inside seawater for millennia",
  "The Library of Alexandria: How ancient scholars calculated Earth's circumference with shadows",
  "The Voynich Manuscript: The unsolved 600-year-old mystery book that nobody can decipher",
  "The incredible story of Ernest Shackleton's Antarctic survival against impossible odds",
];

function pickEngagingTopic(level) {
  const seed = Math.floor(Math.random() * CURATED_ENGAGING_TOPICS.length);
  return CURATED_ENGAGING_TOPICS[seed];
}

function buildArticleGenerationPrompt(level, topic, targetWordCount = null) {
  const chosenTopic = topic || pickEngagingTopic(level);
  const topicInstruction = `Write the article specifically about this captivating topic: "${chosenTopic}".`;

  const parsedTarget = Number(targetWordCount);
  const effectiveWords =
    Number.isFinite(parsedTarget) && parsedTarget >= 100 && parsedTarget <= 1500
      ? Math.round(parsedTarget)
      : ({ A1: 180, A2: 230, B1: 300, B2: 350, C1: 380, C2: 400 }[level] || 320);

  const minWords = Math.max(95, Math.round(effectiveWords * 0.95));
  const maxWords = Math.round(effectiveWords * 1.18);
  const targetParas = Math.max(3, Math.min(8, Math.round(effectiveWords / 72)));
  const wordsPerPara = Math.round(effectiveWords / targetParas);
  const sentencesPerPara = wordsPerPara >= 75 ? "4 to 5" : "3 to 4";
  const paraCount = `EXACTLY ${targetParas} well-developed paragraphs (each paragraph MUST contain ${sentencesPerPara} full, detailed sentences — about ${wordsPerPara} words per paragraph)`;

  const levelStyle = {
    A1: "simple everyday vocabulary and short clear sentences",
    A2: "clear pre-intermediate vocabulary and straightforward connected sentences",
    B1: "natural intermediate English with clear flow",
    B2: "rich upper-intermediate English with vivid details",
    C1: "sophisticated advanced English with nuanced arguments",
    C2: "nuanced, idiomatic mastery-level English",
  }[level] || "natural intermediate English";

  return [
    `You are an expert English curriculum author creating a CEFR ${level} reading article for Turkish learners of English.`,
    topicInstruction,
    `MANDATORY LENGTH & STRUCTURE: Write AT LEAST ${effectiveWords} words (strictly between ${minWords} and ${maxWords} words) across ${paraCount}, separated by \\n\\n, using ${levelStyle}.`,
    "Tone & Quality Requirements:",
    "- The opening sentence MUST be a compelling hook (a curious question, striking scientific phenomenon, or immersive story). Never start with dry textbook definitions.",
    "- Develop each paragraph fully with concrete examples, vivid facts, and smooth transitions so the article naturally reaches the full target word count.",
    "- Avoid dry academic jargon unless explained in context.",
    "Return ONLY one valid JSON object (no markdown fences) with these EXACT keys:",
    "{",
    '  "title": "Engaging English title (4-9 words)",',
    '  "description": "Rich, engaging English summary for the article card (STRICTLY 2 complete sentences, 32 to 48 words — never a single short phrase)",',
    '  "category": "Single category word (e.g. Science, Psychology, Culture, Technology, History, Nature, Art, Health, Daily Life)",',
    `  "content": "Full English article text of ${minWords}-${maxWords} words with ${targetParas} full paragraphs separated by \\n\\n",`,
    '  "word_meanings": { "lowercase_word": "exact contextual Turkish meaning in this article (for verbs use -mak/-mek)" },',
    `  "paragraph_translations": [${Array.from({ length: targetParas }, (_, i) => `"Natural fluent Turkish translation of paragraph ${i + 1}."`).join(", ")}],`,
    '  "sentence_translations": { "Exact English sentence from content": "Natural, fluent Turkish translation" },',
    '  "word_relations": { "lowercase_word": { "syn": ["1-3 exact contextual English synonyms"], "ant": ["1-2 exact contextual English antonyms"] } }',
    "}",
    "Rules:",
    `1. CRITICAL WORD COUNT: "content" MUST have ${targetParas} full paragraphs (${sentencesPerPara} sentences each) totaling AT LEAST ${minWords} words (target ${effectiveWords} words). Never write short 2-sentence paragraphs!`,
    '2. CRITICAL: "description" MUST be 2 full, compelling sentences (32-48 words).',
    `3. CRITICAL: "paragraph_translations" MUST be an array of EXACTLY ${targetParas} fluent Turkish paragraph translations matching each paragraph of "content" in order.`,
    "4. Include 30 to 45 key content words from the article in word_meanings (lowercase base/appeared forms) with their EXACT contextual Turkish meaning in this article.",
    "5. Include EVERY sentence from content in sentence_translations with exact punctuation.",
    "6. Include 15 to 25 key content words in word_relations with ONLY synonyms and antonyms that match the EXACT sense used in this article's sentences.",
  ].join("\n");
}

function resolveTopicImageUrl(title, category, content) {
  const text = `${title || ""} ${category || ""} ${content ? content.slice(0, 300) : ""}`.toLowerCase();
  
  if (text.includes("cycl") || text.includes("bike") || text.includes("bicycle")) {
    return "https://images.unsplash.com/photo-1485965120184-e220f721d03e?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("marathon") || text.includes("sahara") || text.includes("desert") || text.includes("running") || text.includes("runner")) {
    return "https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("otter") || text.includes("kelp") || text.includes("coral") || text.includes("reef") || text.includes("marine")) {
    return "https://images.unsplash.com/photo-1546026423-cc4642628d2b?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("seal") || text.includes("arctic") || text.includes("antarctic") || text.includes("polar") || text.includes("glacier") || text.includes("shackleton")) {
    return "https://images.unsplash.com/photo-1517411032315-54ef2cb783bb?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("sculpture") || text.includes("bottle") || text.includes("trash") || text.includes("craft") || text.includes("recycle")) {
    return "https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("floating cit") || text.includes("architecture") || text.includes("urban") || text.includes("skyscraper") || text.includes("building")) {
    return "https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("sunlight") || text.includes("morning sun") || text.includes("circadian") || text.includes("sunrise")) {
    return "https://images.unsplash.com/photo-1470240731273-7821a6eeb6bd?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("paint") || text.includes("art") || text.includes("color") || text.includes("canvas")) {
    return "https://images.unsplash.com/photo-1579783902614-a3fb3927b675?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("psychol") || text.includes("mind") || text.includes("neuro") || text.includes("deja vu") || text.includes("unfinished") || text.includes("zeigarnik") || text.includes("brain")) {
    return "https://images.unsplash.com/photo-1507413245164-6160d8298b31?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("aluminum") || text.includes("metal") || text.includes("industrial") || text.includes("factory") || text.includes("manufacturing")) {
    return "https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("love") || text.includes("negative feeling") || text.includes("relationship") || text.includes("emotion") || text.includes("friendship")) {
    return "https://images.unsplash.com/photo-1518199266791-5375a83190b7?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("space") || text.includes("galaxy") || text.includes("telescope") || text.includes("star") || text.includes("planet") || text.includes("cosmos") || text.includes("universe")) {
    return "https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("black hole") || text.includes("physics") || text.includes("neutron") || text.includes("relativity") || text.includes("einstein")) {
    return "https://images.unsplash.com/photo-1462331940025-496dfbfc7564?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("ocean") || text.includes("sea") || text.includes("deep-sea") || text.includes("octopus") || text.includes("abyss") || text.includes("mariana")) {
    return "https://images.unsplash.com/photo-1518837695005-2083093ee35b?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("forest") || text.includes("tree") || text.includes("fungal") || text.includes("wood wide") || text.includes("nature") || text.includes("plant")) {
    return "https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("butterfly") || text.includes("bird") || text.includes("migration") || text.includes("wildlife") || text.includes("animal")) {
    return "https://images.unsplash.com/photo-1535083783855-76ae62b2914e?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("ai") || text.includes("artificial intelligence") || text.includes("robot") || text.includes("interface") || text.includes("computer") || text.includes("tech")) {
    return "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("roman") || text.includes("alexandria") || text.includes("ancient") || text.includes("history") || text.includes("manuscript")) {
    return "https://images.unsplash.com/photo-1552832230-c0197dd311b5?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("book") || text.includes("reading") || text.includes("library") || text.includes("literature") || text.includes("language")) {
    return "https://images.unsplash.com/photo-1457369804613-52c61a468e7d?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("music") || text.includes("song") || text.includes("melody")) {
    return "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=720&q=75";
  }
  if (text.includes("sleep") || text.includes("dream") || text.includes("rest")) {
    return "https://images.unsplash.com/photo-1541781774459-bb2af2f05b55?auto=format&fit=crop&w=720&q=75";
  }
  return "https://images.unsplash.com/photo-1499750310107-5fef28a66643?auto=format&fit=crop&w=720&q=75";
}

function finalizeGeneratedArticle(parsed, level, providerName) {
  const title = String(parsed?.title || "").trim();
  const content = String(parsed?.content || "").trim();
  if (!title || content.length < 40) return null;

  const description =
    String(parsed.description || "").trim() || buildFallbackDescription(content);
  const category =
    String(parsed.category || "").trim() || inferArticleCategory(title, content);
  const imageUrl =
    String(parsed.image_url || parsed.imageUrl || "").trim() ||
    resolveTopicImageUrl(title, category, content);
  const wordCount = content.split(/\s+/).filter(Boolean).length;
  const readingMin = Math.max(1, Math.round(wordCount / 145));
  const readingTime = readingMin <= 1 ? "1 - 2 dk" : `${readingMin} - ${readingMin + 1} dk`;
  return {
    id: `${level.toLowerCase()}-${slugifyArticleId(title)}`,
    level,
    title,
    description,
    category,
    image_url: imageUrl,
    author: "Line Reader",
    reading_time: readingTime,
    reading_time_minutes: readingMin,
    language: "en",
    published_at: new Date().toISOString(),
    content,
    word_meanings: parsed.word_meanings && typeof parsed.word_meanings === "object" ? parsed.word_meanings : {},
    paragraph_translations: Array.isArray(parsed.paragraph_translations) ? parsed.paragraph_translations.map((p) => String(p || "").trim()).filter(Boolean) : [],
    sentence_translations: parsed.sentence_translations && typeof parsed.sentence_translations === "object" ? parsed.sentence_translations : {},
    word_relations: parsed.word_relations && typeof parsed.word_relations === "object" ? parsed.word_relations : {},
    is_hidden: false,
    publish_at: null,
    _provider: providerName,
  };
}

async function generateArticleWithWorkersAi(ai, level, topic, targetWordCount = null) {
  const prompt = buildArticleGenerationPrompt(level, topic, targetWordCount);
  const parsedTarget = Number(targetWordCount);
  const effectiveWords =
    Number.isFinite(parsedTarget) && parsedTarget >= 100 && parsedTarget <= 1500
      ? Math.round(parsedTarget)
      : 350;
  const dynamicMaxTokens = Math.min(8192, Math.max(5200, effectiveWords * 14));
  const cfModels = [
    "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
    "@cf/meta/llama-3.1-8b-instruct",
  ];
  let lastErr = "Cloudflare Workers AI yanıt vermedi.";
  for (const model of cfModels) {
    try {
      const rawOut = await ai.run(model, {
        messages: [
          {
            role: "system",
            content: `You are an expert English-Turkish curriculum author. You MUST write the article content at the exact requested word count (~${effectiveWords} words) and a rich 2-sentence description (32-48 words). Output ONLY valid JSON with no markdown or commentary.`,
          },
          { role: "user", content: prompt },
        ],
        temperature: 0.55,
        max_tokens: dynamicMaxTokens,
      });
      const text = extractModelText(rawOut);
      const cleaned = String(text).replace(/```json\s*/gi, "").replace(/```/g, "").trim();
      const start = cleaned.indexOf("{");
      const end = cleaned.lastIndexOf("}");
      if (start === -1 || end <= start) {
        lastErr = `Geçersiz JSON (${model})`;
        continue;
      }
      const parsed = JSON.parse(cleaned.slice(start, end + 1));
      const finalized = finalizeGeneratedArticle(parsed, level, model);
      if (finalized) return finalized;
      lastErr = `Eksik başlık/metin (${model})`;
    } catch (e) {
      lastErr = `${model}: ${String(e?.message || e)}`;
    }
  }
  throw new Error(lastErr);
}

async function generateArticleWithGemini(apiKey, level, topic) {
  const prompt = buildArticleGenerationPrompt(level, topic);

  // En hızlı ve kararlı Flash modelleri (gereksiz /models listeleme çağrısı yapılmaz)
  const models = [
    "gemini-2.5-flash",
    "gemini-flash-latest",
    "gemini-2.0-flash",
  ];
  let lastError = "Gemini yanıt vermedi.";

  for (const model of models) {
    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`;
    const genConfig = {
      temperature: 0.65,
      responseMimeType: "application/json",
    };
    if (model.includes("2.5")) {
      genConfig.thinkingConfig = { thinkingBudget: 0 };
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 18000);
    let res;
    try {
      res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: controller.signal,
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: genConfig,
        }),
      });
    } catch (err) {
      lastError = `${model} zaman aşımı/ağ hatası: ${String(err?.message || err)}`;
      continue;
    } finally {
      clearTimeout(timer);
    }

    if (!res.ok) {
      const errText = await res.text().catch(() => "");
      lastError = `HTTP ${res.status} (${model}): ${errText.slice(0, 160)}`;
      continue;
    }
    const data = await res.json();
    const rawText = data?.candidates?.[0]?.content?.parts?.[0]?.text || "";
    const cleaned = String(rawText).replace(/```json\s*/gi, "").replace(/```/g, "").trim();
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start === -1 || end <= start) {
      lastError = "Geçerli JSON üretilemedi.";
      continue;
    }
    const parsed = JSON.parse(cleaned.slice(start, end + 1));
    const finalized = finalizeGeneratedArticle(parsed, level, model);
    if (!finalized) {
      lastError = "Başlık veya metin eksik geldi.";
      continue;
    }
    return finalized;
  }

  throw new Error(lastError);
}

function buildFallbackDescription(content) {
  const firstPara = String(content || "").split(/\n\s*\n/)[0] || "";
  const sentences = firstPara.split(/(?<=[.!?])\s+/).map((s) => s.trim()).filter(Boolean);
  if (sentences.length === 0) return firstPara.slice(0, 160).trim();
  let desc = sentences[0];
  if (desc.length < 85 && sentences.length > 1) {
    desc = `${desc} ${sentences[1]}`;
  }
  return desc.length > 200 ? `${desc.slice(0, 197).trim()}...` : desc;
}

function inferArticleCategory(title, content) {
  const text = `${title} ${content}`.toLowerCase();
  if (/\b(brain|psycholog|memory|mind|emotion|habit|stress|sleep)\b/.test(text)) return "Psychology";
  if (/\b(science|space|planet|physics|biology|research|scientist|experiment)\b/.test(text)) return "Science";
  if (/\b(technology|computer|robot|ai|digital|internet|software|phone)\b/.test(text)) return "Technology";
  if (/\b(art|paint|music|sculpture|museum|artist|design|film)\b/.test(text)) return "Art";
  if (/\b(history|ancient|century|empire|war|historical)\b/.test(text)) return "History";
  if (/\b(nature|ocean|forest|animal|climate|environment|earth|plant)\b/.test(text)) return "Nature";
  if (/\b(health|food|diet|exercise|medicine|body|sunlight)\b/.test(text)) return "Health";
  return "Culture";
}

async function generatePodcastAudioWithGemini(env, articleId, title, content, voiceName) {
  const apiKey = String(env.GEMINI_API_KEY).trim();
  const githubToken = String(env.GITHUB_TOKEN).trim();
  const ttsText = title ? `${title}.\n\n${content}` : content;

  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=${encodeURIComponent(apiKey)}`;
  const res = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [
            {
              text: `Read the following English article aloud in a clear, warm, natural podcast narrator voice with comfortable pacing:\n\n${ttsText}`,
            },
          ],
        },
      ],
      generationConfig: {
        responseModalities: ["AUDIO"],
        speechConfig: {
          voiceConfig: {
            prebuiltVoiceConfig: {
              voiceName: voiceName || "Kore",
            },
          },
        },
      },
    }),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    throw new Error(`Gemini TTS HTTP ${res.status}: ${errText.slice(0, 180)}`);
  }

  const data = await res.json();
  const parts = data?.candidates?.[0]?.content?.parts || [];
  let inlineAudio = null;
  for (const p of parts) {
    if (p?.inlineData?.data) {
      inlineAudio = p.inlineData;
      break;
    }
  }
  if (!inlineAudio) {
    throw new Error("Gemini TTS ses verisi döndürmedi.");
  }

  const mime = String(inlineAudio.mimeType || "audio/L16;rate=24000").toLowerCase();
  const rawBytes = base64ToBytes(inlineAudio.data);
  let wavBytes = rawBytes;
  let durationSec = 0;

  if (mime.includes("wav")) {
    durationSec = Math.max(1, Math.round((rawBytes.length - 44) / (24000 * 2)));
  } else {
    const rateMatch = mime.match(/rate=(\d+)/);
    const sampleRate = rateMatch ? parseInt(rateMatch[1], 10) : 24000;
    wavBytes = pcmToWavBytes(rawBytes, sampleRate);
    durationSec = Math.max(1, Math.round(rawBytes.length / (sampleRate * 2)));
  }

  const repoPath = `audio/${articleId}.wav`;
  await upsertGitHubFile(
    githubToken,
    repoPath,
    bytesToBase64(wavBytes),
    `Add podcast audio for ${articleId}`
  );

  // Cloudflare Workers AI Whisper ile gerçek cümle zaman damgalarını (audio_segments) çıkar.
  const audioSegments = await alignAudioSegmentsWithWhisper(env, wavBytes, content, durationSec * 1000);

  return {
    audio_url: `https://raw.githubusercontent.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/main/${repoPath}`,
    audio_voice: voiceName || "Kore",
    audio_duration_sec: durationSec,
    ...(audioSegments.length > 0 ? { audio_segments: audioSegments } : {}),
  };
}

/**
 * Cloudflare Workers AI Whisper (`@cf/openai/whisper`) ile ses dosyasından
 * her cümlenin gerçek milisaniye başlangıç/bitişini hizalar.
 */
async function alignAudioSegmentsWithWhisper(env, wavBytes, content, totalDurationMs) {
  if (!env || !env.AI || !content) return [];
  try {
    const paragraphs = String(content)
      .split(/\n\s*\n/)
      .map((p) => p.trim())
      .filter(Boolean);
    const sentences = [];
    paragraphs.forEach((pText, pIdx) => {
      const parts = pText
        .split(/(?<=[.!?])\s+/)
        .map((s) => s.trim())
        .filter(Boolean);
      parts.forEach((text, sIdx) => {
        sentences.push({ p: pIdx, s: sIdx, text });
      });
    });
    if (sentences.length === 0) return [];

    // Whisper girişi: 8-bit dizi olarak WAV baytları (küçük/orta makaleler için doğrudan çalışır).
    const whisperRes = await env.AI.run("@cf/openai/whisper", {
      audio: [...wavBytes],
    });

    const words = Array.isArray(whisperRes?.words) ? whisperRes.words : [];
    const vttSegments = Array.isArray(whisperRes?.segments) ? whisperRes.segments : [];
    if (words.length === 0 && vttSegments.length === 0) return [];

    const norm = (str) => String(str || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    const aligned = [];

    if (words.length > 0) {
      let cursor = 0;
      for (const sent of sentences) {
        const tokens = sent.text.split(/\s+/).map(norm).filter(Boolean);
        if (tokens.length === 0) continue;
        const firstTok = tokens[0];
        let startIdx = cursor;
        const searchEnd = Math.min(words.length, cursor + 14);
        for (let k = cursor; k < searchEnd; k++) {
          if (norm(words[k]?.word) === firstTok) {
            startIdx = k;
            break;
          }
        }
        const endIdx = Math.min(words.length - 1, startIdx + Math.max(1, tokens.length - 1));
        const startMs = Math.max(0, Math.round((Number(words[startIdx]?.start) || 0) * 1000));
        const endMs = Math.max(
          startMs + 250,
          Math.round((Number(words[endIdx]?.end) || Number(words[startIdx]?.end) || 0) * 1000)
        );
        aligned.push({ p: sent.p, s: sent.s, start_ms: startMs, end_ms: endMs });
        cursor = Math.min(words.length - 1, endIdx + 1);
      }
      return aligned;
    }

    // Kelime zamanı yoksa segment zamanlarından orantılı dağıt.
    if (vttSegments.length > 0) {
      const segStartMs = Math.round((Number(vttSegments[0]?.start) || 0) * 1000);
      const segEndMs = Math.max(
        totalDurationMs,
        Math.round((Number(vttSegments[vttSegments.length - 1]?.end) || 0) * 1000)
      );
      const span = Math.max(1000, segEndMs - segStartMs);
      const totalChars = sentences.reduce((acc, s) => acc + s.text.length + 6, 0);
      let acc = 0;
      for (const sent of sentences) {
        const w = sent.text.length + 6;
        const startMs = segStartMs + Math.round((acc / totalChars) * span);
        acc += w;
        const endMs = segStartMs + Math.round((acc / totalChars) * span);
        aligned.push({ p: sent.p, s: sent.s, start_ms: startMs, end_ms: endMs });
      }
      return aligned;
    }
    return [];
  } catch (_) {
    return [];
  }
}

async function upsertGitHubFile(githubToken, repoPath, contentBase64, commitMessage) {
  const apiUrl = `https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/contents/${repoPath}`;
  const headers = {
    Authorization: `Bearer ${githubToken}`,
    Accept: "application/vnd.github+json",
    "Content-Type": "application/json",
    "User-Agent": "LineReader-Worker",
  };

  let existingSha = null;
  const getRes = await fetch(apiUrl, { method: "GET", headers });
  if (getRes.ok) {
    const meta = await getRes.json();
    existingSha = meta?.sha || null;
  }

  const putBody = {
    message: commitMessage,
    content: contentBase64,
    branch: "main",
    ...(existingSha ? { sha: existingSha } : {}),
  };

  const putRes = await fetch(apiUrl, {
    method: "PUT",
    headers,
    body: JSON.stringify(putBody),
  });
  if (!putRes.ok) {
    const errText = await putRes.text().catch(() => "");
    throw new Error(`GitHub yükleme hatası (HTTP ${putRes.status}): ${errText.slice(0, 160)}`);
  }
}

/**
 * İki Aşamalı Otomatik Yayınlama Sistemi:
 * 1. Hazırlık (Pre-bake): Hedef saatten (örn: 09:00) 1 saat önce (08:00-08:59)
 *    A1'den C2'ye kadar 6 seviyenin tamamı için makale + analiz + podcast sesini hazırlar,
 *    sisteme `is_hidden = true` olarak gizlice yükler.
 * 2. Yayınlama (Publish): Hedef saat (09:00) geldiğinde tüm hazır makaleleri
 *    tek saniyede `is_hidden = false` yaparak anında canlıya alır (0 gecikme).
 */
async function handleScheduledPublishRun(env, triggerSource = "cron", forceMode = null) {
  if (!env || !env.DB) return { ok: false, error: "no_db" };
  await ensureSchema(env.DB);

  let cfg = await env.DB
    .prepare("SELECT * FROM publish_schedule_config WHERE id = 1 LIMIT 1")
    .first();
  if (!cfg) {
    cfg = {
      is_enabled: 1,
      publish_hour: 9,
      timezone_offset: 3,
      last_prepared_date: null,
      last_published_date: null,
    };
  }

  const isEnabled = Boolean(cfg.is_enabled);
  if (!isEnabled && forceMode !== "full_pipeline" && forceMode !== "prebake" && forceMode !== "publish") {
    return { ok: true, skipped: true, reason: "schedule_disabled" };
  }

  const tzOffset = Number(cfg.timezone_offset ?? 3);
  const now = new Date();
  const localNow = new Date(now.getTime() + tzOffset * 3600 * 1000);
  const currentHour = localNow.getUTCHours();
  const todayStr = localNow.toISOString().slice(0, 10);
  const publishHour = Number(cfg.publish_hour ?? 9);
  const prebakeHour = (publishHour - 1 + 24) % 24;

  const results = { prebaked: 0, published: 0, ai_generation_disabled: true, errors: [] };

  // 1) ÖN HAZIRLIK AŞAMASI (AI'ya sıfırdan makale yazdırma kapatıldı)
  // Yalnızca önceden manuel olarak eklenip zamanlanmış (is_hidden=true, publish_at<=today) makaleler yayına açılır.

  // 2) YAYINLAMA AŞAMASI (Publish)
  const shouldPublish =
    forceMode === "publish" ||
    forceMode === "full_pipeline" ||
    (currentHour === publishHour && cfg.last_published_date !== todayStr);

  if (shouldPublish) {
    const list = await loadArticlesList(env);
    let unhiddenCount = 0;
    for (const a of list) {
      if (a.is_hidden) {
        // Eğer hedef tarih bugün veya geçmişse yayına aç
        const pDate = a.publish_at ? String(a.publish_at).slice(0, 10) : todayStr;
        if (pDate <= todayStr) {
          a.is_hidden = false;
          unhiddenCount++;
        }
      }
    }

    if (unhiddenCount > 0) {
      await saveArticlesList(env, list, `Publish scheduled articles for ${todayStr} (${unhiddenCount} articles live)`);
      results.published = unhiddenCount;
    }

    await env.DB
      .prepare("UPDATE publish_schedule_config SET last_published_date = ?, updated_at = ? WHERE id = 1")
      .bind(todayStr, new Date().toISOString())
      .run();
  }

  return {
    ok: true,
    results,
    current_hour: currentHour,
    publish_hour: publishHour,
    prebake_hour: prebakeHour,
    today: todayStr,
    trigger_source: triggerSource,
  };
}

function pcmToWavBytes(pcmBytes, sampleRate = 24000) {
  const header = new Uint8Array(44);
  const view = new DataView(header.buffer);
  const dataLen = pcmBytes.length;
  const writeStr = (offset, str) => {
    for (let i = 0; i < str.length; i++) {
      header[offset + i] = str.charCodeAt(i);
    }
  };
  writeStr(0, "RIFF");
  view.setUint32(4, 36 + dataLen, true);
  writeStr(8, "WAVE");
  writeStr(12, "fmt ");
  view.setUint32(16, 16, true); // PCM chunk size
  view.setUint16(20, 1, true); // PCM format
  view.setUint16(22, 1, true); // Mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // Byte rate
  view.setUint16(32, 2, true); // Block align
  view.setUint16(34, 16, true); // Bits per sample
  writeStr(36, "data");
  view.setUint32(40, dataLen, true);

  const out = new Uint8Array(44 + dataLen);
  out.set(header, 0);
  out.set(pcmBytes, 44);
  return out;
}

function base64ToBytes(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) {
    bytes[i] = bin.charCodeAt(i);
  }
  return bytes;
}

function bytesToBase64(bytes) {
  const chunkSize = 0x8000;
  let binary = "";
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const slice = bytes.subarray(i, Math.min(i + chunkSize, bytes.length));
    binary += String.fromCharCode(...slice);
  }
  return btoa(binary);
}

/* ---------------- Admin Uç Noktaları (PC Makale Paneli) ---------------- */

async function handleAdminRequest(request, env, path, method) {
  if (!env || !env.ADMIN_SECRET) {
    return jsonResponse(
      { ok: false, error: "admin_secret_missing", message: "Cloudflare Worker içinde ADMIN_SECRET tanımlanmamış." },
      503
    );
  }

  const supplied = (request.headers.get("X-Admin-Secret") || "").trim();
  if (!supplied || supplied !== String(env.ADMIN_SECRET).trim()) {
    return jsonResponse(
      { ok: false, error: "forbidden", message: "Yönetici şifresi hatalı." },
      403
    );
  }

  if (!env.DB) {
    return jsonResponse(
      { ok: false, error: "db_missing", message: "Cloudflare Worker içinde D1 veri tabanı (DB) bağlanmamış." },
      503
    );
  }

  await ensureSchema(env.DB);

  // PC Makale Stüdyosu yedek makale üretimi (Google Gemini 503 verdiğinde Cloudflare Llama 3.3 70B)
  if (path === "/admin/generate-article" && method === "POST") {
    const body = await safeReadJson(request);
    const rawLevel = String(body?.level || "B1").trim().toUpperCase();
    const level = ["A1", "A2", "B1", "B2", "C1", "C2"].includes(rawLevel) ? rawLevel : "B1";
    const topic = String(body?.topic || "").trim().slice(0, 160);
    const wordCount = body?.wordCount ? Number(body.wordCount) : null;
    if (!env.AI) {
      return jsonResponse({ ok: false, message: "Workers AI bağlı değil." }, 503);
    }
    try {
      const article = await generateArticleWithWorkersAi(env.AI, level, topic, wordCount);
      return jsonResponse({ ok: true, article, model: article._provider || "cloudflare-llama-3.3" });
    } catch (err) {
      return jsonResponse({ ok: false, message: String(err?.message || err) }, 502);
    }
  }

  // PC Makale Stüdyosu kapak fotoğrafı üretimi (Cloudflare Workers AI FLUX.1 Schnell)
  if (path === "/admin/generate-image" && method === "POST") {
    const body = await safeReadJson(request);
    const title = String(body?.title || "").trim().slice(0, 140);
    const description = String(body?.description || "").trim().slice(0, 260);
    const category = String(body?.category || "General").trim().slice(0, 40);
    if (!title) {
      return jsonResponse({ ok: false, message: "Makale başlığı gerekli." }, 400);
    }
    if (!env.AI) {
      return jsonResponse({ ok: false, message: "Workers AI bağlı değil." }, 503);
    }
    try {
      const prompt = `High-resolution editorial magazine cover photograph representing the article "${title}" (${category}). ${description ? `Scene concept: ${description}. ` : ""}Cinematic natural lighting, rich depth of field, National Geographic / The Atlantic editorial photography style, 16:9 widescreen composition. Strictly NO text, NO words, NO letters, NO watermarks, NO logos.`;
      const aiRes = await env.AI.run("@cf/black-forest-labs/flux-1-schnell", {
        prompt,
        steps: 4,
      });
      const b64 = aiRes && typeof aiRes.image === "string" ? aiRes.image : "";
      if (!b64) {
        throw new Error("FLUX boş görsel döndürdü.");
      }
      return jsonResponse({
        ok: true,
        image_base64: b64,
        mime_type: "image/jpeg",
        provider: "cloudflare-flux-1-schnell",
      });
    } catch (err) {
      return jsonResponse({ ok: false, message: String(err?.message || err) }, 502);
    }
  }

  // PC Makale Stüdyosu Podcast AI ses hizalama (Cloudflare Workers AI Whisper)
  if (path === "/admin/align-audio" && method === "POST") {
    const body = await safeReadJson(request);
    const audioB64 = String(body?.audio_base64 || "").trim();
    const content = String(body?.content || "").trim();
    const durationMs = Number(body?.duration_ms || 0);
    if (!audioB64 || !content) {
      return jsonResponse({ ok: false, message: "audio_base64 ve content gerekli." }, 400);
    }
    try {
      const wavBytes = base64ToBytes(audioB64);
      const segments = await alignAudioSegmentsWithWhisper(env, wavBytes, content, durationMs);
      return jsonResponse({ ok: true, audio_segments: segments, count: segments.length });
    } catch (err) {
      return jsonResponse({ ok: false, message: String(err?.message || err) }, 502);
    }
  }

  // Anlık makale akışı güncelleme (PC Makale Paneli -> 1 saniyede canlı yayın)
  if (path === "/admin/articles" && method === "POST") {
    const body = await safeReadJson(request);
    if (!body || !Array.isArray(body.articles)) {
      return jsonResponse(
        { ok: false, error: "invalid_articles", message: "Geçerli bir 'articles' dizisi gönderilmedi." },
        400
      );
    }
    const nowIso = new Date().toISOString();
    const payloadText = JSON.stringify({
      version: body.version ?? 1,
      updated_at: body.updated_at || nowIso,
      articles: body.articles,
    });
    const etag = `"d1-${Date.now()}-${payloadText.length}"`;
    await env.DB
      .prepare(`
        INSERT INTO articles_feed (id, payload_json, etag, updated_at)
        VALUES (1, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          payload_json = excluded.payload_json,
          etag = excluded.etag,
          updated_at = excluded.updated_at
      `)
      .bind(payloadText, etag, nowIso)
      .run();

    return jsonResponse({
      ok: true,
      count: body.articles.length,
      etag,
      message: `${body.articles.length} makale Cloudflare D1'e anında yayınlandı.`,
    });
  }

  // Otomatik Günlük Yayın Planlayıcı (PC Paneli -> Cloudflare D1)
  if (path === "/admin/schedule") {
    if (method === "GET") {
      let cfg = await env.DB
        .prepare("SELECT is_enabled, publish_hour, timezone_offset, last_prepared_date, last_published_date, updated_at FROM publish_schedule_config WHERE id = 1 LIMIT 1")
        .first();
      if (!cfg) {
        cfg = {
          is_enabled: 1,
          publish_hour: 9,
          timezone_offset: 3,
          last_prepared_date: null,
          last_published_date: null,
          updated_at: new Date().toISOString(),
        };
      }
      const tzOffset = Number(cfg.timezone_offset ?? 3);
      const localNow = new Date(Date.now() + tzOffset * 3600 * 1000);
      const serverTimeTr = `${String(localNow.getUTCHours()).padStart(2, "0")}:${String(localNow.getUTCMinutes()).padStart(2, "0")}`;
      const pubHour = Number(cfg.publish_hour ?? 9);
      const preHour = (pubHour - 1 + 24) % 24;

      return jsonResponse({
        ok: true,
        config: {
          is_enabled: Boolean(cfg.is_enabled),
          publish_hour: pubHour,
          timezone_offset: tzOffset,
          last_prepared_date: cfg.last_prepared_date || null,
          last_published_date: cfg.last_published_date || null,
          updated_at: cfg.updated_at || null,
        },
        server_time_tr: serverTimeTr,
        schedule_summary: `Her gün saat ${String(pubHour).padStart(2, "0")}:00'da yayınlanır (${String(preHour).padStart(2, "0")}:15'te A1-C2 tüm 6 seviye önceden hazırlanıp gizlenir).`,
      });
    }

    if (method === "POST") {
      const body = await safeReadJson(request);
      const isEnabled = body?.is_enabled !== false ? 1 : 0;
      let pubHour = parseInt(body?.publish_hour ?? 9, 10);
      if (isNaN(pubHour) || pubHour < 0 || pubHour > 23) pubHour = 9;
      let tzOffset = parseInt(body?.timezone_offset ?? 3, 10);
      if (isNaN(tzOffset) || tzOffset < -12 || tzOffset > 14) tzOffset = 3;

      await env.DB
        .prepare(`
          INSERT INTO publish_schedule_config (id, is_enabled, publish_hour, timezone_offset, updated_at)
          VALUES (1, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            is_enabled = excluded.is_enabled,
            publish_hour = excluded.publish_hour,
            timezone_offset = excluded.timezone_offset,
            updated_at = excluded.updated_at
        `)
        .bind(isEnabled, pubHour, tzOffset, new Date().toISOString())
        .run();

      const preHour = (pubHour - 1 + 24) % 24;
      return jsonResponse({
        ok: true,
        message: isEnabled
          ? `Otomatik yayın saati ${String(pubHour).padStart(2, "0")}:00 olarak ayarlandı (Hazırlık: ${String(preHour).padStart(2, "0")}:15).`
          : "Otomatik günlük yayınlama devre dışı bırakıldı.",
      });
    }
  }

  // Planlayıcıyı Manuel Tetikleme (PC Paneli)
  if (path === "/admin/schedule/run-now" && method === "POST") {
    const body = await safeReadJson(request);
    const mode = String(body?.mode || "full_pipeline").trim();
    const result = await handleScheduledPublishRun(env, "admin_manual", mode);
    return jsonResponse({
      ok: true,
      result,
      message: `Planlayıcı test çalışması tamamlandı (Mod: ${mode}).`,
    });
  }

  // Yapay zekaya sıfırdan makale yazdırma kapatıldı (PC Paneli)
  if (path === "/admin/quick-publish" && method === "POST") {
    return jsonResponse(
      {
        ok: false,
        error: "ai_generation_disabled",
        message: "Yapay zekaya sıfırdan makale yazdırma sistemi kapatıldı. Lütfen Manuel Makale Ekle arayüzünü kullanın.",
      },
      410
    );
  }

  // Kod yönetimi
  if (path === "/admin/codes") {
    if (method === "GET") {
      const res = await env.DB
        .prepare("SELECT code, max_uses, used_count, is_active, note, created_at FROM access_codes ORDER BY created_at DESC")
        .all();
      return jsonResponse({ ok: true, codes: res.results || [] });
    }

    const body = await safeReadJson(request);
    if (method === "POST") {
      const code = String(body?.code || "").trim().toUpperCase().replace(/[^A-Z0-9_-]/g, "");
      const maxUses = Math.max(1, Math.min(100000, parseInt(body?.max_uses ?? 1, 10) || 1));
      const note = String(body?.note || "").trim().slice(0, 140);

      if (code.length < 3 || code.length > 48) {
        return jsonResponse(
          { ok: false, error: "invalid_code", message: "Kod en az 3 karakter olmalı (harf, rakam, - veya _)." },
          400
        );
      }

      const exists = await env.DB
        .prepare("SELECT code FROM access_codes WHERE code = ? LIMIT 1")
        .bind(code)
        .first();
      if (exists) {
        return jsonResponse(
          { ok: false, error: "duplicate_code", message: `"${code}" kodu zaten mevcut.` },
          409
        );
      }

      await env.DB
        .prepare("INSERT INTO access_codes (code, max_uses, used_count, is_active, note, created_at) VALUES (?, ?, 0, 1, ?, ?)")
        .bind(code, maxUses, note, new Date().toISOString())
        .run();

      return jsonResponse({ ok: true, code, max_uses: maxUses, message: `"${code}" kodu oluşturuldu (${maxUses} kullanım).` });
    }

    if (method === "PATCH") {
      const code = String(body?.code || "").trim().toUpperCase();
      if (!code) return jsonResponse({ ok: false, message: "Kod belirtilmedi." }, 400);

      if (typeof body?.is_active === "boolean" || typeof body?.is_active === "number") {
        await env.DB
          .prepare("UPDATE access_codes SET is_active = ? WHERE code = ?")
          .bind(body.is_active ? 1 : 0, code)
          .run();
      }
      if (body?.max_uses !== undefined) {
        const maxUses = Math.max(1, Math.min(100000, parseInt(body.max_uses, 10) || 1));
        await env.DB
          .prepare("UPDATE access_codes SET max_uses = ? WHERE code = ?")
          .bind(maxUses, code)
          .run();
      }
      return jsonResponse({ ok: true, message: `"${code}" güncellendi.` });
    }

    if (method === "DELETE") {
      const code = String(body?.code || "").trim().toUpperCase();
      if (!code) return jsonResponse({ ok: false, message: "Kod belirtilmedi." }, 400);
      await env.DB.prepare("DELETE FROM access_codes WHERE code = ?").bind(code).run();
      return jsonResponse({ ok: true, message: `"${code}" silindi.` });
    }
  }

  // Kullanıcı yetki yönetimi (tüm Firebase kayıtlı kullanıcılar + yetkiler)
  if (path === "/admin/users") {
    if (method === "GET") {
      const users = await listAllUsersWithEntitlements(env.DB);
      return jsonResponse({ ok: true, users });
    }

    const body = await safeReadJson(request);

    // Geçmiş & canlı Firebase Auth senkronizasyonu (prune_missing: true ise Firebase'de silinenleri D1'den temizler)
    if (method === "POST" && body?.action === "import_users" && Array.isArray(body?.users)) {
      const activeEmails = new Set();
      let imported = 0;
      for (const item of body.users) {
        const em = String(item?.email || "").trim().toLowerCase();
        if (!em || !em.includes("@")) continue;
        activeEmails.add(em);
        await upsertRegisteredUser(env.DB, {
          email: em,
          uid: item?.uid || item?.localId || "",
          displayName: item?.displayName || item?.display_name || "",
          authProvider: item?.authProvider || item?.auth_provider || item?.provider || "",
        });
        imported += 1;
      }

      let pruned = 0;
      if (body?.prune_missing === true) {
        const existingReg = await env.DB
          .prepare("SELECT email FROM registered_users")
          .all();
        for (const row of (existingReg.results || [])) {
          const em = String(row.email || "").trim().toLowerCase();
          if (em && !activeEmails.has(em)) {
            await env.DB
              .prepare("DELETE FROM registered_users WHERE LOWER(email) = ?")
              .bind(em)
              .run();
            await env.DB
              .prepare("DELETE FROM user_entitlements WHERE LOWER(email) = ? AND LOWER(source) != 'admin'")
              .bind(em)
              .run();
            pruned += 1;
          }
        }
      }

      const prunedNote = pruned > 0 ? ` (${pruned} silinmiş hesap temizlendi)` : "";
      return jsonResponse({
        ok: true,
        imported,
        pruned,
        message: `${imported} Firebase kullanıcısı eşitlendi${prunedNote}.`,
      });
    }

    const email = String(body?.email || "").trim().toLowerCase();
    if (!email || !email.includes("@")) {
      return jsonResponse({ ok: false, message: "Geçerli bir e-posta adresi girin." }, 400);
    }

    if (method === "POST" || method === "PATCH") {
      // Bağımsız Özel Tema bayrağı güncelleme (Premium/Geliştirici rolünü bozmaz)
      if (body?.action === "set_special_themes" || typeof body?.has_special_themes === "boolean") {
        const enabled = body?.has_special_themes === true || body?.enabled === true;
        if (enabled) {
          await env.DB
            .prepare(`
              INSERT INTO user_entitlements (email, uid, is_unlimited, source, code_used, granted_at, has_special_themes)
              VALUES (?, NULL, 0, 'special_themes', NULL, ?, 1)
              ON CONFLICT(email) DO UPDATE SET
                has_special_themes = 1
            `)
            .bind(email, new Date().toISOString())
            .run();
        } else {
          await env.DB
            .prepare("UPDATE user_entitlements SET has_special_themes = 0 WHERE LOWER(email) = ?")
            .bind(email)
            .run();
          await env.DB
            .prepare("DELETE FROM user_entitlements WHERE LOWER(email) = ? AND is_unlimited = 0 AND has_special_themes = 0")
            .bind(email)
            .run();
        }
        return jsonResponse({
          ok: true,
          has_special_themes: enabled,
          message: enabled
            ? `${email} hesabına Özel Temalar yetkisi verildi.`
            : `${email} hesabının Özel Temalar yetkisi kaldırıldı.`,
        });
      }

      const requestedRole = String(body?.role || "").trim().toLowerCase();
      const isDeveloper = requestedRole === "admin" || requestedRole === "developer";
      const targetSource = isDeveloper ? "admin" : "manual";
      const roleLabel = isDeveloper ? "Geliştirici" : "Premium Üye";
      await env.DB
        .prepare(`
          INSERT INTO user_entitlements (email, uid, is_unlimited, source, code_used, granted_at, has_special_themes)
          VALUES (?, NULL, 1, ?, NULL, ?, 0)
          ON CONFLICT(email) DO UPDATE SET
            is_unlimited = 1,
            source = excluded.source,
            granted_at = excluded.granted_at
        `)
        .bind(email, targetSource, new Date().toISOString())
        .run();
      return jsonResponse({
        ok: true,
        role: isDeveloper ? "admin" : "premium",
        source: targetSource,
        message: `${email} hesabına ${roleLabel} yetkisi tanımlandı.`,
      });
    }

    if (method === "DELETE") {
      if (body?.delete_account === true) {
        await env.DB
          .prepare("DELETE FROM registered_users WHERE LOWER(email) = ?")
          .bind(email)
          .run();
        await env.DB
          .prepare("DELETE FROM user_entitlements WHERE LOWER(email) = ?")
          .bind(email)
          .run();
        return jsonResponse({
          ok: true,
          deleted: true,
          message: `${email} kullanıcısı sistemden tamamen kaldırıldı.`,
        });
      }

      const existing = await env.DB
        .prepare("SELECT has_special_themes FROM user_entitlements WHERE LOWER(email) = ? LIMIT 1")
        .bind(email)
        .first();
      if (existing && Number(existing.has_special_themes) === 1 && body?.revoke_all !== true) {
        await env.DB
          .prepare("UPDATE user_entitlements SET is_unlimited = 0, source = 'special_themes', code_used = NULL WHERE LOWER(email) = ?")
          .bind(email)
          .run();
      } else {
        await env.DB
          .prepare("DELETE FROM user_entitlements WHERE LOWER(email) = ?")
          .bind(email)
          .run();
      }
      return jsonResponse({ ok: true, message: `${email} hesabının yetkisi kaldırıldı.` });
    }
  }

  return jsonResponse({ ok: false, error: "not_found" }, 404);
}

async function safeReadJson(request) {
  try {
    return await request.json();
  } catch (_) {
    return {};
  }
}

/* ---------------- Workers AI Yardımcıları ---------------- */

async function translateWithWorkersAi(ai, word, contextSentence) {
  const systemPrompt = [
    "You are an expert English-to-Turkish contextual dictionary for Turkish language learners.",
    "Given an English word/phrase and the sentence where it appears, return ONLY valid JSON:",
    '{"meanings":[{"translation":"<short Turkish meaning>","partOfSpeech":"<noun|verb|adjective|adverb|phrase|idiom|preposition|conjunction|null>","isContextual":true}]}',
    "Rules:",
    "1. Return 1 to 4 distinct Turkish meanings.",
    "2. The FIRST meaning (isContextual: true) MUST be the exact meaning of the word in the given sentence context.",
    "3. Meanings 2 to 4 (isContextual: false) should be the most common other Turkish dictionary meanings.",
    "4. Use concise, natural Turkish dictionary form (verbs in infinitive -mak/-mek), 1 to 4 words each, lowercase, no parentheses, no explanations.",
    "5. Output ONLY the raw JSON object and nothing else.",
  ].join("\n");

  const userPrompt = contextSentence
    ? `Word: "${word}"\nContext sentence: "${contextSentence}"`
    : `Word: "${word}"`;

  const messages = [
    { role: "system", content: systemPrompt },
    { role: "user", content: userPrompt },
  ];

  let rawOutput;
  try {
    rawOutput = await ai.run(PRIMARY_AI_MODEL, {
      messages,
      temperature: 0.15,
      max_tokens: 220,
    });
  } catch (primaryErr) {
    const lower = String(primaryErr?.message || primaryErr || "").toLowerCase();
    if (lower.includes("quota") || lower.includes("limit") || lower.includes("429") || lower.includes("neuron")) {
      throw primaryErr;
    }
    rawOutput = await ai.run(FALLBACK_AI_MODEL, {
      messages,
      temperature: 0.15,
      max_tokens: 220,
    });
  }

  const text = extractModelText(rawOutput);
  return parseMeaningsJson(text);
}

function extractModelText(rawOutput) {
  if (!rawOutput) return "";
  if (typeof rawOutput === "string") return rawOutput;
  if (typeof rawOutput.response === "string") return rawOutput.response;
  if (rawOutput.response && typeof rawOutput.response === "object") {
    return JSON.stringify(rawOutput.response);
  }
  if (Array.isArray(rawOutput.choices) && rawOutput.choices[0]?.message?.content) {
    return String(rawOutput.choices[0].message.content);
  }
  return "";
}

function parseMeaningsJson(rawText) {
  const cleaned = String(rawText || "")
    .replace(/```json/gi, "")
    .replace(/```/g, "")
    .trim();

  const startIdx = cleaned.indexOf("{");
  const endIdx = cleaned.lastIndexOf("}");
  if (startIdx < 0 || endIdx <= startIdx) return null;

  let parsed;
  try {
    parsed = JSON.parse(cleaned.slice(startIdx, endIdx + 1));
  } catch (_) {
    return null;
  }

  const allowedPos = new Set([
    "noun",
    "verb",
    "adjective",
    "adverb",
    "phrase",
    "idiom",
    "preposition",
    "conjunction",
  ]);

  const rawList = Array.isArray(parsed?.meanings) ? parsed.meanings : [];
  const meanings = [];
  const seen = new Set();

  for (let i = 0; i < rawList.length && meanings.length < 4; i++) {
    const item = rawList[i];
    let translation = "";
    let pos = null;

    if (typeof item === "string") {
      translation = item.trim();
    } else if (item && typeof item === "object") {
      translation = String(item.translation || item.meaning || "").trim();
      const rawPos = String(item.partOfSpeech || item.part_of_speech || "")
        .trim()
        .toLowerCase();
      if (allowedPos.has(rawPos)) {
        pos = rawPos;
      }
    }

    translation = translation.replace(/\s+/g, " ").trim();
    if (!translation || translation.length > 64) continue;

    const dedupeKey = translation.replace(/İ/g, "i").toLowerCase();
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);

    meanings.push({
      translation,
      partOfSpeech: pos,
      isContextual: meanings.length === 0,
    });
  }

  return meanings.length > 0 ? { meanings } : null;
}

/* ---------------- Firebase JWT Doğrulama ---------------- */

async function verifyFirebaseIdToken(token) {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const header = JSON.parse(base64UrlToString(parts[0]));
    const payload = JSON.parse(base64UrlToString(parts[1]));

    if (header.alg !== "RS256" || !header.kid) return null;

    const nowSec = Math.floor(Date.now() / 1000);
    if (payload.aud !== FIREBASE_PROJECT_ID) return null;
    if (payload.iss !== FIREBASE_ISSUER) return null;
    if (!payload.sub || typeof payload.sub !== "string") return null;
    if (typeof payload.exp !== "number" || payload.exp <= nowSec) return null;
    if (typeof payload.iat !== "number" || payload.iat > nowSec + 300) return null;

    const signInProvider = payload?.firebase?.sign_in_provider;
    if (signInProvider === "anonymous") return null;

    const jwk = await getGooglePublicJwk(header.kid);
    if (!jwk) return null;

    const cryptoKey = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"]
    );

    const signedData = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const signatureBytes = base64UrlToBytes(parts[2]);

    const isValid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      cryptoKey,
      signatureBytes,
      signedData
    );

    if (!isValid) return null;
    return {
    uid: payload.sub,
    email: payload.email || "",
    emailVerified: Boolean(payload.email_verified),
    displayName: payload.name || "",
    authProvider: normalizeAuthProvider(payload.firebase?.sign_in_provider || ""),
  };
  } catch (_) {
    return null;
  }
}

async function getGooglePublicJwk(kid) {
  const now = Date.now();
  if (cachedJwks && now < cachedJwksExpiresAt) {
    const found = cachedJwks.find((k) => k.kid === kid);
    if (found) return found;
  }

  const res = await fetch(GOOGLE_JWKS_URL, {
    cf: { cacheTtl: 3600, cacheEverything: true },
  });
  if (!res.ok) return null;

  const data = await res.json();
  if (!Array.isArray(data?.keys)) return null;

  const cacheControl = res.headers.get("Cache-Control") || "";
  const maxAgeMatch = cacheControl.match(/max-age=(\d+)/i);
  const maxAgeMs = maxAgeMatch ? Number(maxAgeMatch[1]) * 1000 : 3600 * 1000;

  cachedJwks = data.keys;
  cachedJwksExpiresAt = Date.now() + Math.max(300000, maxAgeMs);

  return cachedJwks.find((k) => k.kid === kid) || null;
}

function base64UrlToBytes(input) {
  const padded =
    input.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (input.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function base64UrlToString(input) {
  return new TextDecoder().decode(base64UrlToBytes(input));
}

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
