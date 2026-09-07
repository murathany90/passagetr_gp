# PASSAGETR GP

PASSAGETR GP; Kelime, Okuma, Çalışma, Testler ve Sözlük modüllerini sunan tamamen public bir
Flutter Web uygulamasıdır. GitHub Pages üzerinde çalışır; backend, API,
kullanıcı girişi, auth ve runtime database içermez.

## Veri Özeti

- Kelime: 9.000 benzersiz headword
- Reading: 800
- Canonical EN/TR cümle: 7.500
- Reading sorusu: 4.000 (her reading için 5 comprehension sorusu)
- Sözlük kaydı / benzersiz headword: 121.772 / 121.501

## Canonical Kaynaklar

| Path | Format | İçerik | Kayıt | Ana alanlar | Kullanım |
| --- | --- | --- | ---: | --- | --- |
| `source_data/canonical/words/passagetr_yds_words_canonical_9000_FINAL_v2.csv` | CSV | Tek kelime kaynağı | 9.000 | `en_word`, `tr_meaning`, `pos`, EN/TR örnek, synonym/antonym, `level`, `tags_raw` (`technology & it` biçiminde), `notes` | Kelime, flashcard, mini-test, eşleştirme ve focus-word adayları |
| `source_data/canonical/readings/PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx` | XLSX | Tek reading kaynağı | 800 reading / 7.500 cümle / 4.000 soru | `Readings` (`reading_no`, `title_en`, `title_tr`, `level`, `category`, `tags_raw`), `Sentences` (`reading_no`, `sentence_no`, `sentence_en`, `sentence_tr`), `Questions` (5 tip, A–D şıklar, `correct_option`, `evidence_sentence_no`) | Reading index, body, sorular, başlıklar |
| `source_data/mappings/reading_legacy_ids_001_678.json` | JSON | Eski başlık-tabanlı passage ID → yeni `reading_no` eşlemesi | 678 | eski ID → `001`–`678` | Tek seferlik okuma-ilerleme migration’ı |
| `source_data/canonical/dictionary/dictionary_tr_en.xlsx` | XLSX | Geniş EN→TR sözlük | 121.783 kaynak satırı | `en_word`, `pos`, `tr_meaning_clean` | Lazy shard sözlük indeksi |
| `source_data/canonical/study/PASSAGETR_YDS_Study_Canonical_v2_Module_01-30.xlsx` | XLSX | Çalışma modüllerinin tek canonical kaynağı | 30 modül | 10 ilişkili worksheet; modül, hedef kelime, cümle, reading, soru, çeviri, yapı ve review alanları | Yalnız `tools/build_study_content.py` tarafından 30 manifest/modül JSON’una dönüştürülür |
| `source_data/canonical/tests/passagetr_test_bank.xlsx` | XLSX | Testler modülünün tek canonical kaynağı | 110 modül / 2.200 kelime satırı / 480 yapı / 9 test / 450 soru | `words`, `phrasal_prepositions`, `vocabulary_tests` worksheet’leri | Yalnız `tools/build_test_content.py` tarafından bundled JSON’a dönüştürülür |

Kelime için tek authoritative kaynak ilk CSV’dir ve kayıt sayısı 9.000’dir.
Önceki word CSV kaldırılmıştır; production’da kullanılmaz.

Reading body ve sorular yalnız `PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx`
ile üretilir. Eski passage/sentence CSV’leri, soru snapshot JSON’u ve curated
001–100 paketi repodan kaldırılmıştır; üretim akışında JSON
correction/repair/overlay katmanı yoktur. Reading ID’ler başlıktan değil
`reading_no` (`reading | 001` … `reading | 800`) üzerinden türetilir; başlıklar
`001 - English Title (Türkçe Başlık)` formatında gösterilir. Level
yalnız A1/A2/B1/B2/C1/C2 olabilir (kelime ve reading için).

## Generated Content

`assets/content/v1` Git’te tutulmaz. `tools/build_static_content.py` bu dizini
canonical kaynaklardan üretir. `tools/validate_static_content.py`; 9.000
benzersiz kelimeyi, 800 reading/7.500 EN-TR cümle/4.000 soruyu, tek-kaynak
body ve soru eşitliğini, A1–C2 level standardını ve eski kelime-kaynak
referansının kalmadığını doğrular.

`assets/content/study` de Git’te tutulmaz. `tools/build_study_content.py`,
canonical Excel'i çalışma manifesti ve modül JSON'larına dönüştürür;
`tools/validate_study_content.py` worksheet şemasını, ilişki bütünlüğünü,
30 modülün tamamını; modül başına 15 hedef kelime, 5 cümle, reading soruları,
EN→TR/TR→EN çeviriler, test ve review sözleşmesini doğrular. Flutter Web
runtime Excel okumaz; yalnız bundled JSON yükler.

`assets/content/tests` Git’te tutulmaz. `tools/build_test_content.py`, Test
Bank XLSX’ini 110 modül, yapı ve 9 özgün test JSON assetine dönüştürür. Test
sorusu, İngilizce şık ve doğru cevap yalnız bu XLSX’ten gelir. Generated
`option_tr` alanı salt-okunur olarak sırasıyla Test Bank kelimeleri, 9.000
canonical kelime bankası ve canonical sözlükten zenginleştirilir; bulunamayan
karşılıklar validator tarafından raporlanır ancak build’i bloklamaz.

`_local_source_archive/` varsa yalnız yerel inceleme arşividir, Git tarafından
ignore edilir ve Pages build’ine dahil edilmez.

## Rotalar

- `#/words`
- `#/words/matching`
- `#/words/find-word`
- `#/readings`
- `#/study`
- `#/study/module/:moduleId`
- `#/tests`
- `#/tests/module/:moduleNo`
- `#/tests/structures`
- `#/tests/exams`
- `#/dictionary`

Hash routing, GitHub Pages’te server rewrite gerektirmez.

## Build ve Deploy

```powershell
flutter pub get
python tools/build_static_content.py
python tools/build_study_content.py
python tools/build_test_content.py
python tools/validate_static_content.py
python tools/validate_study_content.py
python tools/validate_test_content.py
flutter analyze
flutter test
flutter build web --release --base-href "/passagetr_gp/"
git push origin main
```

`main` push’u GitHub Actions ile canonical içeriği yeniden üretir ve Pages
deploy’unu tetikler.
