#!/usr/bin/env node
/**
 * Line Reader — Gerçek Açık Kaynak EN-TR Sözlük (FreeDict eng-tur) İşleyici
 *
 * OpenSubtitles/Tatoeba örnek cümlelerine (`examples_json`) DOKUNMADAN,
 * D1 `corpus_lexicon.meanings_json` alanını gerçek sözlük anlamlarıyla günceller.
 *
 * Kullanım:
 *   node update_meanings_dict.mjs
 */

import fs from 'node:fs';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RAW_DIR = path.join(__dirname, 'raw', 'freedict');
const OUT_DIR = path.join(__dirname, 'out', 'dict_batches');

const FREEDICT_URLS = [
  'https://raw.githubusercontent.com/freedict/fd-dictionaries/master/eng-tur/eng-tur.tei',
  'https://raw.githubusercontent.com/freedict/fd-dictionaries/main/eng-tur/eng-tur.tei',
];

function downloadText(url, dest, redirects = 0) {
  return new Promise((resolve, reject) => {
    if (fs.existsSync(dest) && fs.statSync(dest).size > 10000) {
      console.log(`[Atlandı] Zaten mevcut: ${path.basename(dest)}`);
      resolve(true);
      return;
    }

    fs.mkdirSync(path.dirname(dest), { recursive: true });
    console.log(`[İndiriliyor] ${url}`);

    const req = https.get(
      url,
      { headers: { 'User-Agent': 'LineReader-DictBuilder/1.0' } },
      (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location &&
          redirects < 5
        ) {
          res.resume();
          const nextUrl = new URL(res.headers.location, url).toString();
          downloadText(nextUrl, dest, redirects + 1).then(resolve, reject);
          return;
        }
        if (res.statusCode !== 200) {
          res.resume();
          reject(new Error(`HTTP ${res.statusCode}`));
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          fs.writeFileSync(dest, Buffer.concat(chunks));
          resolve(true);
        });
      }
    );
    req.setTimeout(45000, () => req.destroy(new Error('Zaman aşımı')));
    req.on('error', reject);
  });
}

