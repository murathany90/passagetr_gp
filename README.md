# PASSAGETR GP

PASSAGETR GP, İngilizce/YDS çalışmaları için geliştirilen **tamamen public ve statik bir Flutter Web uygulamasıdır**. Uygulama; **Kelime, Okuma, Çalışma, Testler ve Sözlük** modüllerini tek arayüzde sunar.

Production çalışma modeli özellikle basit tutulmuştur:

- backend yok
- harici runtime API yok
- kullanıcı girişi / auth yok
- runtime database yok
- production içerik canonical kaynaklardan build aşamasında üretilir
- Flutter Web runtime yalnız paketlenmiş statik JSON assetlerini kullanır
- yayın GitHub Actions üzerinden GitHub Pages'e yapılır

## Canlı Uygulama

**Production:**  
https://gridfreq.online

**GitHub repository:**  
https://github.com/murathany90/passagetr_gp

Hosting altyapısı GitHub Pages'tir. Repository bir GitHub Pages **custom domain** ile çalışır ve production Flutter build'i kök dizin için:

```text
--base-href "/"
```

değeriyle oluşturulur.

> `gridfreq.online` aktif production adresidir. Custom domain kullanıldığı sürece GitHub Pages workflow'undaki base href değeri `/` olarak korunmalıdır.

---

## Proje Özeti

| Alan | Mevcut durum |
| --- | ---: |
| Kelime bankası | **9.000 benzersiz headword** |
| Reading | **800** |
| Canonical EN/TR cümle çifti | **7.500** |
| Reading comprehension sorusu | **4.000** |
| Reading başına soru | **5** |
| Sözlük kaydı | **121.772** |
| Benzersiz sözlük headword | **121.501** |
| Study modülü | **30** |
| Test modülü | **150** |
| Test bankası kelime satırı | **3.000** |
| Phrasal / preposition yapı | **480** |
| Özgün test | **9** |
| Özgün test sorusu | **450** |

---

## Temel Tasarım İlkeleri

PASSAGETR veri katmanında mümkün olduğunca **tek authoritative canonical kaynak** yaklaşımını kullanır.

Ana ilkeler:

1. Her ana veri grubu için tek canonical kaynak tutulur.
2. Runtime için kullanılan JSON dosyaları canonical kaynaklardan yeniden üretilebilir.
3. Generated content doğrudan elle düzenlenmez.
4. Eski correction / repair / overlay katmanları production akışında kullanılmaz.
5. Flutter Web runtime Excel veya CSV okumaz; build sırasında üretilen bundled JSON'ları okur.
6. Veri doğrulama işlemleri deployment öncesinde otomatik çalışır.
7. Hash routing sayesinde GitHub Pages üzerinde server-side rewrite gereksinimi yoktur.
8. Production deployment yalnız `main` branch üzerinden GitHub Actions ile yapılır.

---

# Modüller

## 1. Kelime

Kelime modülü 9.000 benzersiz İngilizce headword üzerinden çalışır.

Canonical word kaynağı:

```text
source_data/canonical/words/passagetr_yds_words_canonical_9000_FINAL_v2.csv
```

Temel alanlar:

- `en_word`
- `tr_meaning`
- `pos`
- İngilizce örnek
- Türkçe örnek
- synonym
- antonym
- `level`
- `tags_raw`
- `notes`

Kelime verileri aşağıdaki özelliklerde kullanılır:

- kelime listesi
- arama
- kelime detayları
- flashcards
- mini-test
- matching
- find-word
- focus-word adayları

Desteklenen level değerleri:

```text
A1
A2
B1
B2
C1
C2
```

Canonical word kaydı **9.000** satırdır ve production word bank için başka bir eski CSV kullanılmaz.

---

## 2. Reading

Reading modülünün tek canonical kaynağı:

```text
source_data/canonical/readings/PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx
```

Workbook üç temel veri grubunu taşır:

### Readings

Başlıca alanlar:

- `reading_no`
- `title_en`
- `title_tr`
- `level`
- `category`
- `tags_raw`

### Sentences

Başlıca alanlar:

- `reading_no`
- `sentence_no`
- `sentence_en`
- `sentence_tr`

