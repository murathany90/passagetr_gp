# PASSAGETR

Public, backend-free Flutter Web project for word and reading practice.

## Content

`assets/content/v1` is the only production data source. It is generated from
the audited public inputs in `source_data`:

```powershell
python tools/build_static_content.py
python tools/validate_static_content.py
```

The builder never creates summaries, questions, focus words, translations, or
cover data that are missing from the source.

## Run and build

```powershell
flutter pub get
flutter run -d chrome
flutter build web --release --base-href "/passagetr_gp/"
```

Flutter's default hash URL strategy is intentionally retained. The live routes
are `#/words` and `#/readings`, which work on GitHub Pages without a server
rewrite rule.
