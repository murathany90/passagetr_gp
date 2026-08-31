# PASSAGETR

Public, backend-free Flutter Web project for word and reading practice.

## Content

Tracked production source data is kept once, under `source_data`:

- `canonical/words/yds_words_set_001.csv`
- `canonical/readings/reading_passages.csv` and `reading_sentences.csv`
- `canonical/dictionary/dictionary_tr_en.xlsx`
- `curated/readings_001_100_curated_v2.json`
- `mappings/word_pack_reclassification_v1.json`
- `legacy/legacy_reading_questions_v1.json`
- `baselines/readings_101_678_baseline_v1.json`

`assets/content/v1` is an ignored, reproducible Flutter asset bundle. Build it
from the tracked source data before testing or building the app:

```powershell
python tools/build_static_content.py
python tools/validate_static_content.py
```

For readings 001--100, the builder preserves the curated bilingual titles,
sentences, summaries, questions, answers, and explanations without editing
them. For readings 101--678, it deterministically derives study metadata from
the tracked source passages and sentences, including extractive summaries,
focus-word links, and cloze questions. Missing source translations remain
empty; the builder does not infer translations or author new curated content.

`_local_source_archive/` is deliberately ignored and is never part of a Pages
build or GitHub push.

## Run and build

```powershell
flutter pub get
flutter run -d chrome
flutter build web --release --base-href "/passagetr_gp/"
```

Flutter's default hash URL strategy is intentionally retained. The live routes
are `#/words` and `#/readings`, which work on GitHub Pages without a server
rewrite rule.