### Questions

Her reading için 5 comprehension sorusu bulunur.

Başlıca alanlar:

- soru tipi
- soru metni
- A–D seçenekleri
- `correct_option`
- `evidence_sentence_no`

Toplam:

```text
800 reading
7.500 EN/TR cümle çifti
4.000 soru
```

Reading body ve soruları yalnız bu canonical workbook'tan üretilir.

Eski:

- passage CSV'leri
- sentence CSV'leri
- soru snapshot JSON'ları
- curated 001–100 paketleri
- JSON correction / repair / overlay katmanları

production akışında kullanılmaz.

Reading kimliği başlıktan türetilmez. Kimlik `reading_no` üzerinden oluşturulur.

Örnek:

```text
reading | 001
...
reading | 800
```

Başlık gösterim biçimi:

```text
001 - English Title (Türkçe Başlık)
```

### Legacy Reading Migration

Eski 001–678 ilerleme kayıtlarının yeni `reading_no` sistemine taşınabilmesi için:

```text
source_data/mappings/reading_legacy_ids_001_678.json
```

dosyası kullanılır.

Bu dosya eski başlık-tabanlı passage ID değerlerini yeni reading numaralarıyla eşler.

---

## 3. Study

Study modülünün canonical kaynağı:

```text
source_data/canonical/study/PASSAGETR_YDS_Study_Canonical_v2_Module_01-30.xlsx
```

Toplam:

```text
30 modül
```

Workbook ilişkili worksheet'ler üzerinden aşağıdaki içerikleri taşır:

- hedef kelimeler
- lexical ilişkiler
- cümleler
- reading
- reading soruları
- EN → TR çeviri
- TR → EN çeviri
- YDS yapıları
- test
- review

Generated runtime içerik:

```text
assets/content/study/
```

altında oluşturulur.

Flutter runtime canonical Excel dosyasını doğrudan okumaz.

Build:

```text
tools/build_study_content.py
```

Validator:

```text
tools/validate_study_content.py
```

Validator, 30 modülün bütünlüğünü ve worksheet ilişkilerini kontrol eder. Modül sözleşmesinde özellikle:

- 15 hedef kelime
- 5 cümle
- reading ve soruları
- çeviri bölümleri
- test
- review

kontrol edilir.

---

## 4. Testler

Testler modülünün tek canonical kaynağı:

```text
source_data/canonical/passagetr_test_bank_CANONICAL_v3.xlsx
```

Canonical kapsam:

```text
150 modül
3.000 kelime satırı
480 phrasal/preposition yapı
9 özgün test
450 özgün test sorusu
```

Başlıca worksheet'ler:

- `words`
- `phrasal_prepositions`
- `vocabulary_tests`

Runtime JSON üretimi:

```text
tools/build_test_content.py
```

Doğrulama:

```text
tools/validate_test_content.py
```

Generated `option_tr` alanı salt-okunur zenginleştirme mantığıyla sırasıyla:

1. Test Bank kelimeleri
2. 9.000 canonical kelime bankası
3. canonical sözlük

üzerinden tamamlanır.

Bulunamayan Türkçe seçenek karşılıkları validator tarafından raporlanabilir ancak bu durum tek başına build'i bloklamaz.

Testler modülünde ayrıca:

- modül sayfaları
- modül flashcards (`bildim / toplam` yerel ilerlemesi)
- matching (tamamlanma ve en iyi başarı yüzdesi)
- hızlı test (tamamlanma ve en iyi skor)
- structures (bildim olarak işaretlenen yapı ilerlemesi)
- özgün exams (`answered / total`, son konum ve en iyi skor)
- Test Bank'a özel favoriler: `testFavoriteWordIds`
- wrong answers

akışları bulunur.

> Kelime alanındaki `favoriteWordIds` ile Testler alanındaki
> `testFavoriteWordIds` ayrı SharedPreferences kayıtlarıdır. Bir alandaki
> favori diğer alanda görünmez.

---

## 5. Sözlük

Canonical sözlük kaynağı:

```text
source_data/canonical/dictionary/dictionary_tr_en.xlsx
```

Kaynak workbook yaklaşık:

```text
121.783 kaynak satırı
```

