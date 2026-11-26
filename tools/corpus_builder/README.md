# Line Reader — OpenSubtitles & Tatoeba Korpus Hazırlama Aracı

Bu araç, **OPUS OpenSubtitles (en-tr)** film/dizi altyazıları ve **Tatoeba (eng-tur)** insan çevirisi cümlelerini işleyip en yaygın ~25.000 İngilizce kelime için:
- Bağlamsal çeşitliliğe sahip 3'er doğal alıntı (EN + TR + kaynak etiketi),
- Gerçek kullanım sıklığına göre sıralı Türkçe anlam adayları

üretir ve Cloudflare D1 (`linereader-db`) veri tabanına yükler.

## Kullanım Adımları (PowerShell)

1. **Veri setlerini indir:**
   ```powershell
   cd tools\corpus_builder
   node download_corpora.mjs
   ```
   *(İsterseniz sadece birini indirmek için `--only tatoeba` veya `--only opensubtitles` kullanabilirsiniz.)*

2. **Ön-işleme betiğini çalıştır:**
   ```powershell
   node build_lexicon_corpus.mjs
   ```
   Çıktılar `out\d1_batches\batch_*.sql` ve `out\corpus_summary.json` içine yazılır.

3. **Cloudflare D1'e yükle:**
   ```powershell
   .\upload_to_d1.ps1
   ```
   *(Yarıda kesilirse kaldığınız parçadan devam etmek için: `.\upload_to_d1.ps1 -StartBatch 12`)*
