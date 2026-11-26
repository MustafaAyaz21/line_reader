#!/usr/bin/env node
/**
 * Line Reader — OpenSubtitles & Tatoeba Ön-İşleme Betiği (Node.js)
 * Sıfır harici npm paketi gerektirir.
 *
 * Kullanım:
 *   node build_lexicon_corpus.mjs
 *   node build_lexicon_corpus.mjs --max-words 25000 --batch-size 350
 */

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..', '..');
const RAW_DIR = path.join(__dirname, 'raw');
const OUT_DIR = path.join(__dirname, 'out');
const SQL_DIR = path.join(OUT_DIR, 'd1_batches');
const LEXICON_CORE_PATH = path.join(PROJECT_ROOT, 'assets', 'lexicon_core.json.gz');

const WORD_RE = /\b[a-z]{2,20}\b/g;
const TR_WORD_RE = /[a-zçğıöşü]{2,24}/g;
const STAGE_NOTE_RE = /(\[[^\]]*\]|\([^)]*\)|♪|<[^>]*>)/g;
const BAD_CHARS_RE = /(http|www\.|@|#|\d{2}:\d{2}|-->)/i;

const PROFANITY = new Set([
  'fuck', 'fucking', 'fucked', 'fucker', 'shit', 'bullshit', 'bitch', 'asshole',
  'bastard', 'dick', 'cock', 'pussy', 'cunt', 'whore', 'slut', 'motherfucker',
  'damn', 'goddamn', 'crap', 'piss', 'nigger', 'faggot',
]);

const EN_STOPWORDS = new Set([
  'the', 'a', 'an', 'and', 'or', 'but', 'if', 'in', 'on', 'at', 'to', 'for',
  'of', 'with', 'by', 'from', 'as', 'is', 'are', 'was', 'were', 'be', 'been',
  'am', 'it', 'its', 'this', 'that', 'these', 'those', 'he', 'she', 'they',
  'we', 'you', 'i', 'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his',
  'our', 'their', 'what', 'which', 'who', 'whom', 'whose', 'when', 'where',
  'why', 'how', 'not', 'no', 'yes', 'so', 'do', 'does', 'did', 'will', 'would',
  'can', 'could', 'should', 'may', 'might', 'must', 'shall', 'have', 'has', 'had',
]);

const TR_STOPWORDS = new Set([
  'bir', 've', 'bu', 'da', 'de', 'ile', 'için', 'ama', 'fakat', 'ancak',
  'ben', 'sen', 'o', 'biz', 'siz', 'onlar', 'beni', 'seni', 'onu', 'bizi',
  'bana', 'sana', 'ona', 'bize', 'size', 'benim', 'senin', 'onun', 'bizim',
  'sizin', 'onların', 'ne', 'neden', 'niçin', 'nasıl', 'nerede', 'kim',
  'mi', 'mı', 'mu', 'mü', 'var', 'yok', 'evet', 'hayır', 'çok', 'daha',
  'en', 'gibi', 'kadar', 'olarak', 'olan', 'oldu', 'olur', 'değil', 'şey',
  'şu', 'oğlum', 'kızım', 'baba', 'anne', 'efendim', 'lütfen', 'tamam',
  'şimdi', 'burada', 'orada', 'zaten', 'belki', 'sadece', 'bile', 'ise',
  'diye', 'ki', 'ya', 'veya', 'hem', 'her', 'hiç', 'böyle', 'şöyle',
]);

function getArg(name, fallback) {
  const idx = process.argv.indexOf(name);
  if (idx !== -1 && process.argv[idx + 1]) {
    const parsed = Number(process.argv[idx + 1]);
    if (Number.isFinite(parsed) && parsed > 0) return parsed;
  }
  return fallback;
}

function cleanSentence(text) {
  let s = text.replace(STAGE_NOTE_RE, ' ').replace(/""/g, '"').trim();
  if (s.startsWith('- ')) s = s.slice(2).trim();
  return s.replace(/\s+/g, ' ').trim();
}

function isQualityPair(en, tr) {
  if (!en || !tr) return false;
  if (BAD_CHARS_RE.test(en) || BAD_CHARS_RE.test(tr)) return false;
  if ((en.match(/"/g) || []).length % 2 !== 0) return false;
  if (en.startsWith('...') || en.startsWith('-') || en.startsWith('*')) return false;

  const enWords = en.split(' ');
  const trWords = tr.split(' ');
  if (enWords.length < 7 || enWords.length > 22) return false;
  if (trWords.length < 3 || trWords.length > 24) return false;
  if (en.length < 30 || en.length > 180) return false;
  if (!/^[A-Z]/.test(en) || !/[.!?]$/.test(en)) return false;

  const lower = en.toLowerCase();
  const tokens = lower.match(WORD_RE) || [];
  if (tokens.length < 6) return false;
  for (const t of tokens) {
    if (PROFANITY.has(t)) return false;
  }

  let upperCount = 0;
  for (let i = 0; i < en.length; i++) {
    const ch = en[i];
    if (ch >= 'A' && ch <= 'Z') upperCount++;
  }
  if (upperCount > en.length * 0.25) return false;

  return true;
}

function scoreSentence(en, source) {
  const words = en.split(' ').length;
  let score = 100;
  if (words >= 9 && words <= 17) score += 35;
  else if (words >= 8 && words <= 20) score += 15;
  if (source === 'tatoeba') score += 20;
  if (en.endsWith('.')) score += 5;
  if (!en.includes("'") && !en.includes('"')) score += 5;
  return score;
}

function loadCoreWords() {
  if (!fs.existsSync(LEXICON_CORE_PATH)) return new Set();
  try {
    const gz = fs.readFileSync(LEXICON_CORE_PATH);
    const json = JSON.parse(zlib.gunzipSync(gz).toString('utf8'));
    const out = new Set();
    for (const k of Object.keys(json)) {
      const clean = k.trim().toLowerCase();
      if (/^[a-z]{2,20}$/.test(clean)) out.add(clean);
    }
    return out;
  } catch (err) {
    console.log(`[Uyarı] lexicon_core.json.gz okunamadı: ${err.message}`);
    return new Set();
  }
}

function trContentTokens(trSentence) {
  const lowered = trSentence.replace(/İ/g, 'i').replace(/I/g, 'ı').toLowerCase();
  const matches = lowered.match(TR_WORD_RE) || [];
  return matches.filter((t) => t.length >= 3 && !TR_STOPWORDS.has(t));
}

async function readParallelFiles(enPath, trPath, source, maxLines, pairs, wordFreq, seenEn) {
  if (!fs.existsSync(enPath) || !fs.existsSync(trPath)) return 0;

  const rlEn = readline.createInterface({ input: fs.createReadStream(enPath, 'utf8'), crlfDelay: Infinity });
  const rlTr = readline.createInterface({ input: fs.createReadStream(trPath, 'utf8'), crlfDelay: Infinity });

  const itEn = rlEn[Symbol.asyncIterator]();
  const itTr = rlTr[Symbol.asyncIterator]();

  let lineNo = 0;
  let added = 0;
  while (lineNo < maxLines) {
    const [r1, r2] = await Promise.all([itEn.next(), itTr.next()]);
    if (r1.done || r2.done) break;
    lineNo++;

    const en = cleanSentence(r1.value);
    const tr = cleanSentence(r2.value);
    if (!isQualityPair(en, tr)) continue;

    const key = en.toLowerCase();
    if (seenEn.has(key)) continue;
    seenEn.add(key);

    pairs.push([en, tr, source]);
    added++;

    const toks = new Set(key.match(WORD_RE) || []);
    for (const tok of toks) {
      wordFreq.set(tok, (wordFreq.get(tok) || 0) + 1);
    }
  }
  rlEn.close();
  rlTr.close();
  return added;
}

function pickDiverseExamples(candidates, limit = 3) {
  candidates.sort((a, b) => b[0] - a[0]);
  const selected = [];
  const usedRoots = new Set();

  for (const [, en, tr, source] of candidates) {
    const roots = new Set(trContentTokens(tr).map((t) => t.slice(0, 5)));
    let diff = 0;
    for (const r of roots) if (!usedRoots.has(r)) diff++;

    if (selected.length === 0 || diff >= 2) {
      selected.push({ english: en, turkish: tr, source });
      for (const r of roots) usedRoots.add(r);
      if (selected.length >= limit) return selected;
    }
  }

  const chosenEn = new Set(selected.map((s) => s.english.toLowerCase()));
  for (const [, en, tr, source] of candidates) {
    if (chosenEn.has(en.toLowerCase())) continue;
    selected.push({ english: en, turkish: tr, source });
    chosenEn.add(en.toLowerCase());
    if (selected.length >= limit) break;
  }

  return selected;
}

function inferRankedMeanings(wordTrCounter, globalTrFreq, totalPairs, wordCount, maxMeanings = 10) {
  if (wordCount < 3 || totalPairs === 0) return [];

  const entries = [...wordTrCounter.entries()]
    .filter(([, c]) => c >= 2)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 60);

  const scored = [];
  const seenRoots = new Set();

  for (const [trTok, coCount] of entries) {
    const gFreq = globalTrFreq.get(trTok) || 1;
    const pmi = Math.log2((coCount * totalPairs) / (wordCount * gFreq) + 1.0);
    const score = coCount * Math.max(pmi, 0.2);
    const root = trTok.slice(0, 5);
    if (seenRoots.has(root)) continue;
    seenRoots.add(root);
    scored.push([score, trTok]);
  }

  scored.sort((a, b) => b[0] - a[0]);
  return scored.slice(0, maxMeanings).map((x) => x[1]);
}

function sqlEscape(val) {
  return `'${String(val).replace(/'/g, "''")}'`;
}

function writeD1Batches(rows, batchSize) {
  fs.mkdirSync(SQL_DIR, { recursive: true });
  for (const f of fs.readdirSync(SQL_DIR)) {
    if (f.startsWith('batch_') && f.endsWith('.sql')) {
      fs.unlinkSync(path.join(SQL_DIR, f));
    }
  }

  const nowIso = new Date().toISOString();
  const stmtRowsLimit = 25; // D1 tek SQL statement 100 KB limitini aşmamak için
  let fileCount = 0;

  for (let i = 0; i < rows.length; i += batchSize) {
    const fileChunk = rows.slice(i, i + batchSize);
    fileCount++;
    const fileName = `batch_${String(fileCount).padStart(4, '0')}.sql`;
    const statements = [];

    for (let j = 0; j < fileChunk.length; j += stmtRowsLimit) {
      const sub = fileChunk.slice(j, j + stmtRowsLimit);
      const values = sub.map(([word, meanings, examples, rank]) => {
        const mJson = JSON.stringify(meanings);
        const eJson = JSON.stringify(examples);
        return `(${sqlEscape(word)}, ${sqlEscape(mJson)}, ${sqlEscape(eJson)}, ${rank}, ${sqlEscape(nowIso)})`;
      });

      statements.push(
        'INSERT INTO corpus_lexicon (word, meanings_json, examples_json, freq_rank, updated_at)\nVALUES\n  ' +
          values.join(',\n  ') +
          '\nON CONFLICT(word) DO UPDATE SET\n' +
          '  meanings_json = excluded.meanings_json,\n' +
          '  examples_json = excluded.examples_json,\n' +
          '  freq_rank = excluded.freq_rank,\n' +
          '  updated_at = excluded.updated_at;'
      );
    }

    fs.writeFileSync(path.join(SQL_DIR, fileName), statements.join('\n\n') + '\n', 'utf8');
  }

  return fileCount;
}

async function main() {
  const maxWords = getArg('--max-words', 25000);
  const maxSubtitleLines = getArg('--max-subtitle-lines', 2000000);
  const batchSize = getArg('--batch-size', 350);

  const pairs = [];
  const wordFreq = new Map();
  const seenEn = new Set();

  const tatEn = path.join(RAW_DIR, 'tatoeba', 'Tatoeba.en-tr.en');
  const tatTr = path.join(RAW_DIR, 'tatoeba', 'Tatoeba.en-tr.tr');
  const tatAdded = await readParallelFiles(tatEn, tatTr, 'tatoeba', 1000000, pairs, wordFreq, seenEn);
  if (tatAdded > 0) console.log(`[Korpus] Tatoeba: ${tatAdded.toLocaleString()} kaliteli cümle alındı.`);

  const subEn = path.join(RAW_DIR, 'opensubtitles', 'OpenSubtitles.en-tr.en');
  const subTr = path.join(RAW_DIR, 'opensubtitles', 'OpenSubtitles.en-tr.tr');
  const subAdded = await readParallelFiles(subEn, subTr, 'subtitle', maxSubtitleLines, pairs, wordFreq, seenEn);
  if (subAdded > 0) console.log(`[Korpus] OpenSubtitles: ${subAdded.toLocaleString()} kaliteli film/dizi alıntısı alındı.`);

  if (pairs.length === 0) {
    console.error('[Hata] İşlenecek korpus bulunamadı! Önce `node download_corpora.mjs` çalıştırın.');
    process.exit(1);
  }

  const coreWords = loadCoreWords();
  console.log(`[Kelime Havuzu] Çekirdek sözlük: ${coreWords.size.toLocaleString()} kelime`);

  const sortedByFreq = [...wordFreq.entries()]
    .filter(([w]) => !EN_STOPWORDS.has(w) && !PROFANITY.has(w) && w.length >= 2)
    .sort((a, b) => b[1] - a[1])
    .slice(0, maxWords * 2)
    .map(([w]) => w);

  const targetLookup = new Set();
  for (const w of coreWords) {
    if (!PROFANITY.has(w)) targetLookup.add(w);
    if (targetLookup.size >= maxWords) break;
  }
  for (const w of sortedByFreq) {
    if (targetLookup.size >= maxWords) break;
    targetLookup.add(w);
  }

  console.log(`[Hedef] ${targetLookup.size.toLocaleString()} İngilizce kelime indeksleniyor...`);

  const wordCandidates = new Map();
  const wordTrCo = new Map();
  const globalTrFreq = new Map();

  for (const [en, tr, source] of pairs) {
    const trToks = new Set(trContentTokens(tr));
    for (const t of trToks) {
      globalTrFreq.set(t, (globalTrFreq.get(t) || 0) + 1);
    }

    const enToks = new Set(en.toLowerCase().match(WORD_RE) || []);
    const baseScore = scoreSentence(en, source);
    for (const w of enToks) {
      if (!targetLookup.has(w)) continue;
      let bucket = wordCandidates.get(w);
      if (!bucket) {
        bucket = [];
        wordCandidates.set(w, bucket);
      }
      if (bucket.length < 30) {
        bucket.push([baseScore, en, tr, source]);
      }

      let coMap = wordTrCo.get(w);
      if (!coMap) {
        coMap = new Map();
        wordTrCo.set(w, coMap);
      }
      for (const t of trToks) {
        coMap.set(t, (coMap.get(t) || 0) + 1);
      }
    }
  }

  const orderedTargets = [...targetLookup].sort(
    (a, b) => (wordFreq.get(b) || 0) - (wordFreq.get(a) || 0)
  );

  const rows = [];
  const totalPairs = pairs.length;
  let rank = 0;

  for (const word of orderedTargets) {
    rank++;
    const cands = wordCandidates.get(word);
    if (!cands || cands.length === 0) continue;
    const examples = pickDiverseExamples(cands, 3);
    if (examples.length === 0) continue;
    const meanings = inferRankedMeanings(
      wordTrCo.get(word) || new Map(),
      globalTrFreq,
      totalPairs,
      wordFreq.get(word) || cands.length
    );
    rows.push([word, meanings, examples, rank]);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const batchCount = writeD1Batches(rows, batchSize);

  const summary = {
    total_corpus_pairs: totalPairs,
    indexed_words: rows.length,
    sql_batch_files: batchCount,
    sample_preview: Object.fromEntries(
      rows.slice(0, 5).map(([w, m, ex]) => [w, { meanings: m, examples: ex }])
    ),
  };
  fs.writeFileSync(path.join(OUT_DIR, 'corpus_summary.json'), JSON.stringify(summary, null, 2), 'utf8');

  console.log('\n[Tamamlandı]');
  console.log(`  İndekslenen kelime sayısı : ${rows.length.toLocaleString()}`);
  console.log(`  Üretilen D1 SQL dosyası   : ${batchCount} adet (${SQL_DIR})`);
  console.log(`  Özet dosya                : ${path.join(OUT_DIR, 'corpus_summary.json')}`);
  console.log('\nSıradaki adım (Cloudflare D1\'e yükleme):');
  console.log('  .\\upload_to_d1.ps1');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
