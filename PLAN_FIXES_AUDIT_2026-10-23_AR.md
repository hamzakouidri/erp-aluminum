# خطة إصلاح التطبيق — بعد الفحص الشامل (23 أكتوبر 2026)

> هذا الملف مُعدّ ليُسلَّم إلى جلسة Claude Code جديدة (على حساب آخر).
> انسخه كاملاً في أول رسالة، أو قل: «اقرأ الملف `PLAN_FIXES_AUDIT_2026-10-23_AR.md` ونفّذ الخطة مرحلة بمرحلة».

## السياق

- المشروع: ERP لورش الألمنيوم والـ PVC — Flutter 3.38+ / Dart 3.10+، Windows أساساً + Android/iOS.
- قاعدة البيانات: SQLite محلياً + مزامنة Supabase (وبعض أجزاء Firebase/Firestore).
- اقرأ `CLAUDE.md` أولاً: الشرح بالعربية دائماً، الترجمة عبر `Localization.translate(...)`، دعم الفأرة على الديسك توب.
- الفرع الحالي: `main`. **توجد 14 ملفات معدّلة غير محفوظة** (انظر المرحلة 0).

### نتيجة الفحص
- `flutter analyze`: **0 أخطاء**، 172 تحذيراً، 373 ملاحظة.
- `flutter test`: **802 ناجح، 3 فاشلة**.

---

## المرحلة 0 — حسم التعديلات غير المحفوظة (قبل أي شيء)

الملفات المعدّلة: `pubspec.yaml`, `pubspec.lock`, `lib/services/auth_service.dart`, `lib/login_screen.dart`,
`lib/services/share_filename_utils.dart`, `lib/Commande/devis_preview_screen.dart`, `lib/Commande/devis_builder.dart`,
`lib/Commande/window_painter.dart`, `lib/Commande/Systeme/show_system_francais.dart`,
`lib/Commande/Systeme/calculate_component.dart`, `lib/Commande/Systeme/material_consumption/pricing.dart`,
`lib/sql_database/catalog.dart`, `macos/Flutter/GeneratedPluginRegistrant.swift`.

محتواها باختصار:
1. **ترقية مكتبات**: Firebase (core 5 / auth 7 / messaging 17 / firestore 7)، `google_sign_in` 6→7، `archive` 3→4، `sqflite_common_ffi_web` 1.1.1، مع `dependency_overrides: image: 4.8.0`.
2. تكييف تسجيل الدخول بـ Google مع `google_sign_in 7` (دوال جديدة في `auth_service.dart`: `googleSignIn()`، `pickGoogleAccount()`، `fetchGoogleAccessToken()`).
3. اسم ملف PDF لعرض السعر = اسم الزبون كما كُتب (بالعربية أيضاً) عبر `devisPdfBaseName`.
4. أسعار مكوّنات الشتر حسب اللون (`ShutterColorPrices`) في `catalog.dart`.
5. رسم أدوات التحكم اليدوي للشتر النفقي في دالة `_drawTunnelShutterControls`.
6. صفحة الرسم تعرض مؤشر تحميل حتى يُحمَّل الكتالوج (`_initialCatalogReady = hasReusableCatalog`).

المطلوب:
- [ ] `flutter pub get` ثم `flutter analyze` (يجب 0 أخطاء).
- [ ] **تجربة يدوية**: تسجيل الدخول بـ Google على Android (لا تغطيه الاختبارات)، وعلى Windows.
- [ ] تجربة حفظ ملف قياسات واستيراده في `lib/Screen/measurements_screen.dart` (يستخدم `ZipEncoder/ZipDecoder` من `archive 4`).
- [ ] حفظ التعديلات في commits منفصلة حسب الموضوع (المكتبات + Google، اسم PDF، أسعار الشتر، الرسم).

---

## المرحلة 1 — 🔴 خلل الدفع الإلكتروني (أولوية قصوى)