içerir.

Production dictionary çıktısı:

```text
121.772 kayıt
121.501 benzersiz headword
```

Ana alanlar:

- `en_word`
- `pos`
- `tr_meaning_clean`

Sözlük doğrudan tek büyük runtime dosyası olarak kullanılmak yerine lazy shard yaklaşımıyla üretilir.

---

# Canonical Kaynaklar

| Path | Format | İçerik | Kapsam | Production kullanımı |
| --- | --- | --- | --- | --- |
| `source_data/canonical/words/passagetr_yds_words_canonical_9000_FINAL_v2.csv` | CSV | Kelime bankası | 9.000 unique word | Words, flashcards, mini-test, matching, focus-word |
| `source_data/canonical/readings/PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx` | XLSX | Reading canonical | 800 reading / 7.500 cümle / 4.000 soru | Reading index, body, questions |
| `source_data/mappings/reading_legacy_ids_001_678.json` | JSON | Legacy ID migration | 678 mapping | Eski reading progress migration |
| `source_data/canonical/dictionary/dictionary_tr_en.xlsx` | XLSX | EN→TR sözlük | 121.783 kaynak satırı | Dictionary shard üretimi |
| `source_data/canonical/study/PASSAGETR_YDS_Study_Canonical_v2_Module_01-30.xlsx` | XLSX | Study canonical | 30 modül | Study manifest/module JSON |
| `source_data/canonical/passagetr_test_bank_CANONICAL_v3.xlsx` | XLSX | Test canonical V3 | 150 modül / 9 test | Test runtime JSON |

---

# Generated Content

Production runtime içeriği canonical kaynaklardan build sırasında üretilir.

## Static content

Generated dizin:

```text
assets/content/v1/
```

Builder:

```text
tools/build_static_content.py
```

Validator:

```text
tools/validate_static_content.py
```

Validator başlıca aşağıdaki sözleşmeleri kontrol eder:

- 9.000 benzersiz kelime
- 800 reading
- 7.500 EN/TR cümle
- 4.000 reading sorusu
- reading body / soru tek-kaynak eşitliği
- A1–C2 level standardı
- eski word source referanslarının kaldırılmış olması

## Study content

Generated dizin:

```text
assets/content/study/
```

Builder:

```text
tools/build_study_content.py
```

Validator:

```text
tools/validate_study_content.py
```

## Test content

Generated dizin:

```text
assets/content/tests/
```

Builder:

```text
tools/build_test_content.py
```

Validator:

```text
tools/validate_test_content.py
```

## Generated dosyaların Git politikası

Aşağıdaki generated içerikler canonical kaynakların yerine geçmez:

```text
assets/content/v1/
assets/content/study/
assets/content/tests/
```

Canonical veri değiştirilecekse generated JSON üzerinde elle düzeltme yapmak yerine ilgili canonical kaynak düzeltilmeli ve builder yeniden çalıştırılmalıdır.

`_local_source_archive/` mevcutsa yalnız yerel inceleme arşividir; Git tarafından ignore edilir ve GitHub Pages production build'ine dahil edilmez.

---

# Veri Akışı

```text
Canonical CSV / XLSX / JSON
          │
          ▼
tools/build_*.py
          │
          ▼
Generated bundled JSON
assets/content/*
          │
          ▼
Flutter Web runtime
          │
          ▼
GitHub Actions
          │
          ▼
GitHub Pages
          │
          ▼
https://gridfreq.online
```

Runtime mimarisinin önemli özelliği:

> Production istemcisi canonical Excel/CSV dosyalarını doğrudan okumaz.

---

# Rotalar

Uygulama hash-routing kullanır.

## Ana

```text
#/
```

## Words

```text
#/words
#/words/flashcards
#/words/mini-test
#/words/matching
#/words/find-word
```

## Dictionary

```text
#/dictionary
```

## Readings

```text
#/readings
#/readings/:id
```

## Study

```text
#/study
#/study/module/:moduleId
```

## Tests

```text
#/tests
#/tests/module/:moduleNo
#/tests/module/:moduleNo/flashcards
#/tests/module/:moduleNo/matching
#/tests/structures
#/tests/exams
#/tests/exam/:testNo
#/tests/wrong
```

