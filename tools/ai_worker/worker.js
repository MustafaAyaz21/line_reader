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

    // 2) Herkese açık anlık makale akışı (Cloudflare D1 — 1 saniye altı yayın)
    if (method === "GET" && (path === "/articles" || path === "/articles.json")) {
      return handleGetArticlesFeed(request, env);
    }

    // 2.5) Herkese açık D1 önbellekli doğal örnek cümle servisi (8-22 kelimelik cümleler)
    if ((method === "GET" || method === "POST") && path === "/examples") {
      return handleWordExamples(request, env, url);
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

    if (method === "POST" && path === "/redeem") {
      return handleRedeemCode(request, env, verifiedUser);
    }

    if (method === "POST" && (path === "/" || path === "/translate")) {
      return handleBrowserAiTranslate(request, env, verifiedUser);
    }

    // 4) Mobil Geliştirici Paneli uç noktaları (Firebase ID Token + D1 source='admin' zorunlu)
    if (path.startsWith("/dev/")) {
      return handleDeveloperPanelRequest(request, env, verifiedUser, path, method);
    }

    return jsonResponse({ error: "not_found" }, 404);
  },
};

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

  // 1) Önce Cloudflare D1 önbelleğine bak (maliyetsiz ve <100ms).
  if (env && env.DB) {
    try {
      await ensureSchema(env.DB);
      const cached = await env.DB
        .prepare("SELECT examples_json FROM word_examples_cache WHERE word = ? LIMIT 1")
        .bind(word)
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
    "You are an expert English-Turkish dictionary editor.",
    "Write EXACTLY 3 natural, meaningful, real-life English example sentences for the given English word or expression, with fluent Turkish translations.",
    "Strict rules:",
    "1. Every English sentence MUST be a complete, natural sentence between 10 and 18 words long (never shorter than 8 words, never longer than 22 words).",
    "2. Every sentence MUST naturally use the target word or expression in a clear, realistic context (daily life, work, travel, technology, news, or conversation).",
    "3. Use 3 distinct, varied contexts. Never write dictionary definitions, bare phrases, or robotic templates like 'We talked about X in class today'.",
    "4. Provide a natural, idiomatic Turkish translation for each sentence.",
    '5. Respond ONLY with valid JSON: {"examples":[{"english":"...","turkish":"..."},{"english":"...","turkish":"..."},{"english":"...","turkish":"..."}]}',
  ].join("\n");

  const userPrompt = `Target word or expression: "${word}"\nReturn ONLY the JSON object.`;

  try {
    const aiResult = await env.AI.run(MODEL_ID, {
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.35,
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
          .bind(word, JSON.stringify(validExamples), new Date().toISOString())
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
  ]);
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
    const role = ent.isUnlimited
      ? (String(ent.source || "").toLowerCase() === "admin" ? "admin" : "premium")
      : "standard";
    return jsonResponse({
      ok: true,
      uid: user.uid,
      email: user.email,
      is_unlimited: ent.isUnlimited,
      source: ent.source,
      role,
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

  // 1) Premium kullanıcı yönetimi (Geliştirici rolleri yalnızca PC panelinden değiştirilebilir)
  if (path === "/dev/users") {
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

    const existing = await env.DB
      .prepare("SELECT email, source FROM user_entitlements WHERE LOWER(email) = ? LIMIT 1")
      .bind(email)
      .first();

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
          INSERT INTO user_entitlements (email, uid, is_unlimited, source, code_used, granted_at)
          VALUES (?, NULL, 1, 'manual', ?, ?)
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
      await env.DB
        .prepare("DELETE FROM user_entitlements WHERE LOWER(email) = ? AND LOWER(source) != 'admin'")
        .bind(email)
        .run();
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
        is_hidden: Boolean(a.is_hidden),
        publish_at: a.publish_at || null,
        has_audio: Boolean(a.audio_url && String(a.audio_url).trim().length > 0),
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
    if (!env.GEMINI_API_KEY) {
      return jsonResponse({
        ok: false,
        error: "gemini_key_missing",
        message: "Cloudflare Worker içinde GEMINI_API_KEY tanımlı değil. Settings → Variables and Secrets bölümünden ekleyin.",
      }, 503);
    }
    const body = await safeReadJson(request);
    const rawLevel = String(body?.level || "B1").trim().toUpperCase();
    const level = ["A1", "A2", "B1", "B2", "C1", "C2"].includes(rawLevel) ? rawLevel : "B1";
    const topic = String(body?.topic || "").trim().slice(0, 160);
    try {
      const generated = await generateArticleWithGemini(String(env.GEMINI_API_KEY).trim(), level, topic);
      return jsonResponse({ ok: true, article: generated });
    } catch (err) {
      return jsonResponse({
        ok: false,
        error: "gemini_generate_failed",
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
    const articleObj = {
      id,
      level,
      title,
      content,
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

async function generateArticleWithGemini(apiKey, level, topic) {
  const topicInstruction = topic
    ? `Write the article specifically about this topic: "${topic}".`
    : "Choose an engaging, fresh, real-world topic suitable for English learners (science, psychology, culture, technology, daily life, history, or nature).";

  const levelWordTarget = {
    A1: "140 to 190 words in 3 short paragraphs using simple everyday vocabulary and short clear sentences",
    A2: "180 to 240 words in 3 to 4 paragraphs using clear pre-intermediate vocabulary",
    B1: "230 to 300 words in 4 paragraphs using natural intermediate English",
    B2: "270 to 350 words in 4 paragraphs using rich upper-intermediate English",
    C1: "300 to 390 words in 4 to 5 paragraphs using sophisticated advanced English",
    C2: "320 to 420 words in 4 to 5 paragraphs using nuanced, idiomatic mastery-level English",
  }[level] || "230 to 300 words in 4 paragraphs";

  const prompt = [
    `You are an expert English curriculum author creating a CEFR ${level} reading article for Turkish learners of English.`,
    topicInstruction,
    `Length & style: ${levelWordTarget}. Separate paragraphs with \\n\\n.`,
    "Return ONLY one valid JSON object (no markdown fences) with these EXACT keys:",
    "{",
    '  "title": "Engaging English title",',
    '  "content": "Full English article text with paragraphs separated by \\n\\n",',
    '  "word_meanings": { "lowercase_word": "exact contextual Turkish meaning in this article (for verbs use -mak/-mek)" },',
    '  "sentence_translations": { "Exact English sentence from content": "Natural, fluent Turkish translation" },',
    '  "word_relations": { "lowercase_word": { "syn": ["1-3 exact contextual English synonyms"], "ant": ["1-2 exact contextual English antonyms"] } }',
    "}",
    "Rules:",
    "1. Include ALL meaningful content words from the article in word_meanings (40 to 120 words, lowercase base/appeared forms) with their EXACT contextual Turkish meaning in this article.",
    "2. Include EVERY sentence from content in sentence_translations with exact punctuation.",
    "3. Include 25 to 60 key content words in word_relations with ONLY synonyms and antonyms that match the EXACT sense used in this article's sentences.",
  ].join("\n");

  const models = [
    "gemini-flash-latest",
    "gemini-3-flash-preview",
    "gemini-2.5-flash",
    "gemini-2.5-pro",
  ];
  // Eğer sabit modellerin hepsi 404 verirse API anahtarının desteklediği aktif Flash modelini otomatik keşfet.
  try {
    const listRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`
    );
    if (listRes.ok) {
      const listData = await listRes.json();
      const apiModels = Array.isArray(listData?.models) ? listData.models : [];
      for (const m of apiModels) {
        const name = String(m?.name || "").replace(/^models\//, "");
        const methods = Array.isArray(m?.supportedGenerationMethods)
          ? m.supportedGenerationMethods
          : [];
        if (
          methods.includes("generateContent") &&
          name.includes("gemini") &&
          name.includes("flash") &&
          !name.includes("tts") &&
          !name.includes("image") &&
          !models.includes(name)
        ) {
          models.push(name);
        }
      }
    }
  } catch (_) {}

  let lastError = "Gemini yanıt vermedi.";

  for (const model of models) {
    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`;
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.65,
          responseMimeType: "application/json",
        },
      }),
    });
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
    const title = String(parsed.title || "").trim();
    const content = String(parsed.content || "").trim();
    if (!title || content.length < 40) {
      lastError = "Başlık veya metin eksik geldi.";
      continue;
    }
    return {
      id: `${level.toLowerCase()}-${slugifyArticleId(title)}`,
      level,
      title,
      content,
      word_meanings: parsed.word_meanings && typeof parsed.word_meanings === "object" ? parsed.word_meanings : {},
      sentence_translations: parsed.sentence_translations && typeof parsed.sentence_translations === "object" ? parsed.sentence_translations : {},
      word_relations: parsed.word_relations && typeof parsed.word_relations === "object" ? parsed.word_relations : {},
      is_hidden: false,
      publish_at: null,
    };
  }

  throw new Error(lastError);
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

    if (method === "POST" || method === "PATCH") {
      const requestedRole = String(body?.role || "").trim().toLowerCase();
      const isDeveloper = requestedRole === "admin" || requestedRole === "developer";
      const targetSource = isDeveloper ? "admin" : "manual";
      const roleLabel = isDeveloper ? "Geliştirici" : "Premium Üye";
      await env.DB
        .prepare(`
          INSERT INTO user_entitlements (email, uid, is_unlimited, source, code_used, granted_at)
          VALUES (?, NULL, 1, ?, NULL, ?)
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