### المشكلة
- `lib/Screen/electronic_payment_screen.dart` (الدالة `_verifyPaymentStatus` قرب السطر 194–215): بعد الدفع تستدعي
  `AlgerianPaymentService().activatePaidSubscription(...)`.
- `lib/services/algerian_payment_service.dart` (قرب السطر 310): تستدعي
  `SupabaseAccountService().setSubscriptionForWorkshopId` ← RPC `admin_set_workshop_subscription`.
- هذه الـ RPC في `supabase/catalog_sync.sql:202-247` ترفض غير المدير:
  `if not public.is_app_admin() then raise exception 'Only application administrators can change subscriptions'`.
- ⇒ **الزبون العادي يدفع ولا يُفعَّل اشتراكه**، والشاشة تعرض «نجاح» لأن قيمة `false` المُرجعة مُتجاهلة.

### مشكلة أمنية مرتبطة
- المفتاح السري لـ Chargily يُقرأ في التطبيق من Firestore `app_config/payment_gateway` أو من `SharedPreferences`
  (`getPaymentGatewayConfig`، قرب السطر 164)، والطلبات إلى `pay.chargily.net` تُرسَل من جهاز المستخدم بـ `Bearer $secretKey`.
- التحقق من حالة الدفع يتم على جهاز العميل ⇒ قابل للتلاعب.

### الإصلاح المقترح
1. **إصلاح فوري صغير** (يمكن نشره وحده):
   - في `_verifyPaymentStatus`: افحص القيمة المُرجعة من `activatePaidSubscription`؛ إن كانت `false` فاعرض رسالة خطأ مترجمة
     («تم الدفع لكن تعذّر تفعيل الاشتراك، تواصل مع الدعم مع رقم العملية …») بدل رسالة النجاح.
   - سجّل العملية في `subscription_payments` بحالة `pending_activation` حتى يفعّلها المدير يدوياً.
2. **الإصلاح الصحيح** (على الخادم):
   - Supabase Edge Function `create-checkout`: تستقبل `plan_id`، تقرأ السعر من الخادم (لا من التطبيق)، تنشئ checkout في Chargily بالمفتاح السري المخزّن في أسرار Supabase، وتعيد رابط الدفع.
   - Edge Function `chargily-webhook`: تتحقق من توقيع Chargily (`signature` header)، ثم تفعّل الاشتراك بصلاحية `service_role` (أو RPC جديدة `activate_paid_subscription` بـ `security definer` تُستدعى من الخادم فقط).
   - في التطبيق: احذف استخدام المفتاح السري نهائياً، واجعل `_verifyPaymentStatus` يقرأ حالة الاشتراك من Supabase فقط.
   - احذف `_defaultTestSecretKey` وحقل المفتاح السري من `payment_gateway_settings_screen.dart` و`admin_users_screen.dart` (أو اجعله يُحفظ في أسرار الخادم).
   - تأكد من قواعد Firestore: `app_config/payment_gateway` يجب ألا يكون مقروءاً للمستخدمين العاديين.
3. اختبار: أضف اختباراً في `test/` يتأكد أن فشل التفعيل لا يُظهر رسالة نجاح.

---

## المرحلة 2 — 🟠 الاختبارات الفاشلة الثلاثة

1. `test/drawing_frame_selection_camera_test.dart`:
   - «a click that moves a pixel or two still selects the frame»
   - «a double click on empty canvas leaves the view alone» (خطأ `Bad state: No element` في `selectionPainter` سطر 213)
   - **السبب**: تعديل المرحلة 0 في `lib/Commande/Systeme/show_system_francais.dart:526` — الصفحة تعرض مؤشر تحميل حتى يكتمل
     `_loadInitialCatalog()` (`lib/Commande/Systeme/window_view/frame_controls.dart:60`)، والاختبار لا ينتظر.
     في الاختبار يفشل تحميل الكتالوج برسالة `Bad state: locked`.
   - **الإصلاح**: في `pumpPage` بالاختبار، أعطِ النموذج كتالوجاً جاهزاً (`availableSystems` غير فارغة + `activeSeries`) أو انتظر بـ `pumpAndSettle`/حلقة `pump` حتى يظهر `WorkspaceSelectionPainter`. لا تتراجع عن التعديل في الشيفرة فهو صحيح.
