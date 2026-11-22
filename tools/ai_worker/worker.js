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
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Admin-Secret",
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
      });
    }

    // 2) Admin uç noktaları (PC Makale Paneli — X-Admin-Secret korumalı)
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

    if (method === "POST" && path === "/redeem") {
      return handleRedeemCode(request, env, verifiedUser);
    }

    if (method === "POST" && (path === "/" || path === "/translate")) {
      return handleBrowserAiTranslate(request, env, verifiedUser);
    }

    return jsonResponse({ error: "not_found" }, 404);
  },
};

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
        granted_at TEXT NOT NULL
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
  ]);
}

async function getUserEntitlement(db, user) {
  if (!db) return { isUnlimited: false, source: null, codeUsed: null };
  await ensureSchema(db);

  const email = (user.email || "").trim().toLowerCase();
  const uid = (user.uid || "").trim();

  let row = null;
  if (email) {
    row = await db
      .prepare("SELECT email, uid, is_unlimited, source, code_used FROM user_entitlements WHERE LOWER(email) = ? LIMIT 1")
      .bind(email)
      .first();
  }
  if (!row && uid) {
    row = await db
      .prepare("SELECT email, uid, is_unlimited, source, code_used FROM user_entitlements WHERE uid = ? LIMIT 1")
      .bind(uid)
      .first();
  }

  if (!row || Number(row.is_unlimited) !== 1) {
    return { isUnlimited: false, source: null, codeUsed: null };
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

  return {
    isUnlimited: true,
    source: row.source || "manual",
    codeUsed: row.code_used || null,
  };
}

async function handleGetMe(env, user) {
  try {
    const ent = await getUserEntitlement(env.DB, user);
    return jsonResponse({
      ok: true,
      uid: user.uid,
      email: user.email,
      is_unlimited: ent.isUnlimited,
      source: ent.source,
      code_used: ent.codeUsed,
    });
  } catch (err) {
    return jsonResponse({ error: "db_error", message: String(err?.message || err) }, 500);
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

  // Kullanıcı yetki yönetimi
  if (path === "/admin/users") {
    if (method === "GET") {
      const res = await env.DB
        .prepare("SELECT email, uid, is_unlimited, source, code_used, granted_at FROM user_entitlements ORDER BY granted_at DESC")
        .all();
      return jsonResponse({ ok: true, users: res.results || [] });
    }

    const body = await safeReadJson(request);
    const email = String(body?.email || "").trim().toLowerCase();
    if (!email || !email.includes("@")) {
      return jsonResponse({ ok: false, message: "Geçerli bir e-posta adresi girin." }, 400);
    }

    if (method === "POST") {
      await env.DB
        .prepare(`
          INSERT INTO user_entitlements (email, uid, is_unlimited, source, code_used, granted_at)
          VALUES (?, NULL, 1, 'manual', NULL, ?)
          ON CONFLICT(email) DO UPDATE SET
            is_unlimited = 1,
            source = 'manual',
            granted_at = excluded.granted_at
        `)
        .bind(email, new Date().toISOString())
        .run();
      return jsonResponse({ ok: true, message: `${email} hesabına sınırsız yetki verildi.` });
    }

    if (method === "DELETE") {
      await env.DB
        .prepare("DELETE FROM user_entitlements WHERE LOWER(email) = ?")
        .bind(email)
        .run();
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
    return { uid: payload.sub, email: payload.email || "" };
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
