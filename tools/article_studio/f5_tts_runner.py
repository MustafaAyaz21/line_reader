import json
import os
import re
import sys
import time
import wave

os.environ["TQDM_DISABLE"] = "1"

import numpy as np
from scipy import signal
import soundfile as sf
import torch
import torchaudio


def _sf_torchaudio_load(filepath, frame_offset=0, num_frames=-1, *args, **kwargs):
    start = int(frame_offset) if frame_offset else 0
    stop = (start + int(num_frames)) if (num_frames is not None and int(num_frames) > 0) else None
    data, sr = sf.read(str(filepath), start=start, stop=stop, dtype="float32", always_2d=True)
    return torch.from_numpy(data.T.copy()), int(sr)


def _sf_torchaudio_save(filepath, src, sample_rate, *args, **kwargs):
    arr = src.detach().cpu().float().numpy()
    if arr.ndim == 2:
        arr = arr.T
    sf.write(str(filepath), arr, int(sample_rate))


torchaudio.load = _sf_torchaudio_load
torchaudio.save = _sf_torchaudio_save


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


def split_chunks(content, max_chars=240):
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
        for s in sents:
            if cur_sents and (cur_len + len(s) + 1 > max_chars):
                chunks.append({
                    "text": " ".join(cur_sents),
                    "sentences": list(cur_sents),
                    "pause_ms": 300,
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
                "pause_ms": 220 if is_last_para else 540,
            })

    return chunks


def master_podcast_audio(samples, sr):
    if len(samples) < 64:
        return samples
    audio = samples.astype(np.float64)
    nyq = 0.5 * float(sr)

    sos_hp = signal.butter(2, 70.0 / nyq, btype="highpass", output="sos")
    audio = signal.sosfilt(sos_hp, audio)

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


