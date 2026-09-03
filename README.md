# PASSAGETR GP

PASSAGETR GP; Kelime, Okuma ve Sözlük modüllerini sunan tamamen public bir
Flutter Web uygulamasıdır. GitHub Pages üzerinde çalışır; backend, API,
kullanıcı girişi, auth ve runtime database içermez.

## Veri Özeti

- Kelime: 7.500 benzersiz headword
- Reading: 678
- Canonical EN/TR cümle: 6.275
- Sözlük kaydı / benzersiz headword: 121.772 / 121.501
- Curated 001–100: 500 comprehension sorusu
- 101–678 soru snapshot’ı: 1.634 vocabulary-practice sorusu

## Canonical Kaynaklar

| Path | Format | İçerik | Kayıt | Ana alanlar | Kullanım |
| --- | --- | --- | ---: | --- | --- |
| `source_data/canonical/words/passagetr_yds_words_canonical_7500_FINAL.csv` | CSV | Tek kelime kaynağı | 7.500 | `en_word`, `tr_meaning`, `pos`, EN/TR örnek, synonym/antonym, `level`, `tags_raw`, `notes` | Kelime, flashcard, mini-test ve focus-word adayları |
| `source_data/canonical/readings/reading_passages.csv` | CSV | Passage metadata ve gösterim başlıkları | 678 | `pack_name`, `title`, `level`, `tags_raw`, `Category`, `display_title_en`, `display_title_tr` | Reading index, filtre ve başlıklar |
| `source_data/canonical/readings/reading_sentences.csv` | CSV | Tek authoritative reading body | 6.275 | `passage_title`, `idx`, `sentence_en`, `sentence_tr` | Uygulamadaki bütün EN/TR reading cümleleri |
| `source_data/canonical/readings/reading_questions_v1.json` | JSON | Korunan 101–678 vocabulary-practice soru snapshot’ı | 578 reading | `sourceNumber`, `readingId`, `questions` | Soru içeriği; reading body override değildir |
| `source_data/canonical/dictionary/dictionary_tr_en.xlsx` | XLSX | Geniş EN→TR sözlük | 121.783 kaynak satırı | `en_word`, `pos`, `tr_meaning_clean` | Lazy shard sözlük indeksi |
| `source_data/curated/readings_001_100_curated_v2.json` | JSON | 001–100 curated özet/metadata/comprehension soruları | 100 | `source_number`, `summary_en`, `summary_tr`, `questions` | Curated soru ve özet kaynağı; EN/TR body override değildir |

Kelime için tek authoritative kaynak ilk CSV’dir ve kayıt sayısı 7.500’dür.
Önceki word CSV kaldırılmıştır; production’da kullanılmaz.

Reading body yalnız `reading_passages.csv` + `reading_sentences.csv` ile
üretilir. Eski JSON correction/repair/overlay katmanları üretim akışında yoktur;
nihai EN/TR cümleler doğrudan canonical sentence CSV’ye yazılmıştır.

## Generated Content

`assets/content/v1` Git’te tutulmaz. `tools/build_static_content.py` bu dizini
canonical kaynaklardan üretir. `tools/validate_static_content.py`; 7.500
benzersiz kelimeyi, 678 reading/6.275 EN-TR cümleyi, tek-kaynak body eşitliğini,
soru kaynaklarını ve eski kelime-kaynak referansının kalmadığını doğrular.

`_local_source_archive/` varsa yalnız yerel inceleme arşividir, Git tarafından
ignore edilir ve Pages build’ine dahil edilmez.

## Rotalar

- `#/words`
- `#/readings`
- `#/dictionary`

Hash routing, GitHub Pages’te server rewrite gerektirmez.

## Build ve Deploy

```powershell
flutter pub get
python tools/build_static_content.py
python tools/validate_static_content.py
flutter analyze
flutter test
flutter build web --release --base-href "/passagetr_gp/"
git push origin main
```

`main` push’u GitHub Actions ile canonical içeriği yeniden üretir ve Pages
deploy’unu tetikler.
