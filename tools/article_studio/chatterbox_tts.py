import json
import os
import re
import sys
import time
import wave

os.environ["TQDM_DISABLE"] = "1"

import numpy as np
from scipy import signal
import torch


def write_progress(progress_path, data):
    if not progress_path:
        return
    try:
        tmp = f"{progress_path}.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, progress_path)
    except Exception:
        try:
            with open(progress_path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False)
        except Exception:
            pass


def sanitize_text(raw):
    s = str(raw or "")
    s = s.replace("\u2018", "'").replace("\u2019", "'")
    s = s.replace("\u201C", '"').replace("\u201D", '"')
    s = s.replace("\u2013", ", ").replace("\u2014", ", ")
    s = s.replace("\u2026", "...")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def split_chunks(content, max_chars=190):
    raw_paragraphs = [
        sanitize_text(p)
        for p in re.split(r"\n{2,}", str(content or "").replace("\r\n", "\n"))
    ]
    raw_paragraphs = [p for p in raw_paragraphs if re.search(r"[A-Za-z0-9]", p)]

    chunks = []
    for p_idx, p_text in enumerate(raw_paragraphs):
        raw_sents = re.findall(r"[^.!?]+(?:[.!?]+[\"'’)\]]*|$)", p_text) or [p_text]
        sents = [s.strip() for s in raw_sents if re.search(r"[A-Za-z0-9]", s)]
        if not sents:
            continue

        cur_sents = []
        cur_len = 0
        for s_idx, s in enumerate(sents):
            if cur_sents and (cur_len + len(s) + 1 > max_chars):
                chunks.append({
                    "text": " ".join(cur_sents),
                    "sentences": list(cur_sents),
                    "pause_ms": 340,
                })
                cur_sents = [s]
                cur_len = len(s)
            else:
                cur_sents.append(s)
                cur_len += len(s) + 1

        if cur_sents:
            is_last_para = (p_idx == len(raw_paragraphs) - 1)
            chunks.append({
                "text": " ".join(cur_sents),
                "sentences": list(cur_sents),
                "pause_ms": 220 if is_last_para else 580,
            })

    return chunks


def master_podcast_audio(samples, sr):
    """Boğukluğu gideren dengeli stüdyo podcast EQ (75 Hz HPF + 300 Hz -2.2 dB çamur temizliği + 4.5 kHz +1.5 dB yumuşak parlaklık)."""
    if len(samples) < 64:
        return samples
    audio = samples.astype(np.float64)
    nyq = 0.5 * float(sr)

    # 1) 75 Hz altı uğultu temizliği
    sos_hp = signal.butter(2, 75.0 / nyq, btype="highpass", output="sos")
    audio = signal.sosfilt(sos_hp, audio)

    # 2) 300 Hz boğukluk / çamur bandını hafifçe temizle (-2.2 dB peaking EQ, Q=1.2)
    cut_db = -2.2
    fc_mud = 300.0
    q_mud = 1.2
    a_mud = 10.0 ** (cut_db / 40.0)
    w0_m = 2.0 * np.pi * fc_mud / float(sr)
    alpha_m = np.sin(w0_m) / (2.0 * q_mud)
    cos_m = np.cos(w0_m)

    bm0 = 1.0 + alpha_m * a_mud
    bm1 = -2.0 * cos_m
    bm2 = 1.0 - alpha_m * a_mud
    am0 = 1.0 + alpha_m / a_mud
    am1 = -2.0 * cos_m
    am2 = 1.0 - alpha_m / a_mud
    audio = signal.lfilter(
        np.array([bm0, bm1, bm2]) / am0,
        np.array([1.0, am1 / am0, am2 / am0]),
        audio,
    )

    # 3) 4500 Hz üstü yumuşak stüdyo parlaklığı (+1.5 dB, tizleştirmeden netlik)
    gain_db = 1.5
    fc = 4500.0
    a = 10.0 ** (gain_db / 40.0)
    w0 = 2.0 * np.pi * fc / float(sr)
    cos_w0 = np.cos(w0)
    sin_w0 = np.sin(w0)
    alpha = sin_w0 / np.sqrt(2.0)
    sqrt_a = np.sqrt(a)

    b0 = a * ((a + 1.0) + (a - 1.0) * cos_w0 + 2.0 * sqrt_a * alpha)
    b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w0)
    b2 = a * ((a + 1.0) + (a - 1.0) * cos_w0 - 2.0 * sqrt_a * alpha)
    a0 = (a + 1.0) - (a - 1.0) * cos_w0 + 2.0 * sqrt_a * alpha
    a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cos_w0)
    a2 = (a + 1.0) - (a - 1.0) * cos_w0 - 2.0 * sqrt_a * alpha

    audio = signal.lfilter(
        np.array([b0, b1, b2]) / a0,
        np.array([1.0, a1 / a0, a2 / a0]),
        audio,
    )

    # 4) Temiz stüdyo seviye normalizasyonu (-0.9 dB peak)
    peak = float(np.max(np.abs(audio)))
    if peak > 1e-6:
        audio = audio * (0.90 / peak)

    return audio.astype(np.float32)


def save_wav_16bit(path, float_samples, sample_rate):
    mastered = master_podcast_audio(float_samples, sample_rate)
    clipped = np.clip(mastered, -1.0, 1.0)
    int16_data = (clipped * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(sample_rate))
        wf.writeframes(int16_data.tobytes())


