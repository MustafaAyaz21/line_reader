#!/usr/bin/env python3
"""
Line Reader — OpenSubtitles & Tatoeba Ön-İşleme Betiği

En yaygın ~25.000-30.000 İngilizce kelime için:
1) Paralel korpustaki gerçek kullanım sıklığına göre sıralı Türkçe anlam adayları,
2) Farklı bağlamları kapsayan 3'er adet temiz, doğal film/dizi/kitap alıntısı (EN + TR + source)
üretir ve Cloudflare D1'e toplu aktarım için parçalı `.sql` dosyaları çıkarır.

Kullanım:
    python build_lexicon_corpus.py
    python build_lexicon_corpus.py --max-words 25000 --batch-size 400
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent.parent
RAW_DIR = BASE_DIR / "raw"
OUT_DIR = BASE_DIR / "out"
SQL_DIR = OUT_DIR / "d1_batches"
LEXICON_CORE_PATH = PROJECT_ROOT / "assets" / "lexicon_core.json.gz"

WORD_RE = re.compile(r"\b[a-z]{2,20}\b")
TR_WORD_RE = re.compile(r"[a-zçğıöşü]{2,24}")
STAGE_NOTE_RE = re.compile(r"(\[[^\]]*\]|\([^)]*\)|♪|<[^>]*>)")
BAD_CHARS_RE = re.compile(r"(http|www\.|@|#|\d{2}:\d{2}|-->)")

# Küfür / argo / altyazı gürültü filtresi
PROFANITY_WORDS = {
    "fuck", "fucking", "fucked", "fucker", "shit", "bullshit", "bitch", "asshole",
    "bastard", "dick", "cock", "pussy", "cunt", "whore", "slut", "motherfucker",
    "damn", "goddamn", "crap", "piss", "nigger", "faggot",
}

EN_STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "if", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "as", "is", "are", "was", "were", "be", "been",
    "am", "it", "its", "this", "that", "these", "those", "he", "she", "they",
    "we", "you", "i", "me", "him", "her", "us", "them", "my", "your", "his",
    "our", "their", "what", "which", "who", "whom", "whose", "when", "where",
    "why", "how", "not", "no", "yes", "so", "do", "does", "did", "will", "would",
    "can", "could", "should", "may", "might", "must", "shall", "have", "has", "had",
}

TR_STOPWORDS = {
    "bir", "ve", "bu", "da", "de", "ile", "için", "ama", "fakat", "ancak",
    "ben", "sen", "o", "biz", "siz", "onlar", "beni", "seni", "onu", "bizi",
    "bana", "sana", "ona", "bize", "size", "benim", "senin", "onun", "bizim",
    "sizin", "onların", "ne", "neden", "niçin", "nasıl", "nerede", "kim",
    "mi", "mı", "mu", "mü", "var", "yok", "evet", "hayır", "çok", "daha",
    "en", "gibi", "kadar", "olarak", "olan", "oldu", "olur", "değil", "şey",
    "şu", "oğlum", "kızım", "baba", "anne", "efendim", "lütfen", "tamam",
    "şimdi", "burada", "orada", "zaten", "belki", "sadece", "bile", "ise",
    "diye", "ki", "ya", "veya", "hem", "her", "hiç", "böyle", "şöyle",
}


def clean_sentence(text: str) -> str:
    text = STAGE_NOTE_RE.sub(" ", text)
    text = text.replace('""', '"').strip()
    if text.startswith("- "):
        text = text[2:].strip()
    text = re.sub(r"\s+", " ", text).strip()
    return text


def is_quality_pair(en: str, tr: str) -> bool:
    if not en or not tr:
        return False
    if BAD_CHARS_RE.search(en) or BAD_CHARS_RE.search(tr):
        return False
    if en.count('"') % 2 != 0:
        return False
    if en.startswith(("...", "-", "*")):
        return False

    en_words = en.split()
    tr_words = tr.split()
    if not (7 <= len(en_words) <= 22):
        return False
    if not (3 <= len(tr_words) <= 24):
        return False
    if not (30 <= len(en) <= 180):
        return False
    if not en[0].isalpha() or not en[0].isupper():
        return False
    if en[-1] not in ".!?":
        return False

    lower_en = en.lower()
    tokens = WORD_RE.findall(lower_en)
    if len(tokens) < 6:
        return False
    if any(t in PROFANITY_WORDS for t in tokens):
        return False

    # Çok fazla büyük harf / bağırma / özel karakter engeli
    upper_count = sum(1 for ch in en if ch.isupper())
    if upper_count > len(en) * 0.25:
        return False

    return True


def score_sentence(en: str, source: str) -> int:
    words = len(en.split())
    score = 100
    if 9 <= words <= 17:
        score += 35
    elif 8 <= words <= 20:
        score += 15
    if source == "tatoeba":
        score += 20  # İnsan çevirisi öncelikli
    if en.endswith("."):
        score += 5
    if "'" not in en and '"' not in en:
        score += 5
    return score


def load_core_lexicon_words() -> set[str]:
    if not LEXICON_CORE_PATH.exists():
        return set()
    try:
        with gzip.open(LEXICON_CORE_PATH, "rb") as f:
            data = json.loads(f.read().decode("utf-8"))
        return {k.strip().lower() for k in data.keys() if re.fullmatch(r"[a-z]{2,20}", k.strip().lower())}
    except Exception as exc:
        print(f"[Uyarı] lexicon_core.json.gz okunamadı: {exc}")
        return set()


def iter_corpus_pairs(max_subtitle_lines: int) -> tuple[list[tuple[str, str, str]], Counter]:
    """
    Tatoeba ve OpenSubtitles cümle çiftlerini okuyup kaliteli olanları döndürür.
    """
    pairs: list[tuple[str, str, str]] = []
    word_freq: Counter = Counter()
    seen_en: set[str] = set()

    tatoeba_path = RAW_DIR / "tatoeba" / "tatoeba_eng_tur.tsv"
    if tatoeba_path.exists():
        print(f"[Korpus] Tatoeba okunuyor: {tatoeba_path}")
        with open(tatoeba_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 2:
                    continue
                en = clean_sentence(parts[0])
                tr = clean_sentence(parts[1])
                if not is_quality_pair(en, tr):
                    continue
                key = en.lower()
                if key in seen_en:
                    continue
                seen_en.add(key)
                pairs.append((en, tr, "tatoeba"))
                for tok in set(WORD_RE.findall(key)):
                    word_freq[tok] += 1
        print(f"  Tatoeba'dan {len(pairs):,} kaliteli cümle alındı.")

    os_en_path = RAW_DIR / "opensubtitles" / "OpenSubtitles.en-tr.en"
    os_tr_path = RAW_DIR / "opensubtitles" / "OpenSubtitles.en-tr.tr"
    if os_en_path.exists() and os_tr_path.exists():
        print(f"[Korpus] OpenSubtitles okunuyor (en fazla {max_subtitle_lines:,} satır taranacak)...")
        added_subs = 0
        with open(os_en_path, "r", encoding="utf-8", errors="replace") as fen, \
                open(os_tr_path, "r", encoding="utf-8", errors="replace") as ftr:
            for idx, (raw_en, raw_tr) in enumerate(zip(fen, ftr), start=1):
                if idx > max_subtitle_lines:
                    break
                en = clean_sentence(raw_en)
                tr = clean_sentence(raw_tr)
                if not is_quality_pair(en, tr):
                    continue
                key = en.lower()
                if key in seen_en:
                    continue
                seen_en.add(key)
                pairs.append((en, tr, "subtitle"))
                added_subs += 1
                for tok in set(WORD_RE.findall(key)):
                    word_freq[tok] += 1
        print(f"  OpenSubtitles'dan {added_subs:,} kaliteli film/dizi alıntısı alındı.")

    return pairs, word_freq


def tr_content_tokens(tr_sentence: str) -> list[str]:
    lowered = tr_sentence.replace("İ", "i").replace("I", "ı").lower()
    return [t for t in TR_WORD_RE.findall(lowered) if t not in TR_STOPWORDS and len(t) >= 3]


def pick_diverse_examples(
    candidates: list[tuple[int, str, str, str]],
    limit: int = 3,
) -> list[dict[str, str]]:
    """
    Puanı yüksek ve Türkçe bağlamı (anlamı) birbirinden farklı 3 alıntı seçer.
    Örn: 'book' için bir cümlede 'kitap', diğerinde 'rezervasyon' geçiyorsa ikisini de alır.
    """
    candidates.sort(key=lambda item: item[0], reverse=True)
    selected: list[dict[str, str]] = []
    used_tr_roots: set[str] = set()

    # 1. Geçiş: Bağlam çeşitliliği öncelikli (farklı Türkçe kökler içeren cümleler)
    for _, en, tr, source in candidates:
        roots = {tok[:5] for tok in tr_content_tokens(tr)}
        if not selected or len(roots - used_tr_roots) >= 2:
            selected.append({"english": en, "turkish": tr, "source": source})
            used_tr_roots.update(roots)
            if len(selected) >= limit:
                return selected

    # 2. Geçiş: Hâlâ 3'e ulaşmadıysa kalan en yüksek puanlılarla tamamla
    selected_en = {item["english"].lower() for item in selected}
    for _, en, tr, source in candidates:
        if en.lower() in selected_en:
            continue
        selected.append({"english": en, "turkish": tr, "source": source})
        selected_en.add(en.lower())
        if len(selected) >= limit:
            break

    return selected


def infer_ranked_meanings(
    word_tr_counter: Counter,
    global_tr_freq: Counter,
    total_pairs: int,
    word_count_in_corpus: int,
    max_meanings: int = 10,
) -> list[str]:
    """
    Basit PMI + frekans skoruyla hedef kelimeyle en sık eşleşen Türkçe kelimeleri sıralar.
    """
    if word_count_in_corpus < 3 or total_pairs == 0:
        return []

    scored: list[tuple[float, str]] = []
    seen_roots: set[str] = set()
    for tr_tok, co_count in word_tr_counter.most_common(60):
        if co_count < 2:
            continue
        g_freq = global_tr_freq.get(tr_tok, 1)
        # PMI benzeri ağırlık: (co_count / word_count) * log(total_pairs / g_freq)
        pmi = math.log2((co_count * total_pairs) / (word_count_in_corpus * g_freq) + 1.0)
        score = co_count * max(pmi, 0.2)
        root = tr_tok[:5]
        if root in seen_roots:
            continue
        seen_roots.add(root)
        scored.append((score, tr_tok))

    scored.sort(key=lambda x: x[0], reverse=True)
    return [tok for _, tok in scored[:max_meanings]]


def sql_escape(val: str) -> str:
    return "'" + val.replace("'", "''") + "'"


def write_d1_batches(rows: list[tuple[str, list[str], list[dict[str, str]], int]], batch_size: int) -> int:
    SQL_DIR.mkdir(parents=True, exist_ok=True)
    for old in SQL_DIR.glob("batch_*.sql"):
        old.unlink()

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    total_files = 0
    for i in range(0, len(rows), batch_size):
        chunk = rows[i : i + batch_size]
        total_files += 1
        out_path = SQL_DIR / f"batch_{total_files:04d}.sql"
        values_sql = []
        for word, meanings, examples, rank in chunk:
            m_json = json.dumps(meanings, ensure_ascii=False)
            e_json = json.dumps(examples, ensure_ascii=False)
            values_sql.append(
                f"({sql_escape(word)}, {sql_escape(m_json)}, {sql_escape(e_json)}, {rank}, {sql_escape(now_iso)})"
            )

        stmt = (
            "INSERT INTO corpus_lexicon (word, meanings_json, examples_json, freq_rank, updated_at)\n"
            "VALUES\n  "
            + ",\n  ".join(values_sql)
            + "\nON CONFLICT(word) DO UPDATE SET\n"
            "  meanings_json = excluded.meanings_json,\n"
            "  examples_json = excluded.examples_json,\n"
            "  freq_rank = excluded.freq_rank,\n"
            "  updated_at = excluded.updated_at;\n"
        )
        out_path.write_text(stmt, encoding="utf-8")

    return total_files


def main() -> int:
    parser = argparse.ArgumentParser(description="Line Reader Korpus Ön-İşleme")
    parser.add_argument("--max-words", type=int, default=25000, help="Hedef kelime sayısı (varsayılan: 25000)")
    parser.add_argument("--max-subtitle-lines", type=int, default=2500000, help="Taranacak maksimum altyazı satırı")
    parser.add_argument("--batch-size", type=int, default=350, help="Her SQL dosyasındaki satır sayısı")
    args = parser.parse_args()

    pairs, word_freq = iter_corpus_pairs(max_subtitle_lines=args.max_subtitle_lines)
    if not pairs:
        print("[Hata] İşlenecek korpus bulunamadı! Önce `python download_corpora.py` çalıştırın.")
        return 1

    core_words = load_core_lexicon_words()
    print(f"[Kelime Havuzu] Çekirdek sözlük: {len(core_words):,} kelime")

    # En sık geçen kelimeleri + çekirdek kelimeleri birleştir
    ranked_words = [
        w for w, _ in word_freq.most_common(args.max_words * 2)
        if w not in EN_STOPWORDS and w not in PROFANITY_WORDS and len(w) >= 2
    ]
    target_set: list[str] = []
    seen_targets: set[str] = set()
    for w in list(core_words) + ranked_words:
        if w not in seen_targets and w not in PROFANITY_WORDS:
            seen_targets.add(w)
            target_set.append(w)
        if len(target_set) >= args.max_words:
            break

    target_lookup = set(target_set)
    print(f"[Hedef] {len(target_lookup):,} İngilizce kelime için alıntı ve frekans indeksi kuruluyor...")

    word_candidates: dict[str, list[tuple[int, str, str, str]]] = defaultdict(list)
    word_tr_co: dict[str, Counter] = defaultdict(Counter)
    global_tr_freq: Counter = Counter()

    for en, tr, source in pairs:
        tr_toks = set(tr_content_tokens(tr))
        for t in tr_toks:
            global_tr_freq[t] += 1

        en_toks = set(WORD_RE.findall(en.lower()))
        base_score = score_sentence(en, source)
        for w in en_toks:
            if w not in target_lookup:
                continue
            bucket = word_candidates[w]
            # Bellek kontrolü: her kelime için en fazla 30 aday tut
            if len(bucket) < 30:
                bucket.append((base_score, en, tr, source))
            for t in tr_toks:
                word_tr_co[w][t] += 1

    # Frekans sırasına göre çıktı satırlarını hazırla
    ordered_targets = sorted(target_lookup, key=lambda w: word_freq.get(w, 0), reverse=True)
    rows: list[tuple[str, list[str], list[dict[str, str]], int]] = []
    total_pairs = len(pairs)

    for rank, word in enumerate(ordered_targets, start=1):
        cands = word_candidates.get(word)
        if not cands:
            continue
        examples = pick_diverse_examples(cands, limit=3)
        if not examples:
            continue
        meanings = infer_ranked_meanings(
            word_tr_co[word],
            global_tr_freq,
            total_pairs,
            word_freq.get(word, len(cands)),
        )
        rows.append((word, meanings, examples, rank))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    batch_count = write_d1_batches(rows, batch_size=args.batch_size)

    summary = {
        "total_corpus_pairs": total_pairs,
        "indexed_words": len(rows),
        "sql_batch_files": batch_count,
        "sample_preview": {
            w: {"meanings": m, "examples": ex}
            for w, m, ex, _ in rows[:5]
        },
    }
    (OUT_DIR / "corpus_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"\n[Tamamlandı]")
    print(f"  İndekslenen kelime sayısı : {len(rows):,}")
    print(f"  Üretilen D1 SQL dosyası   : {batch_count} adet ({SQL_DIR})")
    print(f"  Özet dosya                : {OUT_DIR / 'corpus_summary.json'}")
    print("\nSıradaki adım (Cloudflare D1'e yükleme):")
    print("  .\\upload_to_d1.ps1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