Sayısal test module route'ları `1–150`, özgün exam route'ları `1–9` aralığıyla sınırlandırılır. Geçersiz route parametreleri uygulama crash'i yerine kontrollü hata sayfasına yönlendirilir.

Hash routing kullanılması GitHub Pages tarafında ek server rewrite kuralı gerektirmez.

---

# Teknoloji

Ana runtime bileşenleri:

- Flutter Web
- Dart
- Riverpod
- GoRouter
- Shared Preferences
- Web APIs
- GitHub Actions
- GitHub Pages

Uygulama statik hosting üzerinde çalışacak şekilde tasarlanmıştır.

---

# Repository Yapısı

```text
.github/
  workflows/
    pages.yml

lib/
  app/
  core/
  features/
  models/
  repositories/

source_data/
  canonical/
    words/
    readings/
    dictionary/
    study/
    passagetr_test_bank_CANONICAL_v3.xlsx
  mappings/

tools/

test/

web/
```

- `.github/workflows/pages.yml`: production CI/CD workflow
- `lib/`: Flutter runtime ve UI kodu
- `source_data/`: authoritative canonical kaynaklar ve mappingler
- `tools/`: canonical → generated JSON builder / validator scriptleri
- `test/`: Flutter testleri
- `web/`: Flutter Web platform dosyaları

---

# Yerel Geliştirme

## Gereksinimler

- Flutter stable
- Python 3
- Git
- builder scriptlerinin gerektirdiği Python paketleri

Fresh clone sonrasında generated assetler mevcut değilse önce içerik build edilmelidir.

## İçerik üretimi

```powershell
flutter pub get
python tools/build_static_content.py
python tools/build_study_content.py
python tools/build_test_content.py
```

## Veri doğrulama

```powershell
python tools/validate_static_content.py
python tools/validate_study_content.py
python tools/validate_test_content.py
```

## Flutter kalite kontrolleri

```powershell
flutter analyze
flutter test
```

## Production web build

```powershell
flutter build web --release --base-href "/"
```

Build çıktısı:

```text
build/web/
```

`build/web/index.html` içinde beklenen değer:

```html
<base href="/">
```

---

# CI/CD ve GitHub Pages

Production deployment workflow:

```text
.github/workflows/pages.yml
```

Workflow aşağıdaki durumlarda çalışır:

```text
push → main
workflow_dispatch
```

Pipeline:

```text
Checkout
  ↓
Flutter stable
  ↓
flutter pub get
  ↓
Build static content
  ↓
Build study content
  ↓
Build test content
  ↓
Validate static content
  ↓
Validate study content
  ↓
Validate test content
  ↓
flutter analyze
  ↓
flutter test
  ↓
flutter build web --release --base-href "/"
  ↓
Upload Pages artifact
  ↓
Deploy GitHub Pages
```

Production build sırasında commit bilgisi `APP_BUILD_SHA` olarak Flutter build'e aktarılır.

GitHub Actions build komutu:

```bash
flutter build web --release --base-href "/" --dart-define=APP_BUILD_SHA=${{ github.sha }}
```

---

# Custom Domain

Production custom domain:

```text
gridfreq.online
```

Production URL:

```text
https://gridfreq.online
```

GitHub Pages custom domain aktif olduğundan uygulama root path altında serve edilir. Bu nedenle:

```text
--base-href "/"
```

korunmalıdır.

Aşağıdaki eski project-path build ayarı production custom domain için kullanılmamalıdır:

```text
--base-href "/passagetr_gp/"
```

Custom domain aktifken bu değere geri dönülmesi Flutter JS, asset ve JSON yollarının bozulmasına neden olabilir.

---

# Deployment Öncesi Kontrol Listesi

Canonical veya uygulama değişikliklerinden sonra:

```text
[ ] build_static_content.py PASS
[ ] build_study_content.py PASS
[ ] build_test_content.py PASS

[ ] validate_static_content.py PASS
[ ] validate_study_content.py PASS
[ ] validate_test_content.py PASS

[ ] flutter analyze PASS
[ ] flutter test PASS

[ ] Flutter production build PASS
[ ] <base href="/"> doğrulandı
```

