#!/usr/bin/env python3
"""
Line Reader — OPUS OpenSubtitles (en-tr) ve Tatoeba (eng-tur) İndirme Betiği

Kullanım:
    python download_corpora.py
    python download_corpora.py --only tatoeba
    python download_corpora.py --only opensubtitles --force
"""

from __future__ import annotations

import argparse
import bz2
import csv
import gzip
import os
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
RAW_DIR = BASE_DIR / "raw"

OPENSUBTITLES_URLS = [
    "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2024/moses/en-tr.txt.zip",
    "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/moses/en-tr.txt.zip",
]

TATOEBA_ENG_URL = "https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2"
TATOEBA_TUR_URL = "https://downloads.tatoeba.org/exports/per_language/tur/tur_sentences.tsv.bz2"
TATOEBA_LINKS_URL = "https://downloads.tatoeba.org/exports/links.csv.bz2"


def download_file(url: str, dest: Path, force: bool = False) -> bool:
    if dest.exists() and dest.stat().st_size > 0 and not force:
        print(f"[Atlandı] Zaten mevcut: {dest.name}")
        return True

    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = dest.with_suffix(dest.suffix + ".part")
    print(f"[İndiriliyor] {url} -> {dest.name}")

    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "LineReader-CorpusBuilder/1.0"},
        )
        with urllib.request.urlopen(req, timeout=60) as resp, open(tmp_path, "wb") as out:
            total = int(resp.headers.get("Content-Length") or 0)
            downloaded = 0
            chunk_size = 1024 * 256
            while True:
                chunk = resp.read(chunk_size)
                if not chunk:
                    break
                out.write(chunk)
                downloaded += len(chunk)
                if total > 0:
                    pct = downloaded * 100 / total
                    mb = downloaded / (1024 * 1024)
                    total_mb = total / (1024 * 1024)
                    print(f"\r  {mb:.1f} / {total_mb:.1f} MB ({pct:.1f}%)", end="", flush=True)
        print()
        shutil.move(str(tmp_path), str(dest))
        return True
    except Exception as exc:
        print(f"\n[Hata] {url} indirilemedi: {exc}")
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)
        return False


def prepare_opensubtitles(force: bool = False) -> None:
    os_dir = RAW_DIR / "opensubtitles"
    os_dir.mkdir(parents=True, exist_ok=True)
    en_out = os_dir / "OpenSubtitles.en-tr.en"
    tr_out = os_dir / "OpenSubtitles.en-tr.tr"

    if en_out.exists() and tr_out.exists() and not force:
        print("[OpenSubtitles] Paralel metin dosyaları zaten hazır.")
        return

    zip_path = os_dir / "en-tr.txt.zip"
    downloaded = False
    for url in OPENSUBTITLES_URLS:
        if download_file(url, zip_path, force=force):
            downloaded = True
            break

    if not downloaded:
        print("[OpenSubtitles] İndirme başarısız. Manuel olarak en-tr.txt.zip indirip raw/opensubtitles/ içine koyabilirsiniz.")
        return

    print("[OpenSubtitles] Zip arşivi açılıyor...")
    with zipfile.ZipFile(zip_path, "r") as zf:
        for member in zf.namelist():
            if member.endswith(".en") or member.endswith(".tr"):
                target_name = "OpenSubtitles.en-tr.en" if member.endswith(".en") else "OpenSubtitles.en-tr.tr"
                target_path = os_dir / target_name
                with zf.open(member) as src, open(target_path, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                print(f"  Çıkarıldı: {target_name}")


def prepare_tatoeba(force: bool = False) -> None:
    tat_dir = RAW_DIR / "tatoeba"
    tat_dir.mkdir(parents=True, exist_ok=True)
    tsv_out = tat_dir / "tatoeba_eng_tur.tsv"

    if tsv_out.exists() and tsv_out.stat().st_size > 0 and not force:
        print("[Tatoeba] tatoeba_eng_tur.tsv zaten hazır.")
        return

    eng_bz2 = tat_dir / "eng_sentences.tsv.bz2"
    tur_bz2 = tat_dir / "tur_sentences.tsv.bz2"
    links_bz2 = tat_dir / "links.csv.bz2"

    ok1 = download_file(TATOEBA_ENG_URL, eng_bz2, force=force)
    ok2 = download_file(TATOEBA_TUR_URL, tur_bz2, force=force)
    ok3 = download_file(TATOEBA_LINKS_URL, links_bz2, force=force)
    if not (ok1 and ok2 and ok3):
        print("[Tatoeba] Gerekli dosyalar indirilemedi.")
        return

    print("[Tatoeba] İngilizce cümleler okunuyor...")
    eng_map: dict[str, str] = {}
    with bz2.open(eng_bz2, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3:
                eng_map[parts[0]] = parts[2].strip()

    print(f"  {len(eng_map):,} İngilizce cümle yüklendi. Türkçe cümleler okunuyor...")
    tur_map: dict[str, str] = {}
    with bz2.open(tur_bz2, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3:
                tur_map[parts[0]] = parts[2].strip()

    print(f"  {len(tur_map):,} Türkçe cümle yüklendi. Bağlantılar eşleştiriliyor...")
    count = 0
    with bz2.open(links_bz2, "rt", encoding="utf-8", errors="replace") as lf, \
            open(tsv_out, "w", encoding="utf-8", newline="") as out:
        writer = csv.writer(out, delimiter="\t")
        for line in lf:
            parts = line.strip().split("\t")
            if len(parts) < 2:
                continue
            sid, tid = parts[0], parts[1]
            en_text = eng_map.get(sid)
            if not en_text:
                continue
            tr_text = tur_map.get(tid)
            if not tr_text:
                continue
            writer.writerow([en_text, tr_text])
            count += 1

    print(f"[Tatoeba] Tamamlandı: {count:,} paralel EN-TR cümle -> {tsv_out}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Line Reader Korpus İndirici")
    parser.add_argument(
        "--only",
        choices=["all", "opensubtitles", "tatoeba"],
        default="all",
        help="Yalnızca belirtilen veri setini indir.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Mevcut dosyaları yeniden indir ve oluştur.",
    )
    args = parser.parse_args()

    if args.only in ("all", "tatoeba"):
        prepare_tatoeba(force=args.force)
    if args.only in ("all", "opensubtitles"):
        prepare_opensubtitles(force=args.force)

    print("\nİndirme/hazırlama işlemi tamamlandı. Sıradaki adım:")
    print("  python build_lexicon_corpus.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