def transcribe_wav_without_ffmpeg(wav_path, device):
    """ffmpeg olmadan soundfile/wave ile numpy array okuyup önbellekteki Whisper ile metni çıkarır."""
    import soundfile as sf
    from transformers import pipeline

    audio, sr = sf.read(wav_path, dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != 16000:
        num_samples = int(round(len(audio) * 16000.0 / float(sr)))
        audio = signal.resample(audio, num_samples).astype(np.float32)
        sr = 16000

    asr = pipeline(
        "automatic-speech-recognition",
        model="openai/whisper-large-v3-turbo",
        device=0 if device == "cuda" else -1,
    )
    out = asr({"raw": audio, "sampling_rate": sr})
    return str(out.get("text") or "").strip()


def find_reference_voice(device="cuda"):
    studio_dir = os.path.dirname(os.path.abspath(__file__))
    voices_dir = os.path.join(studio_dir, "voices")
    ref_audio = None
    for fname in ("custom.wav", "custom.mp3", "custom.m4a"):
        candidate = os.path.join(voices_dir, fname)
        if os.path.exists(candidate):
            ref_audio = candidate
            break
    ref_text = ""
    txt_candidate = os.path.join(voices_dir, "custom.txt")
    if os.path.exists(txt_candidate):
        try:
            with open(txt_candidate, "r", encoding="utf-8") as f:
                ref_text = f.read().strip()
        except Exception:
            pass

    if ref_audio and not ref_text and ref_audio.lower().endswith(".wav"):
        try:
            ref_text = transcribe_wav_without_ffmpeg(ref_audio, device)
            if ref_text:
                with open(txt_candidate, "w", encoding="utf-8") as f:
                    f.write(ref_text)
        except Exception:
            pass
    return ref_audio, ref_text


def main():
    if len(sys.argv) < 3:
        print("Usage: python f5_tts_runner.py <input.json> <out.wav> [out.meta.json] [progress.json]", file=sys.stderr)
        sys.exit(1)

    in_json = sys.argv[1]
    out_wav = sys.argv[2]
    out_meta = sys.argv[3] if len(sys.argv) > 3 else None
    progress_path = sys.argv[4] if len(sys.argv) > 4 else None

    started_at = time.time()
    with open(in_json, "r", encoding="utf-8-sig") as f:
        payload = json.load(f)

    text = str(payload.get("text") or "").strip()
    preset = str(payload.get("voice") or "normal").strip().lower()
    if not text:
        print("Bos metin.", file=sys.stderr)
        sys.exit(1)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    gpu_label = torch.cuda.get_device_name(0) if device == "cuda" else "CPU"

    ref_audio, ref_text = find_reference_voice(device)
    if not ref_audio:
        raise RuntimeError("F5-TTS klonlama icin tools\\article_studio\\voices\\custom.wav (veya custom.mp3) dosyasi gerekli.")

    chunks = split_chunks(text)
    total_chunks = len(chunks)
    total_chars = sum(max(1, len(c["text"])) for c in chunks)

    write_progress(progress_path, {
        "phase": "loading_model",
        "completed": 0,
        "total": total_chunks,
        "percent": 5,
        "elapsedMs": int((time.time() - started_at) * 1000),
        "etaMs": None,
        "message": f"F5-TTS Diffusion modeli yükleniyor ({gpu_label})...",
    })

    from f5_tts.api import F5TTS
    f5tts = F5TTS(device=device)

    speed = 0.92 if preset == "calm" else 0.98
    synth_started = time.time()

    write_progress(progress_path, {
        "phase": "synthesizing",
        "completed": 0,
        "total": total_chunks,
        "percent": 10,
        "elapsedMs": int((time.time() - started_at) * 1000),
        "etaMs": None,
        "message": f"Bölüm 1 / {total_chunks} F5-TTS ile seslendiriliyor ({gpu_label})...",
    })

    audio_parts = []
    segments = []
    cursor_ms = 0
    processed_chars = 0
    sample_rate = 24000

    for idx, chunk in enumerate(chunks):
        wav, sr, _ = f5tts.infer(
            ref_file=ref_audio,
            ref_text=ref_text,
            gen_text=chunk["text"],
            speed=speed,
        )
        sample_rate = int(sr)
        samples = np.asarray(wav, dtype=np.float32).reshape(-1)
        chunk_duration_ms = int(round((len(samples) * 1000.0) / sample_rate))

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
            silence = np.zeros(int(round(sample_rate * pause_ms / 1000.0)), dtype=np.float32)
            audio_parts.append(silence)
            cursor_ms += pause_ms

        processed_chars += max(1, len(chunk["text"]))
        synth_elapsed_ms = max(1, int((time.time() - synth_started) * 1000))
        remaining_chars = max(0, total_chars - processed_chars)
        eta_ms = int(round((synth_elapsed_ms / processed_chars) * remaining_chars)) + 800 if remaining_chars > 0 else 600
        percent = min(96, int(round(10 + (processed_chars / max(1, total_chars)) * 86)))
        done_count = idx + 1

        write_progress(progress_path, {
            "phase": "synthesizing" if done_count < total_chunks else "encoding",
            "completed": done_count,
            "total": total_chunks,
            "percent": percent,
            "elapsedMs": int((time.time() - started_at) * 1000),
            "etaMs": eta_ms,
            "message": f"Bölüm {done_count + 1} / {total_chunks} F5-TTS ile seslendiriliyor ({gpu_label})..."
            if done_count < total_chunks
            else "Ses dosyası (M4A) hazırlanıyor...",
        })

    full_audio = np.concatenate(audio_parts) if audio_parts else np.zeros(sample_rate, dtype=np.float32)
    save_wav_16bit(out_wav, full_audio, sample_rate)

    if out_meta:
        with open(out_meta, "w", encoding="utf-8") as f:
            json.dump({"durationMs": cursor_ms, "sampleRate": sample_rate, "segments": segments}, f, ensure_ascii=False)

    print(json.dumps({"ok": True, "device": device, "durationMs": cursor_ms, "segments": len(segments)}))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        if len(sys.argv) > 4 and sys.argv[4]:
            write_progress(sys.argv[4], {"phase": "error", "error": str(exc), "message": str(exc)})
        print(str(exc), file=sys.stderr)
        sys.exit(1)