2. `test/dump_motors_test.dart`: ليس اختباراً بل أداة تفريغ، تفشل بـ `MissingPluginException (sqflite_sqlcipher)`.
   **الإصلاح**: انقله إلى `tool/` (وكذلك `test/inspect_db_test.dart` إن كان مثله).
3. ملاحظة جانبية: رسالة متكررة `no such column: confirmed_mesures_json` من «Legacy glass override migration» — تأكد أن هذا الترحيل يعمل بعد إنشاء العمود في `lib/sql_database/schema.dart`، أو يتحقق من وجود العمود أولاً بـ `PRAGMA table_info`.

التحقق: `flutter test` ← يجب أن تنجح كلها.

---

## المرحلة 3 — 🟡 نقائص وظيفية

1. **سعر التكلفة ظاهر للجميع**: `lib/Commande/Systeme/material_consumption_screen.dart:92`
   `bool showCostPrice = true; // TODO: يُربط بصلاحية المدير`
   ⇒ اربطه بدور المستخدم (ابحث عن نظام الأدوار/الصلاحيات الموجود في المشروع، مثل ما يُستخدم في `workers_management_screen.dart`)، وأخفِ زر الإظهار للعامل.
2. **صفحة المخزون فارغة**: `lib/Inventory/inventory_page.dart` — ثلاثة تبويبات فيها نصوص مؤقتة فقط، وزر الإضافة فيه `// TODO` (سطر 60).
   ⇒ تحقق أولاً إن كانت هذه الصفحة مستخدمة أصلاً (`grep -rn "InventoryPage(" lib`)؛ إن لم تكن فاحذفها، وإلا اربطها بجداول المخزون الموجودة في `lib/sql_database/inventory_sales.dart`.
3. **نصوص غير مترجمة (~71 نصاً)**، أهمها:
   - `lib/Screen/worker_remnants_review_dialog.dart` (29 نصاً، لا يستخدم الترجمة إطلاقاً)
   - `lib/Screen/distribution_tracking_screen.dart` (6)، `lib/items_produits/catalogue_manager.dart` (5)، `lib/Screen/map_picker_screen.dart` (5)، `lib/items_produits/glass_systems_rules_screen.dart` (4)، `lib/Screen/workers_management_screen.dart` (4)، `lib/services/glass_fabrication_pdf_service.dart` (3).
   - أمر البحث (في Git Bash):
     ```
     LC_ALL=C.UTF-8 grep -rnP "(Text|labelText:|hintText:|tooltip:)\s*\(?\s*(const\s+)?['\"][^'\"]*[\x{0600}-\x{06FF}]" lib --include=*.dart | grep -vE "translate|_t\(|tr\("
     ```
   - أضف المفاتيح بالعربية والفرنسية والإنجليزية بنفس طريقة الملفات المجاورة، وشغّل `test/localization_coverage_test.dart`.

---

## المرحلة 4 — 🔵 نظافة المستودع (مهم للخصوصية)

⚠️ **بيانات زبائن حقيقية متتبَّعة في Git**:
- `diagnostics/phone_backups/*.db` (منها `Islem.db`، `35al_erp_backup.db`، نسخ بتاريخ 2026-07-25 و2026-08-22)
- `aluminum_database.db`، `my_app.db`، `test.db.corrupt_1782269788104`، `test.db.corrupt_1782273489686`

