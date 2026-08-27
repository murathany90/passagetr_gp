# PASSAGETR İlk 100 Reading Curated Bilingual Pack v2

100 reading; her reading 15 EN cümle + cümle bazlı TR çeviri; toplam 1.500 çift. Her reading 5 passage-specific çift dilli soru; toplam 500 soru. `items/001.json` ... `items/100.json` agent tarafından tek tek değiştirilebilir.

## Kritik legacy soru politikası
Yerel orijinal repoda bulunan gerçek/eski soru-cevaplar bu paket tarafından silinmemelidir. Agent önce bunları export edip `source_data/legacy_reading_questions.*` altında korumalıdır. Bu paket `curated_v2`/supplemental kaynak olarak eklenmeli; otomatik cloze soru üretimi kapatılmalıdır.

## Import
`source_number` ile mevcut reading UUID'sini eşleştir; UUID değiştirme. Runtime statik kalmalı.