def main():
    if len(sys.argv) < 3:
        print("Usage: python chatterbox_tts.py <input.json> <out.wav> [out.meta.json] [progress.json]", file=sys.stderr)
        sys.exit(1)

    in_json = sys.argv[1]
    out_wav = sys.argv[2]
    out_meta = sys.argv[3] if len(sys.argv) > 3 else None
    progress_path = sys.argv[4] if len(sys.argv) > 4 else None

    started_at = time.time()
    with open(in_json, "r", encoding="utf-8-sig") as f:
        payload = json.load(f)

    text = str(payload.get("text") or "").strip()
    preset = str(payload.get("voice") or "expressive").strip().lower()
    if not text:
        print("Bos metin.", file=sys.stderr)
        sys.exit(1)

    chunks = split_chunks(text)
    total_chunks = len(chunks)
    total_chars = sum(max(1, len(c["text"])) for c in chunks)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    gpu_label = torch.cuda.get_device_name(0) if device == "cuda" else "CPU"

    write_progress(progress_path, {
        "phase": "loading_model",
        "completed": 0,
        "total": total_chunks,
        "percent": 5,
        "elapsedMs": int((time.time() - started_at) * 1000),
        "etaMs": None,
        "message": f"Chatterbox modeli yükleniyor ({gpu_label})...",
    })

    from chatterbox.tts import ChatterboxTTS
    model = ChatterboxTTS.from_pretrained(device=device)
    sr = int(model.sr)

    # Preset parametreleri (yavaş, sakin, doğal nefesli ve vurgulu okuma dengesi)
    exaggeration = 0.42
    cfg_weight = 0.30
    audio_prompt_path = None

    if preset == "calm":
        exaggeration = 0.28
        cfg_weight = 0.35
    elif preset == "natural":
        exaggeration = 0.38
        cfg_weight = 0.32
    elif preset == "expressive":
        exaggeration = 0.46
        cfg_weight = 0.28
    elif preset == "custom":
        studio_dir = os.path.dirname(os.path.abspath(__file__))
        voices_dir = os.path.join(studio_dir, "voices")
        for fname in ("custom.wav", "custom.mp3", "custom.m4a"):
            candidate = os.path.join(voices_dir, fname)
            if os.path.exists(candidate):
                audio_prompt_path = candidate
                break
        exaggeration = 0.48
        cfg_weight = 0.50

    synth_started = time.time()
    write_progress(progress_path, {
        "phase": "synthesizing",
        "completed": 0,
        "total": total_chunks,
        "percent": 10,
        "elapsedMs": int((time.time() - started_at) * 1000),
        "etaMs": None,
        "message": f"Bölüm 1 / {total_chunks} seslendiriliyor ({gpu_label})...",
    })

    audio_parts = []
    segments = []
    cursor_ms = 0
    processed_chars = 0

    for idx, chunk in enumerate(chunks):
        kwargs = {
            "exaggeration": exaggeration,
            "cfg_weight": cfg_weight,
        }
        if audio_prompt_path:
            kwargs["audio_prompt_path"] = audio_prompt_path

        wav_tensor = model.generate(chunk["text"], **kwargs)
        samples = wav_tensor.squeeze().detach().cpu().numpy().astype(np.float32)
        chunk_duration_ms = int(round((len(samples) * 1000.0) / sr))

        s_total_chars = sum(max(1, len(s)) for s in chunk["sentences"])
        local_cursor = cursor_ms
        for s_i, s_text in enumerate(chunk["sentences"]):
            is_last = (s_i == len(chunk["sentences"]) - 1)
            share = int(round((chunk_duration_ms * max(1, len(s_text))) / s_total_chars))
            end_ms = (cursor_ms + chunk_duration_ms) if is_last else (local_cursor + share)
            segments.append({
                "text": s_text,
                "start_ms": local_cursor,
                "end_ms": max(local_cursor + 250, end_ms),
            })
            local_cursor = end_ms

        audio_parts.append(samples)
        cursor_ms += chunk_duration_ms

        pause_ms = int(chunk["pause_ms"])
        if pause_ms > 0:
            silence = np.zeros(int(round(sr * pause_ms / 1000.0)), dtype=np.float32)
            audio_parts.append(silence)
            cursor_ms += pause_ms

        processed_chars += max(1, len(chunk["text"]))
        synth_elapsed_ms = max(1, int((time.time() - synth_started) * 1000))
        remaining_chars = max(0, total_chars - processed_chars)
        eta_ms = int(round((synth_elapsed_ms / processed_chars) * remaining_chars)) + 1000 if remaining_chars > 0 else 800
        percent = min(96, int(round(10 + (processed_chars / max(1, total_chars)) * 86)))
        done_count = idx + 1

        write_progress(progress_path, {
            "phase": "synthesizing" if done_count < total_chunks else "encoding",
            "completed": done_count,
            "total": total_chunks,
            "percent": percent,
            "elapsedMs": int((time.time() - started_at) * 1000),
            "etaMs": eta_ms,
            "message": f"Bölüm {done_count + 1} / {total_chunks} seslendiriliyor ({gpu_label})..."
            if done_count < total_chunks
            else "Ses dosyası (M4A) hazırlanıyor...",
        })

    full_audio = np.concatenate(audio_parts) if audio_parts else np.zeros(sr, dtype=np.float32)
    save_wav_16bit(out_wav, full_audio, sr)

    if out_meta:
        with open(out_meta, "w", encoding="utf-8") as f:
            json.dump({"durationMs": cursor_ms, "sampleRate": sr, "segments": segments}, f, ensure_ascii=False)

    print(json.dumps({"ok": True, "device": device, "durationMs": cursor_ms, "segments": len(segments)}))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        if len(sys.argv) > 4 and sys.argv[4]:
            write_progress(sys.argv[4], {"phase": "error", "error": str(exc), "message": str(exc)})
        print(str(exc), file=sys.stderr)
        sys.exit(1)