function decodeXmlEntities(str) {
  return str
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function parseFreeDictTei(xmlText) {
  const dict = new Map();
  const entryRe = /<entry\b[^>]*>([\s\S]*?)<\/entry>/gi;
  const orthRe = /<orth[^>]*>([\s\S]*?)<\/orth>/i;
  const quoteRe = /<cit[^>]*type=["']trans["'][^>]*>[\s\S]*?<quote[^>]*>([\s\S]*?)<\/quote>[\s\S]*?<\/cit>/gi;
  const fallbackQuoteRe = /<quote[^>]*>([\s\S]*?)<\/quote>/gi;

  let entryMatch;
  while ((entryMatch = entryRe.exec(xmlText)) !== null) {
    const block = entryMatch[1];
    const orthMatch = orthRe.exec(block);
    if (!orthMatch) continue;

    const rawWord = decodeXmlEntities(orthMatch[1].replace(/<[^>]+>/g, ''))
      .replace(/İ/g, 'i')
      .toLowerCase();

    if (!/^[a-z]{2,24}$/.test(rawWord)) continue;

    const meanings = [];
    const seen = new Set();

    const addTranslation = (raw) => {
      const cleaned = decodeXmlEntities(raw.replace(/<[^>]+>/g, ''))
        .replace(/\([^)]*\)/g, '')
        .trim();
      if (!cleaned || cleaned.length > 48) return;
      // Virgül veya noktalı virgülle ayrılmış çoklu karşılıkları ayır
      for (const part of cleaned.split(/[;,]/)) {
        const item = part.trim();
        if (item.length < 2 || item.length > 36) continue;
        const key = item.replace(/İ/g, 'i').toLowerCase();
        if (!seen.has(key)) {
          seen.add(key);
          meanings.push(item);
          if (meanings.length >= 12) return;
        }
      }
    };

    let qMatch;
    let foundTrans = false;
    quoteRe.lastIndex = 0;
    while ((qMatch = quoteRe.exec(block)) !== null) {
      foundTrans = true;
      addTranslation(qMatch[1]);
      if (meanings.length >= 12) break;
    }

    if (!foundTrans) {
      fallbackQuoteRe.lastIndex = 0;
      while ((qMatch = fallbackQuoteRe.exec(block)) !== null) {
        addTranslation(qMatch[1]);
        if (meanings.length >= 12) break;
      }
    }

    if (meanings.length === 0) continue;

    const existing = dict.get(rawWord);
    if (!existing) {
      dict.set(rawWord, meanings);
    } else {
      const existingKeys = new Set(existing.map((m) => m.replace(/İ/g, 'i').toLowerCase()));
      for (const m of meanings) {
        const k = m.replace(/İ/g, 'i').toLowerCase();
        if (!existingKeys.has(k) && existing.length < 15) {
          existing.push(m);
          existingKeys.add(k);
        }
      }
    }
  }

  return dict;
}

function sqlEscape(val) {
  return `'${String(val).replace(/'/g, "''")}'`;
}

function writeSqlBatches(dict) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  for (const f of fs.readdirSync(OUT_DIR)) {
    if (f.startsWith('dict_batch_') && f.endsWith('.sql')) {
      fs.unlinkSync(path.join(OUT_DIR, f));
    }
  }

  // 0. adım: Eski istatistiksel anlamları sıfırla (examples_json korunur!)
  fs.writeFileSync(
    path.join(OUT_DIR, 'dict_batch_0000.sql'),
    "UPDATE corpus_lexicon SET meanings_json = '[]';\n",
    'utf8'
  );

  const entries = [...dict.entries()];
  const fileRowsLimit = 350;
  const stmtRowsLimit = 25;
  const nowIso = new Date().toISOString();
  let fileCount = 0;

  for (let i = 0; i < entries.length; i += fileRowsLimit) {
    const fileChunk = entries.slice(i, i + fileRowsLimit);
    fileCount++;
    const fileName = `dict_batch_${String(fileCount).padStart(4, '0')}.sql`;
    const statements = [];

    for (let j = 0; j < fileChunk.length; j += stmtRowsLimit) {
      const sub = fileChunk.slice(j, j + stmtRowsLimit);
      const values = sub.map(([word, meanings]) => {
        const mJson = JSON.stringify(meanings);
        return `(${sqlEscape(word)}, ${sqlEscape(mJson)}, '[]', 999999, ${sqlEscape(nowIso)})`;
      });

      statements.push(
        'INSERT INTO corpus_lexicon (word, meanings_json, examples_json, freq_rank, updated_at)\nVALUES\n  ' +
          values.join(',\n  ') +
          '\nON CONFLICT(word) DO UPDATE SET\n' +
          '  meanings_json = excluded.meanings_json,\n' +
          '  updated_at = excluded.updated_at;'
      );
    }

    fs.writeFileSync(path.join(OUT_DIR, fileName), statements.join('\n\n') + '\n', 'utf8');
  }

  return fileCount + 1;
}

async function main() {
  const teiPath = path.join(RAW_DIR, 'eng-tur.tei');
  let ok = false;
  for (const url of FREEDICT_URLS) {
    try {
      await downloadText(url, teiPath);
      ok = true;
      break;
    } catch (err) {
      console.log(`[Uyarı] ${url} başarısız: ${err.message}`);
    }
  }

  if (!ok) {
    console.error('[Hata] FreeDict eng-tur.tei indirilemedi.');
    process.exit(1);
  }

  console.log('[İşleniyor] FreeDict eng-tur.tei ayrıştırılıyor...');
  const xmlText = fs.readFileSync(teiPath, 'utf8');
  const dict = parseFreeDictTei(xmlText);
  console.log(`[Sözlük] ${dict.size.toLocaleString()} İngilizce kelime için gerçek Türkçe anlam çıkarıldı.`);

  if (dict.size === 0) {
    console.error('[Hata] Hiç kelime ayrıştırılamadı.');
    process.exit(1);
  }

  const totalFiles = writeSqlBatches(dict);
  console.log(`\n[Tamamlandı] ${totalFiles} adet SQL dosyası oluşturuldu (${OUT_DIR}).`);
  console.log('Örnek (turkey):', dict.get('turkey'));
  console.log('Örnek (operation):', dict.get('operation'));
  console.log('\nSıradaki adım (D1 güncelleme):');
  console.log('  .\\upload_dict_to_d1.ps1');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
