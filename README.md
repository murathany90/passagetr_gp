# PASSAGETR GP

Tamamen public Flutter Web uygulaması. GitHub Pages üzerinde Kelime, Okuma ve
Sözlük modüllerini sunar. Backend, API, kullanıcı girişi, auth ve runtime
database yoktur; production verisi bundled statik JSON’dan okunur.

## Veri Özeti

Builder ve validator’ın güncel çıktıları:

- Words: 5.314
- Readings: 678
- Generated sentences: 6.243
- Dictionary entries / unique headwords: 121.772 / 121.501
- Curated 001–100: 1.500 cümle, 500 comprehension sorusu
- Derived 101–678: 1.634 vocabulary-practice cloze sorusu

## Source Data

| Path | Format | İçerik | Yaklaşık kayıt | Ana alanlar | Kullanım |
| --- | --- | --- | ---: | --- | --- |
| `source_data/canonical/words/yds_words_set_001.csv` | CSV | İngilizce kelime çalışması | 5.314 | `en_word`, `tr_meaning`, `pos`, `example_en`, `example_tr`, `synonyms_raw`, `antonyms_raw`, `level`, `tags_raw`, `notes` | Kelime, flashcard, mini test ve focus-word adayları |
| `source_data/canonical/readings/reading_passages.csv` | CSV | Okuma üst bilgisi | 678 | `pack_name`, `title`, `level`, `tags_raw`, `Category` | Reading index ve filtreler |
| `source_data/canonical/readings/reading_sentences.csv` | CSV | Canonical reading–cümle ilişkisi | 5.242 | `passage_title`, `idx`, `sentence_en`, `sentence_tr` | Builder’ın temel reading girdisi |
| `source_data/canonical/dictionary/dictionary_tr_en.xlsx` | XLSX | Geniş EN→TR sözlük | 121.783 satır / 121.772 kayıt | `en_word`, `pos`, `tr_meaning_clean` | Lazy shard sözlük indeksi |
| `source_data/curated/readings_001_100_curated_v2.json` | JSON | İlk 100 immutable bilingual reading | 100 | `source_number`, 15 EN/TR cümle, başlıklar, özetler, soru/cevap/açıklama | 001–100 source-of-truth |
| `source_data/quality/reading_translation_repairs_v1.json` | JSON | Eksik canonical TR için kaynak-bağlı overlay | 0 repair | `sourceNumber`, `readingId`, `sentenceIndex`, EN/TR metin, neden | Canonical CSV’yi değiştirmeden çeviri onarımı |
| `source_data/quality/reading_content_repairs_v1.json` | JSON | Critical-short reading’ler için append-only bilingual overlay | 2 reading / 11 cümle | `sourceNumber`, `readingId`, neden, `appendSentences` | Kaynak cümleleri koruyarak kontrollü genişletme |
| `source_data/quality/reading_content_repairs_101_300_v2.json` | JSON | 101–300 için quality-safe append-only bilingual overlay | 52 reading / 108 cümle | `sourceNumber`, `readingId`, neden, `appendSentences` | Production authoritative overlay; şablon/canonical tekrar içermez |
| `source_data/legacy/reading_content_repairs_101_300_v1_template_history.json` | JSON | Önceki template ağırlıklı repair geçmişi | 102 reading / 422 cümle | v1 append kayıtları | Production’da kullanılmaz; v2 editoryal audit karşılaştırması için tutulur |
| `source_data/mappings/word_pack_reclassification_v1.json` | JSON | Kelime paket eşlemesi | 5.314 | `word_id`, `target_pack_name`, eşleme nedeni | Kelime paketleri |
| `source_data/baselines/readings_101_678_source_baseline_v2.json` | JSON | Canonical 101–678 kaynak bütünlüğü | 578 | kayıt/cümle sayısı, canonical EN/TR proje SHA-256 | Derived metadata değişirken canonical kaynak değişikliğini yakalar |
| `source_data/legacy/pre_curated_generated_questions_backup_v1.json` | JSON | Curated öncesi generated soru yedeği | 100 reading / 282 soru | `sourceNumber`, soru, seçenekler, cevap | Audit/backup; orijinal legacy soru bankası değildir |

Builder, curated 001–100 başlık/cümle/özet/sorularını değiştirmez. 101–678’de
üretilen cloze’lar `vocabulary_practice` olarak sınıflanır; gerçek Okuduğunu
Anlama sorusu diye sunulmaz. Derived ilk iki cümle de `extractive` olarak
etiketlenir; UI’da “Metinden Kısa Bölüm” başlığını alır.

## Reading Quality

`source_data/reports/reading_translation_audit_v1.json` ve
`source_data/reports/reading_length_audit_v1.json` builder tarafından
deterministik üretilen denetim kayıtlarıdır.

- TR kapsamı: 6.243 / 6.243 cümle (%100); translation repair: 0
- Critical short: 404 önce, 54 kontrollü repair, 350 kalan
- Curated 001–100 sabit kalır; quality overlay’ler yalnız 101–678 içindir.
- Kalan critical-short kayıtlar otomatik metin uydurmamak için audit’te açıkça
  işaretlenir; sonraki editoryal aşamada kaynakla birlikte ele alınmalıdır.

## Yerel Kaynak Arşivi

`_local_source_archive/` Git tarafından ignore edilir ve Pages build’ine dahil
edilmez. `original_passagetr_v0/archive_manifest.csv`, eski çalışma kopyasından
yerelde kopyalanan benzersiz veriyi `original_path`, `new_path`, `sha256` ve
`purpose` alanlarıyla kaydetmek içindir. Son taramada production source ile aynı
hash’e sahip CSV/XLSX/JSON’lar tekrar kopyalanmamış; manifest dışında benzersiz
veri kaynağı bulunmamıştır.

## Generated Content

`assets/content/v1` Git’te tutulmaz. `tools/build_static_content.py` bu dizini
canonical + curated + quality overlay kaynaklarından üretir. CI, analyze/test/
web build’den önce üretimi çalıştırır; `tools/validate_static_content.py` hem
çıktıyı hem source baseline ve quality audit sözleşmelerini doğrular.

## Routes

- `#/words`
- `#/readings`
- `#/dictionary`

Hash routing GitHub Pages’de server rewrite gerektirmez.

## Build / Deploy

```powershell
flutter pub get
python tools/build_static_content.py
python tools/validate_static_content.py
flutter analyze
flutter test
flutter build web --release --base-href "/passagetr_gp/"
git push origin main
```

`main` push’u GitHub Actions ile static content üretimini ve Pages deploy’unu
tetikler.
