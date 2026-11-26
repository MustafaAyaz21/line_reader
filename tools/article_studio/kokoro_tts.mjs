import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { KokoroTTS } from "kokoro-js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SAMPLE_RATE = 24000;

function writeProgress(progressPath, data) {
  if (!progressPath) return;
  try {
    const tmp = `${progressPath}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(data), "utf8");
    fs.renameSync(tmp, progressPath);
  } catch (_) {
    try {
      fs.writeFileSync(progressPath, JSON.stringify(data), "utf8");
    } catch (_) {}
  }
}

function sanitizeForTts(raw) {
  return String(raw || "")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
    .replace(/[\u2013\u2014]/g, ", ")
    .replace(/\u2026/g, "...")
    .replace(/\s+/g, " ")
    .trim();
}

function splitParagraphsWithSentences(content) {
  const rawParagraphs = String(content || "")
    .replace(/\r\n/g, "\n")
    .split(/\n{2,}/)
    .map((p) => sanitizeForTts(p))
    .filter((p) => /[a-zA-Z0-9]/.test(p));

  const paragraphs = [];
  for (let pIdx = 0; pIdx < rawParagraphs.length; pIdx++) {
    const pText = rawParagraphs[pIdx];
    const rawSentences = pText.match(/[^.!?]+(?:[.!?]+["')\]]*|$)/g) || [pText];
    const sentences = rawSentences
      .map((s) => s.trim())
      .filter((s) => /[a-zA-Z0-9]/.test(s));
    if (sentences.length === 0) continue;
    const isLast = pIdx === rawParagraphs.length - 1;
    paragraphs.push({
      text: pText,
      sentences,
      pauseMs: isLast ? 200 : 480,
    });
  }
  return paragraphs;
}

function encodeWavFromFloat32(floatChunks, sampleRate) {
  let totalSamples = 0;
  for (const chunk of floatChunks) {
    totalSamples += chunk.length;
  }

  const dataByteLen = totalSamples * 2;
  const buffer = Buffer.alloc(44 + dataByteLen);

  buffer.write("RIFF", 0, "ascii");
  buffer.writeUInt32LE(36 + dataByteLen, 4);
  buffer.write("WAVE", 8, "ascii");
  buffer.write("fmt ", 12, "ascii");
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write("data", 36, "ascii");
  buffer.writeUInt32LE(dataByteLen, 40);

  let offset = 44;
  for (const chunk of floatChunks) {
    for (let i = 0; i < chunk.length; i++) {
      let s = chunk[i];
      if (s > 1) s = 1;
      else if (s < -1) s = -1;
      const int16 = s < 0 ? Math.round(s * 32768) : Math.round(s * 32767);
      buffer.writeInt16LE(int16, offset);
      offset += 2;
    }
  }
  return buffer;
}

async function loadKokoroModel() {
  try {
    return await KokoroTTS.from_pretrained("onnx-community/Kokoro-82M-v1.0-ONNX", {
      dtype: "q8",
      device: "cpu",
    });
  } catch (err) {
    const msg = String(err?.message || err);
    if (msg.includes("Protobuf") || msg.includes("parsing failed") || msg.includes("corrupt")) {
      const cacheDir = path.join(__dirname, "node_modules", "@huggingface", "transformers", ".cache");
      try { fs.rmSync(cacheDir, { recursive: true, force: true }); } catch (_) {}
      return await KokoroTTS.from_pretrained("onnx-community/Kokoro-82M-v1.0-ONNX", {
        dtype: "q8",
        device: "cpu",
      });
    }
    throw err;
  }
}

async function main() {
  const args = process.argv.slice(2);
  const inputJsonPath = args[0];
  const outWavPath = args[1];
  const outMetaPath = args[2];
  const progressPath = args[3] || null;

  if (!inputJsonPath || !outWavPath) {
    console.error("Usage: node kokoro_tts.mjs <input.json> <out.wav> [out.meta.json] [progress.json]");
    process.exit(1);
  }

  const startedAt = Date.now();
  const input = JSON.parse(fs.readFileSync(inputJsonPath, "utf8"));
  const voice = input.voice || "af_heart";
  const text = String(input.text || "").trim();

  if (!text) {
    console.error("Bos metin.");
    process.exit(1);
  }

  const paragraphs = splitParagraphsWithSentences(text);
  const totalParagraphs = paragraphs.length;
  const totalAllChars = paragraphs.reduce((acc, p) => acc + Math.max(1, p.text.length), 0);

  writeProgress(progressPath, {
    phase: "loading_model",
    completed: 0,
    total: totalParagraphs,
    percent: 4,
    elapsedMs: Date.now() - startedAt,
    etaMs: null,
    message: "Kokoro AI modeli yükleniyor...",
  });

  const tts = await loadKokoroModel();
  const synthStartedAt = Date.now();

  writeProgress(progressPath, {
    phase: "synthesizing",
    completed: 0,
    total: totalParagraphs,
    percent: 8,
    elapsedMs: Date.now() - startedAt,
    etaMs: null,
    message: `Paragraf 1 / ${totalParagraphs} seslendiriliyor...`,
  });

  const pcmChunks = [];
  const segments = [];
  let cursorMs = 0;
  let processedChars = 0;

  for (let pIdx = 0; pIdx < paragraphs.length; pIdx++) {
    const para = paragraphs[pIdx];
    const generated = await tts.generate(para.text, { voice });
    const samples = generated.audio;
    const sr = generated.sampling_rate || SAMPLE_RATE;
    const paraDurationMs = Math.round((samples.length * 1000) / sr);

    const totalChars = para.sentences.reduce((acc, s) => acc + Math.max(1, s.length), 0);
    let localCursorMs = cursorMs;
    for (let i = 0; i < para.sentences.length; i++) {
      const s = para.sentences[i];
      const isLast = i === para.sentences.length - 1;
      const share = Math.round((paraDurationMs * Math.max(1, s.length)) / totalChars);
      const endMs = isLast ? cursorMs + paraDurationMs : localCursorMs + share;
      segments.push({
        text: s,
        start_ms: localCursorMs,
        end_ms: Math.max(localCursorMs + 250, endMs),
      });
      localCursorMs = endMs;
    }

    pcmChunks.push(samples);
    cursorMs += paraDurationMs;

    if (para.pauseMs > 0) {
      const silenceSamples = Math.round((sr * para.pauseMs) / 1000);
      pcmChunks.push(new Float32Array(silenceSamples));
      cursorMs += paraDurationMs > 0 ? para.pauseMs : 0;
    }

    processedChars += Math.max(1, para.text.length);
    const synthElapsedMs = Math.max(1, Date.now() - synthStartedAt);
    const remainingChars = Math.max(0, totalAllChars - processedChars);
    const etaMs = remainingChars > 0
      ? Math.round((synthElapsedMs / processedChars) * remainingChars) + 1200
      : 1000;
    const percent = Math.min(95, Math.round(8 + (processedChars / Math.max(1, totalAllChars)) * 87));
    const nextIdx = pIdx + 1;

    writeProgress(progressPath, {
      phase: nextIdx < totalParagraphs ? "synthesizing" : "encoding",
      completed: nextIdx,
      total: totalParagraphs,
      percent,
      elapsedMs: Date.now() - startedAt,
      etaMs,
      message: nextIdx < totalParagraphs
        ? `Paragraf ${nextIdx + 1} / ${totalParagraphs} seslendiriliyor...`
        : "Ses dosyası (M4A) hazırlanıyor...",
    });
  }

  writeProgress(progressPath, {
    phase: "encoding",
    completed: totalParagraphs,
    total: totalParagraphs,
    percent: 97,
    elapsedMs: Date.now() - startedAt,
    etaMs: 1000,
    message: "M4A formatına dönüştürülüyor...",
  });

  const wavBuffer = encodeWavFromFloat32(pcmChunks, SAMPLE_RATE);
  fs.writeFileSync(outWavPath, wavBuffer);

  if (outMetaPath) {
    fs.writeFileSync(
      outMetaPath,
      JSON.stringify({ durationMs: cursorMs, segments }),
      "utf8"
    );
  }

  console.log(JSON.stringify({ ok: true, durationMs: cursorMs, segments: segments.length }));
}

main().catch((err) => {
  console.error(err?.message || String(err));
  process.exit(1);
});