الخطوات:
- [ ] **اسأل المستخدم قبل الحذف**، ثم: `git rm --cached` لهذه الملفات (تبقى على القرص)، وأضف إلى `.gitignore`: `*.db` (مع استثناء `!assets/database.db` و`!assets/test_database.db` إن كانا ضروريين للتطبيق)، `*.corrupt_*`، `diagnostics/phone_backups/`.
- [ ] إن كان المستودع على GitHub ومشتركاً، فالبيانات موجودة في التاريخ: ناقش مع المستخدم تنظيفه (`git filter-repo`) — عملية خطرة تحتاج موافقة صريحة.
- [ ] ملفات تنفيذية: `innosetup.exe`، `is_setup.exe` ← أزلها من التتبّع.
- [ ] سكربتات ومخرجات مؤقتة في الجذر: `*.py` (append_*, update_*, patch_*, …)، `scratch/`، `.gemini/`، `analyze_out*.txt`، `diff*.txt`، `git_diff_*.txt`، `dart_analyze.txt`، `run_debug_log.txt`، `decompressed_pdf.txt`، ملفات `*.dart` المؤقتة في الجذر (`scratch.dart`، `test_font.dart`، `find_db.dart`، `dump_motors.dart`، `inject_sync.dart`، `restore_methods.dart`، `material_prev.dart`، `_fetchDefaults_extracted.dart`)، و`test_invoice*.pdf`.
  ⇒ اعرض القائمة على المستخدم، ثم انقل ما يريد الاحتفاظ به إلى `tool/` واحذف الباقي من التتبّع.
- [ ] `test/test_pdf_gen_test.dart` يكتب `test_invoice_images.pdf` في جذر المشروع في كل تشغيل ⇒ اجعله يكتب في مجلد مؤقت.

---

## المرحلة 5 — 🔵 جودة الشيفرة (غير عاجلة، على دفعات)

1. **تحذيرات `flutter analyze` (172)**: 44 `unused_element`، 27 `unused_local_variable`، 23 `unused_field`، 23 `unnecessary_non_null_assertion`، 15 `dead_code`، 11 `unnecessary_null_comparison`…
   - ابدأ بـ `lib/login_screen.dart`: دوال قديمة غير مستعملة `_syncSupabasePasswordSession` (518)، `_registerLegacy` (1122)، `_signInWithGoogleLegacy` (1728)، وشيفرة ميتة (1232، 1266، 1280، 1887).
   - `lib/Commande/order_table_edit_screen.dart:857` (`invalid_null_aware_operator`).
   - `lib/settings/document_status_localization.dart:51,54` (حالات مكررة في switch).
   - `lib/sql_database/catalog.dart:1112` `_insertDefaultColors` غير مستخدمة.
2. **واجهات مهجورة (373 ملاحظة)**: `withOpacity` ← `withValues(alpha: …)`، `groupValue/onChanged` في Radio ← `RadioGroup`، `value` ← `initialValue` في `DropdownButtonFormField`، `ExpansionTileController` ← `ExpansibleController`، وفي `lib/services/worker_push_notification_service.dart` `getToken/onTokenRefresh` ← `register()/onRegistered` (بعد ترقية firebase_messaging 17).
3. **566 كتلة `catch` فارغة**: لا تغيّرها كلها؛ ابدأ بخدمات المزامنة والدفع (`lib/services/cloud_sync_service.dart`، `algerian_payment_service.dart`) وأضف `debugPrint` على الأقل.
4. **ملفات ضخمة** (للمستقبل): `tempered_glass_work_screen.dart` (14k سطر)، `calculate_component.dart` (12.5k)، `window_painter.dart` (9.7k)، `welcom_screen.dart` (8.7k) — قسّمها إلى `part`/extensions كما فُعل في `material_consumption/`.

---

## أوامر التحقق بعد كل مرحلة

```
flutter analyze
```
```
flutter test
```
```
flutter run -d windows
```

## ترتيب العمل المقترح

0 ← 1 (الإصلاح الفوري أولاً، ثم الخادم) ← 2 ← 4 (بعد موافقة المستخدم) ← 3 ← 5.
كل مرحلة في commit (أو فرع) مستقل، مع شرح بالعربية للمستخدم، وشرح أوامر الدمج في `main` قبل تشغيل التطبيق.