Deployment sonrası:

```text
[ ] https://gridfreq.online HTTP 200
[ ] Flutter bootstrap yükleniyor
[ ] main.dart.js yükleniyor
[ ] static manifest JSON yükleniyor
[ ] study manifest JSON yükleniyor
[ ] test manifest JSON yükleniyor
[ ] asset / JSON 404 yok
[ ] ana navigation çalışıyor
```

---

# Veri Kalitesi Sözleşmeleri

## Words

```text
9.000 kayıt
9.000 benzersiz headword sözleşmesi
A1–C2 level
```

## Readings

```text
800 reading
7.500 EN/TR sentence pair
4.000 question
5 question / reading
```

## Study

```text
30 module
canonical worksheet ilişkileri
modül hedef kelime / sentence / reading / translation / test / review sözleşmesi
```

## Tests

```text
150 module
3.000 word row
480 structure
9 original test
450 question
```

Generated içerikte görülen bir veri problemi için doğru düzeltme katmanı canonical kaynaktır.

---

# Runtime Veri Yükleme

Flutter uygulaması runtime'da bundled assetleri kullanır.

Örnek static root:

```text
assets/content/v1
```

Ana manifest ve ilgili index dosyaları runtime repository katmanı tarafından yüklenir. Study ve Test içerikleri de kendi manifest / module JSON yapılarını kullanır.

Bu tasarım sayesinde:

- backend bağımlılığı bulunmaz
- database migration gerektirmez
- hosting yalnız statik dosya sunabilir
- canonical kaynaklar runtime'a doğrudan açılmaz
- deploy çıktısı yeniden üretilebilir

---

# Privacy ve Kullanıcı Verisi

Uygulama:

- kullanıcı hesabı istemez
- login istemez
- authentication servisi kullanmaz
- server-side profile database kullanmaz

Runtime ilerleme ve kullanıcı tercihleri server database yerine istemci tarafındaki yerel storage mekanizmalarıyla yönetilir.

---

# Hata Ayıklama

## Uygulama açılış ekranında kalıyorsa

Öncelikle generated içeriklerin eksik olmadığını kontrol edin:

```powershell
python tools/build_static_content.py
python tools/build_study_content.py
python tools/build_test_content.py
```

Ardından validatorları çalıştırın. Browser DevTools → Network altında JSON isteklerinin `200` döndüğünü kontrol edin.

Bir JSON isteği HTML/404 dönüyorsa genellikle asset yolu veya eksik generated content problemi vardır.

## Asset / JSON 404 varsa

Custom domain için:

```text
<base href="/">
```

olmalıdır. Workflow içindeki `--base-href "/"` korunmalıdır.

## Validator count hatası varsa

Generated JSON'u elle değiştirmeyin. İlgili canonical kaynağı düzeltin ve builder'ı yeniden çalıştırın.

## Route doğrudan açılmıyorsa

Hash route kullanın:

```text
https://gridfreq.online/#/words
https://gridfreq.online/#/readings
https://gridfreq.online/#/study
https://gridfreq.online/#/tests
```

---

# Production Değişiklik Kuralı

Bir geliştirme `main` branch'e gönderilmeden önce:

1. canonical veri gerekiyorsa doğru source dosyada değiştirilmelidir
2. generated content yeniden oluşturulmalıdır
3. validatorlar geçmelidir
4. `flutter analyze` geçmelidir
5. `flutter test` geçmelidir
6. production root build doğrulanmalıdır
7. ardından `main` branch'e push yapılmalıdır

`main` push production GitHub Pages deploy'unu otomatik tetikler.

---

# Kısa Komut Özeti

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

flutter build web --release --base-href "/"
```

Production deploy:

```powershell
git push origin main
```

Canlı uygulama:

```text
https://gridfreq.online
```

---

## Not

Bu README production repository yapısını, canonical veri sözleşmesini ve GitHub Pages custom-domain deployment modelini belgelemek için hazırlanmıştır. Generated içerik canonical kaynak yerine geçmez; uygulamanın güvenilirliği canonical source → builder → validator → Flutter build → GitHub Pages zincirinin korunmasına dayanır.
