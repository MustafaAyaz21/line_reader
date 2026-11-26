import fs from "node:fs";
import { EdgeTTS } from "node-edge-tts";

async function main() {
  const args = process.argv.slice(2);
  const inputJsonPath = args[0];
  const outMp3Path = args[1];
  const outMetaPath = args[2];

  if (!inputJsonPath || !outMp3Path) {
    console.error("Usage: node edge_tts.mjs <input.json> <out.mp3> [out.meta.json]");
    process.exit(1);
  }

  const input = JSON.parse(fs.readFileSync(inputJsonPath, "utf8"));
  const voice = input.voice || "en-US-AndrewMultilingualNeural";
  const text = String(input.text || "").trim();

  if (!text) {
    console.error("Bos metin.");
    process.exit(1);
  }

  const tts = new EdgeTTS({
    voice,
    lang: voice.startsWith("en-GB") ? "en-GB" : "en-US",
    outputFormat: "audio-24khz-96kbitrate-mono-mp3",
    saveSubtitles: true,
    rate: "-3%",
  });

  await tts.ttsPromise(text, outMp3Path);

  const subPath = `${outMp3Path}.json`;
  const wordBoundaries = [];
  if (fs.existsSync(subPath)) {
    try {
      const subs = JSON.parse(fs.readFileSync(subPath, "utf8"));
      if (Array.isArray(subs)) {
        for (const item of subs) {
          wordBoundaries.push({
            text: item.part || "",
            offsetMs: Math.round(item.start || 0),
            durationMs: Math.max(40, Math.round((item.end || 0) - (item.start || 0))),
          });
        }
      }
      fs.unlinkSync(subPath);
    } catch (_) {}
  }

  if (outMetaPath) {
    fs.writeFileSync(outMetaPath, JSON.stringify({ wordBoundaries }), "utf8");
  }

  const size = fs.existsSync(outMp3Path) ? fs.statSync(outMp3Path).size : 0;
  console.log(JSON.stringify({ ok: true, bytes: size, words: wordBoundaries.length }));
}

main().catch((err) => {
  console.error(err?.message || String(err));
  process.exit(1);
});
