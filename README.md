# PASSAGETR GP

Tamamen public Flutter Web uygulaması: GitHub Pages üzerinde Kelime, Okuma ve
Sözlük çalışır. Backend, API, kullanıcı girişi, auth veya runtime database
yoktur. Uygulama tüm production içeriğini build sırasında üretilen bundled
JSON dosyalarından okur.

## Veri Özeti

`python tools/build_static_content.py` ve validator çıktısındaki gerçek
sayılar:

- Words: 5.314
- Readings: 678
- Sentences: 6.124
- Dictionary entries / unique headwords: 121.772 / 121.501
- Curated readings 001–100: 1.500 cümle, 500 soru

## Source Data

| Path | Format | İçerik | Yaklaşık kayıt | Ana alanlar | Kullanım |
| --- | --- | --- | ---: | --- | --- |
| `source_data/canonical/words/yds_words_set_001.csv` | CSV | İngilizce kelime çalışması | 5.314 | `en_word`, `tr_meaning`, `pos`, `example_en`, `example_tr`, synonym, antonym, level, tags, notes | Kelime listesi, flashcard ve mini test |
| `source_data/canonical/readings/reading_passages.csv` | CSV | Okuma üst bilgisi | 678 | `pack_name`, `title`, `level`, `tags_raw`, `Category` | Reading index ve filtreler |
| `source_data/canonical/readings/reading_sentences.csv` | CSV | Reading–cümle ilişkisi | 6.124 | `passage_title`, `idx`, `sentence_en`, `sentence_tr` | Reading detail, TR görünüm, TTS |
| `source_data/canonical/dictionary/dictionary_tr_en.xlsx` | XLSX | Geniş EN→TR sözlük | 121.783 satır / 121.772 kayıt | `en_word`, `pos`, `tr_meaning_clean` | Shard edilmiş sözlük araması |
| `source_data/curated/readings_001_100_curated_v2.json` | JSON | İlk 100 bilingual curated reading | 100 | başlıklar, 15 cümle, EN/TR özet, soru/cevap/açıklama | 001–100 source-of-truth |
| `source_data/mappings/word_pack_reclassification_v1.json` | JSON | Kelime paket eşlemesi | 5.314 | `word_id`, `target_pack_name`, eşleme nedeni | Kelime paketleri |
| `source_data/baselines/readings_101_678_baseline_v1.json` | JSON | 101–678 değişmezlik kontrolü | 578 | `sourceNumber`, `readingId`, dosya, SHA-256 | Validator baseline’ı |
| `source_data/legacy/pre_curated_generated_questions_backup_v1.json` | JSON | Curated öncesi generated soru yedeği | 100 reading / 282 soru | `sourceNumber`, soru, seçenekler, cevap | Sadece audit/backup; orijinal legacy soru bankası değildir |

Builder, curated 001–100 paketindeki başlık, cümle, özet ve soruları
değiştirmez. 101–678 için kaynak CSV’lerden deterministik çalışma metadatası
üretir; eksik çeviri uydurmaz.

## Yerel Kaynak Arşivi

`_local_source_archive/` Git tarafından ignore edilir ve Pages build’ine dahil
edilmez. `original_passagetr_v0/archive_manifest.csv`, eski çalışma kopyasından
yerelde kopyalanan benzersiz veriyi `original_path`, `new_path`, `sha256` ve
`purpose` alanlarıyla kaydetmek içindir.

Mevcut taramada Kelime/Okuma/Sözlük için uygun CSV, XLSX ve JSON kaynakları
production source ile aynı hash’e sahipti; bu yüzden tekrar kopyalanmadı.
Yerel manifest dışında ek benzersiz veri kaynağı bulunmadı.

## Generated Content

`assets/content/v1` Git’te tutulmaz. `tools/build_static_content.py` tarafından
üretilir; CI, analyze/test/web build’den önce bu adımı yeniden çalıştırır.

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

`main` push’u, GitHub Actions ile static content üretimini ve Pages deploy’unu
tetikler.
