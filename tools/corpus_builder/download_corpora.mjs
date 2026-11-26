#!/usr/bin/env node
/**
 * Line Reader — OPUS OpenSubtitles (en-tr) & OPUS Tatoeba (en-tr) İndirici (Node.js)
 * Sıfır harici npm paketi gerektirir.
 *
 * Kullanım:
 *   node download_corpora.mjs
 *   node download_corpora.mjs --only tatoeba
 *   node download_corpora.mjs --only opensubtitles --force
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RAW_DIR = path.join(__dirname, 'raw');

const OPENSUBTITLES_URLS = [
  'https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2024/moses/en-tr.txt.zip',
  'https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/moses/en-tr.txt.zip',
];

const TATOEBA_URLS = [
  'https://object.pouta.csc.fi/OPUS-Tatoeba/v2023-04-12/moses/en-tr.txt.zip',
  'https://object.pouta.csc.fi/OPUS-Tatoeba/v2022-03-03/moses/en-tr.txt.zip',
];

function downloadFile(url, dest, force = false, redirects = 0) {
  return new Promise((resolve, reject) => {
    if (!force && fs.existsSync(dest) && fs.statSync(dest).size > 0) {
      console.log(`[Atlandı] Zaten mevcut: ${path.basename(dest)}`);
      resolve(true);
      return;
    }

    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const tmpPath = `${dest}.part`;
    console.log(`[İndiriliyor] ${url}`);

    const req = https.get(
      url,
      { headers: { 'User-Agent': 'LineReader-CorpusBuilder/1.0' } },
      (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location &&
          redirects < 5
        ) {
          res.resume();
          const nextUrl = new URL(res.headers.location, url).toString();
          downloadFile(nextUrl, dest, force, redirects + 1).then(resolve, reject);
          return;
        }

        if (res.statusCode !== 200) {
          res.resume();
          reject(new Error(`HTTP ${res.statusCode}`));
          return;
        }

        const total = Number(res.headers['content-length'] || 0);
        let downloaded = 0;
        let lastLog = 0;
        const out = fs.createWriteStream(tmpPath);

        res.on('data', (chunk) => {
          downloaded += chunk.length;
          const now = Date.now();
          if (total > 0 && now - lastLog > 500) {
            lastLog = now;
            const mb = (downloaded / (1024 * 1024)).toFixed(1);
            const totalMb = (total / (1024 * 1024)).toFixed(1);
            const pct = ((downloaded * 100) / total).toFixed(1);
            process.stdout.write(`\r  ${mb} / ${totalMb} MB (${pct}%)`);
          }
        });

        res.pipe(out);
        out.on('finish', () => {
          out.close(() => {
            if (total > 0) process.stdout.write('\n');
            fs.renameSync(tmpPath, dest);
            resolve(true);
          });
        });
        out.on('error', (err) => {
          try {
            fs.unlinkSync(tmpPath);
          } catch {}
          reject(err);
        });
      }
    );

    req.setTimeout(60000, () => {
      req.destroy(new Error('Zaman aşımı'));
    });
    req.on('error', (err) => {
      try {
        fs.unlinkSync(tmpPath);
      } catch {}
      reject(err);
    });
  });
}

function expandZip(zipPath, extractDir) {
  fs.mkdirSync(extractDir, { recursive: true });
  execFileSync(
    'powershell',
    [
      '-NoProfile',
      '-Command',
      `Expand-Archive -LiteralPath '${zipPath.replace(/'/g, "''")}' -DestinationPath '${extractDir.replace(/'/g, "''")}' -Force`,
    ],
    { stdio: 'inherit' }
  );
}

async function prepareCorpus(name, urls, targetDirName, prefixName, force) {
  const targetDir = path.join(RAW_DIR, targetDirName);
  const enOut = path.join(targetDir, `${prefixName}.en`);
  const trOut = path.join(targetDir, `${prefixName}.tr`);

  if (!force && fs.existsSync(enOut) && fs.existsSync(trOut)) {
    console.log(`[${name}] Paralel metin dosyaları zaten hazır.`);
    return;
  }

  fs.mkdirSync(targetDir, { recursive: true });
  const zipPath = path.join(targetDir, 'en-tr.txt.zip');

  let ok = false;
  for (const url of urls) {
    try {
      await downloadFile(url, zipPath, force);
      ok = true;
      break;
    } catch (err) {
      console.log(`[${name}] Deneme başarısız (${url}): ${err.message}`);
    }
  }

  if (!ok) {
    console.log(`[${name}] İndirilemedi.`);
    return;
  }

  console.log(`[${name}] Zip arşivi açılıyor...`);
  const extractDir = path.join(targetDir, '_extracted');
  expandZip(zipPath, extractDir);

  const files = fs.readdirSync(extractDir, { recursive: true }).map(String);
  for (const rel of files) {
    const full = path.join(extractDir, rel);
    if (!fs.statSync(full).isFile()) continue;
    if (rel.endsWith('.en')) {
      fs.renameSync(full, enOut);
      console.log(`  Hazır: ${path.basename(enOut)}`);
    } else if (rel.endsWith('.tr')) {
      fs.renameSync(full, trOut);
      console.log(`  Hazır: ${path.basename(trOut)}`);
    }
  }
  fs.rmSync(extractDir, { recursive: true, force: true });
}

async function main() {
  const args = process.argv.slice(2);
  const force = args.includes('--force');
  const onlyIdx = args.indexOf('--only');
  const only = onlyIdx !== -1 ? args[onlyIdx + 1] : 'all';

  if (only === 'all' || only === 'tatoeba') {
    await prepareCorpus('Tatoeba', TATOEBA_URLS, 'tatoeba', 'Tatoeba.en-tr', force);
  }
  if (only === 'all' || only === 'opensubtitles') {
    await prepareCorpus('OpenSubtitles', OPENSUBTITLES_URLS, 'opensubtitles', 'OpenSubtitles.en-tr', force);
  }

  console.log('\nİndirme/hazırlama tamamlandı. Sıradaki adım:');
  console.log('  node build_lexicon_corpus.mjs');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
