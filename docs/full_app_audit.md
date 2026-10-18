# تقرير الفحص الشامل لتطبيق ERP الألمنيوم والـ PVC

- **تاريخ الفحص:** 2026-10-16
- **النطاق:** شجرة العمل الحالية على الفرع `main` بما فيها التعديلات غير المُلتزَم بها (حوالي 350 ألف سطر Dart في `lib/`، وملفات `supabase/`).
- **طبيعة العمل:** فحص وتقرير فقط، دون أي تعديل على الكود.
- **الأدوات:** قراءة الكود، و`flutter analyze`، وبحث نصي ومنطقي. لم تُشغَّل الاختبارات (`flutter test`) ولا التطبيق نفسه، لذا كل ما يعتمد على سلوك وقت التشغيل موسوم بـ «يحتاج تحقق».
- **فحص تزامن الأسعار** (WorkshopPriceOverrides، المتوسط المرجّح، النشر والقبول) موثّق سابقاً في
  `C:\Users\hp\AppData\Roaming\Claude\side-session-notes\local_25c02591-7fec-4df8-8648-b0729cca0964\price-sync-audit.md`،
  ولا يتكرر هنا إلا ما يتقاطع معه.

### سلّم الخطورة

| الرمز | المعنى |
|---|---|
| 🔴 حرج | فقدان أو تلف بيانات مالية أو مخزنية، أو ثغرة أمنية، أو ميزة أساسية معطّلة |
| 🟠 عالٍ | نتائج خاطئة في حالات واقعية أو أداء يجمّد الواجهة |
| 🟡 متوسط | خطأ في حالات أقل شيوعاً أو هدر واضح |
| 🟢 منخفض | جودة كود، أو تنظيف، أو تحسينات صغيرة |

---

## 0. ملخص تنفيذي: أخطر عشر نتائج

1. 🔴 **الحذف النهائي لفاتورة شراء من سلة المحذوفات لا يعمل إطلاقاً.** الدالة تستعلم عن جدول `Inventory` غير موجود، ولو كان موجوداً لعكست المخزون مرتين (§2.1).
2. 🔴 **دفعات مبيعات المحل تُحسب مرتين.** تُسجَّل في الخزينة باسم الزبون، ثم تُخصَّص تلقائياً لطلبيات النوافذ (`Commandes`) وتُعلَّم تلك الطلبيات مدفوعة (§2.2).
3. 🔴 **مؤشر المزامنة التدريجية يعتمد على ساعة الجهاز (`updated_at`) لا على الخادم.** أي تعديل يُرفع متأخراً، أو من جهاز ساعته متأخرة، قد لا يصل أبداً لباقي الأجهزة (§4.1).
4. 🔴 **سياسات RLS على `workshop_sync_rows` تسمح لأي عضو، حتى المحظور أو العامل البسيط،** بقراءة وكتابة وحذف كل بيانات الورشة: الخزينة والأجور والأسعار (§4.2).
5. 🔴 **المفتاح السري لبوابة الدفع Chargily مخزّن في Firestore ويقرؤه كل عميل.** إضافة إلى ذلك، تفعيل الاشتراك بعد الدفع يستدعي RPC مخصّصاً للمدير فقط، فيفشل لكل المستخدمين العاديين (§4.3).
6. 🔴 **تصدير واستيراد النسخة الاحتياطية JSON معطّلان على الويندوز (المنصة الأساسية).** الإضافة `flutter_file_dialog` غير مسجّلة لهذه المنصة (§2.3).
7. 🔴 **قواعد بيانات حقيقية لزبائن وورش مرفوعة في git** (`diagnostics/phone_backups/*.db` وغيرها)، أي بيانات شخصية داخل المستودع (§4.4).
8. 🟠 **حساب الصافي المستحق (`net_payable`) يطبّق الضريبة على المبلغ قبل الخصم،** بينما الفاتورة المطبوعة تطبّقها بعد الخصم. رصيد الزبون يختلف عن فاتورته (§2.4).
9. 🟠 **مخزون `CurrentStock` يُزامَن كقيمة مطلقة بمبدأ «آخر كتابة تفوز».** إضافة إلى ذلك، أسطر بيع المحل تأخذ معرّفات autoincrement قد تتصادم بين جهازين، فيضيع خصم مخزون أو يُكتب سطر بيع فوق آخر (§4.5، §4.6).
10. 🟠 **كل رفع مزامنة (بعد 250 ms من أي كتابة) يعيد بناء مئات المشغّلات (triggers)** ويشغّل `PRAGMA quick_check` على كامل القاعدة، إضافة إلى عشرات `ALTER TABLE` الفاشلة في دوال قراءة متكررة. هذا هو المصدر الأرجح لبطء وتجمّد الواجهة (§3).

---

## 1. الميزات الناقصة مقارنةً بتطبيقات ERP وإدارة المبيعات المعروفة

ملاحظة: التطبيق غنيّ أصلاً. فيه مرتجعات مبيعات المحل والمشتريات، وسلة محذوفات، وسجل تدقيق، وإغلاق يومي (`BusinessDayClosings`)، وتنبيهات نقص المخزون، وتقارير موحّدة، وصلاحيات تفصيلية للعمال، وفضلات وقص، ودفع إلكتروني. الناقص هو التالي:

| # | الميزة | الوضع الحالي | الاقتراح |
|---|---|---|---|
| 1.1 | **الطابع الجبائي (Droit de timbre)** على الدفع نقداً، وهو إلزامي في الجزائر | غائب تماماً (لا يوجد أي ذكر لـ `timbre`) | حقل نسبة الطابع وحدّه الأقصى في الإعدادات، ويُطبَّق تلقائياً على الفواتير المدفوعة نقداً |
| 1.2 | **ضريبة مرنة في الفاتورة الرسمية** | النسبة ثابتة 19% و`remise / 1.19` (`devis_builder.dart:272-276`) | نسبة لكل سطر أو لكل وثيقة (0/9/19%) من الإعدادات، وتقرير TVA شهري (مُجمَّع/مُحصَّل، لتعبئة G50) |
| 1.3 | **فاتورة تصحيحية (Avoir) لطلبيات النوافذ** | المرتجعات موجودة لمبيعات المحل والمشتريات فقط | وثيقة Avoir مرتبطة بالطلبية تعكس المبلغ في دفتر الزبون |
| 1.4 | **ترقيم قانوني متسلسل للفواتير** بلا فجوات ولا تكرار بين الأجهزة | ترقيم محلي لكل جهاز، ولا مصالحة للطلبيات والزبائن (§2.11) | سلسلة ترقيم تُحجز من الخادم (RPC) للوثائق الرسمية، مع رقم مؤقت أثناء العمل دون اتصال |
| 1.5 | **آجال الدفع وأعمار الديون (Aging)** | لا يوجد `due_date` ولا تقرير 30/60/90 يوماً | حقل تاريخ استحقاق، وتقرير أعمار الذمم للزبائن والموردين، وتذكير تلقائي |
| 1.6 | **تصدير Excel/CSV** | غائب تماماً (0 ملف) | تصدير الجداول والتقارير (الطلبيات، الخزينة، المخزون، كشوف الحساب) |
| 1.7 | **نسخ احتياطي تلقائي مجدول** | يدوي فقط، وغير مشفّر، ومعطّل على الويندوز (§2.3) | نسخة يومية تلقائية مدوّرة (آخر 7–30 نسخة)، مشفّرة، مع التحقق من سلامة الاستعادة |
| 1.8 | **فرض الصلاحيات على الخادم** | الصلاحيات في الواجهة فقط (`app_settings.dart:433+`) و RLS لا تميّز الأدوار (§4.2) | RLS حسب `table_name` والدور، أو RPC لكل عملية حساسة |
| 1.9 | **حجز مخزون حقيقي للطلبيات** | «الحجز» مجرد علامة على الطلبية، لا يمنع بيع الكمية من المحل (§2.9) | كمية محجوزة في `CurrentStock` تُطرح من المتاح في كل الشاشات |
| 1.10 | **أمر شراء للمورد واقتراح إعادة الطلب** | جزئي: تنبيه نقص فقط | أمر شراء (Bon de commande fournisseur) يُولَّد من النواقص، ثم استلام جزئي |
| 1.11 | **جرد فعلي دوري (Stocktake)** | تعديل مخزون يدوي فقط | جلسة جرد: عدّ، ثم مقارنة، ثم قيد فروقات بتاريخ واحد |
| 1.12 | **قوائم أسعار حسب الزبون أو الفئة** | غائبة (`price_list` = 0) | فئات أسعار (جملة/تجزئة/مقاول) |
| 1.13 | **صلاحية عرض السعر (Devis)** | لا يوجد `valid_until` | تاريخ انتهاء، وتنبيه، وتحويل العرض إلى طلبية |
| 1.14 | **محاسبة عامة** (دليل حسابات، قيود يومية، ميزانية) | غائبة؛ يوجد تقرير مالي موحّد فقط | على الأقل تصدير قيود يومية متوافقة مع برامج المحاسبة |
| 1.15 | **أمان الحساب** (مهلة جلسة، قفل التطبيق، 2FA للمدير) | غائب | قفل بعد خمول، ورمز PIN للعمليات الحساسة (حذف، تسوية أجور) |
| 1.16 | **تشفير القاعدة على الويندوز** | SQLCipher على الجوال فقط (`test/sqlcipher_mobile_reopen_test.dart`)، والقاعدة على سطح المكتب غير مشفّرة | تشفير أو على الأقل حماية مجلد البيانات، ونقل الأدوار من `SharedPreferences` |
| 1.17 | **تقارير ربحية حقيقية** لكل طلبية أو منتج (تكلفة فعلية من CMP مقابل سعر البيع) | جزئية | تقرير هامش ربح يعتمد على `cost_price` الموزون |

---

## 2. الأخطاء والثغرات المنطقية (مرتّبة حسب الخطورة)

### 2.1 🔴 الحذف النهائي لفاتورة شراء من السلة معطّل، وخطير لو عمل
- **الدليل:** `lib/sql_database.dart:11393-11488` (`deleteAchat`) تستعلم وتحدّث جدول `'Inventory'` (الأسطر 11409, 11439, 11457, 11463). هذا الجدول **غير معرّف في أي مكان** من المخطط؛ الجدول الفعلي هو `CurrentStock`.
- **الأثر:**
  - يُرمى خطأ `no such table: Inventory`، فيفشل الحذف النهائي دائماً.
  - الواجهة تعرض SnackBar أحمر **فارغ النص** (`lib/Screen/trash_screen.dart:370` `Text('')`).
  - «تفريغ السلة» يبتلع الخطأ بصمت ويعرض عدداً خاطئاً (`sql_database.dart:11786-11793`).
- **حتى لو صُحّح اسم الجدول:** الفاتورة في السلة سبق أن عُكس مخزونها في `deleteAchatToTrash` (`:11568-11616`، `stock_reversed_on_delete`)، فسيُطرح المخزون مرة ثانية. كما ستُحذف حركات `Purchase` التاريخية، وتُحذف كل حركات الخزينة للمورد بهذا `reference_id`.
- **رسالة الخطأ نفسها تالفة الترميز:** `"?? ???? ??? ..."` في `:11428`.
- **الإصلاح:** إعادة كتابة `deleteAchat` لفاتورة موجودة في السلة: لا تلمس المخزون إن كان `stock_reversed_on_delete = 1`، وتحذف السجلات داخل معاملة واحدة، وتسجّل tombstones. ثم إظهار نص الخطأ في `trash_screen` وإصلاح رسالة الترميز.

### 2.2 🔴 دفعات مبيعات المحل تُخصَّص لطلبيات النوافذ (عدّ مزدوج)
- **الدليل:**
  - `lib/Screen/material_sale_editor_screen.dart:769-781` يسجّل الدفعة بـ `insertTreasury('encaissement', …, referenceId: saleId, entityType: 'Client', entityId: _clientId)`.
  - `insertTreasury` يستدعي `_rebuildClientPaymentLedger` لكل حركة زبون (`sql_database.dart:14224`، وكذلك 14339 و14397 عند التعديل والحذف).
  - `_rebuildClientPaymentLedger` (`:13777-13955`) يعتبر **كل** `encaissement` للزبون إيصالاً، ويوزّعه على `Commandes` فقط. يربط `reference_id` كأنه رقم طلبية (`LEFT JOIN Commandes c ON c.id = t.reference_id`)، ثم يحدّث `advance_payment` و`payment_status` للطلبيات.
- **الأثر:** زبون اشترى من المحل ودفع، وله طلبية نوافذ مفتوحة: تُعلَّم الطلبية مدفوعة جزئياً أو كلياً، وفي الوقت نفسه `MaterialSales.paid_amount` يحسب المبلغ نفسه. الذمم وتقارير التحصيل خاطئة.
- **الإصلاح:**
  - تمييز مصدر الإيصال، بـ `document_type` في `Treasury` أو `entity_type = 'MaterialSale'`.
  - استبعاد إيصالات المحل من دفتر الطلبيات، وتخصيصها في `PaymentAllocations` بـ `document_type = 'MaterialSale'`.
  - مسح البيانات القائمة لإعادة بناء الدفاتر المتأثرة.

### 2.3 🔴 النسخ الاحتياطي JSON معطّل على الويندوز، وغير آمن
- **الدليل:**
  - `exportJsonBackup` و`importJsonBackup` (`sql_database.dart:16524-16620`) تستعملان `FlutterFileDialog.saveFile` و`pickFile`.
  - `flutter_file_dialog` **غير موجودة** في `windows/flutter/generated_plugins.cmake` لأنها تدعم Android وiOS فقط، فالنتيجة المتوقعة `MissingPluginException` (يحتاج تحقق تشغيلي).
- **إضافة إلى ذلك:**
  - الملف يُكتب كاملاً غير مشفّر إلى `getTemporaryDirectory()/al_erp_backup.json` (`:16551`) ولا يُحذف بعدها.
  - طبقة القاعدة تبني واجهات (`BuildContext`، `SnackBar`) بنصوص عربية ثابتة.
  - لا يوجد تحقق من نسخة المخطط عند الاستيراد.
- **الإصلاح:**
  - استخدام `file_selector` أو `file_picker` (موجودتان في `pubspec.yaml:51`) على سطح المكتب.
  - حذف الملف المؤقت بعد الحفظ، وتشفير اختياري.
  - إضافة ترويسة `schema_version` والتحقق منها، ونقل الواجهة إلى `settings_screen`.

### 2.4 🟠 الصافي المستحق (`net_payable`) لا يطابق الفاتورة المطبوعة
- **الدليل:**
  - **الحفظ:** `add_commande.dart:1434-1436` يحسب `calculatedTax = total * taxInput / 100` على الإجمالي **قبل** الخصم، ثم `netPayable: total - calculatedRemise + calculatedTax` (`:1609`).
  - **نسخ الطلبية:** `commande.dart:5785` بنفس الصيغة.
  - **التصدير:** `order_export_service.dart:233` بنفس الصيغة.
  - **الفاتورة:** `devis_builder.dart:277-280` تحسب `totalBeforeTax = total - remise` ثم `tva = totalBeforeTax * tva%`، وهي الصيغة الصحيحة محاسبياً.
- **الأثر:** إذا وُجد خصم وضريبة معاً، يكون رصيد الزبون (المبني على `net_payable` في `_rebuildClientPaymentLedger :13881`) أكبر من مبلغ الفاتورة بقيمة `remise × tva%`.
- **الإصلاح:** دالة واحدة مشتركة `computeOrderTotals(total, remise, tvaPercent)` تُستعمل في الأماكن الأربعة، مع ترحيل لإعادة حساب `net_payable` للطلبيات القديمة.

### 2.5 🟠 تعديل وثيقة محل مؤكدة («التعديل الإجباري») لا يصحّح المخزون
- **الدليل:**
  - `_isLocked` يُتجاوز بـ `_forceEditing` (`material_sale_editor_screen.dart:245-252`).
  - الحفظ يعيد كتابة الأسطر كلها عبر `saveMaterialSaleWithItems` (`sql_database.dart:23906-23960`، حذف ثم إدراج)، ثم يستدعي `deductStockForMaterialSale`.
  - `deductStockForMaterialSale` يعود فوراً إذا كان `stock_deducted = 1` (`:24024`).
- **الأثر:** تغيير الكمية من 10 إلى 4 مثلاً يترك المخزون مخصوماً بـ 10، والعكس أيضاً، فيحدث خلل دائم بين الوثيقة والمخزون. حذف وإعادة إدراج الأسطر يغيّر معرّفاتها، فيكسر أيضاً منطق المرتجعات المرتبط بالمفاتيح.
- **الإصلاح:** عند تعديل وثيقة مخصومة: احسب الفرق لكل صنف وطبّق حركة تسوية داخل المعاملة نفسها، أو امنع التعديل وافرض «مرتجع ثم وثيقة جديدة».

### 2.6 🟠 تغيير المخزن في وثيقة محل موجودة لا يُحفظ
- **الدليل:**
  - `updateMaterialSale` (`sql_database.dart:23162-23213`) لا يقبل `locationId`.
  - المحرر يخصم من `_locationId` الحالي (`material_sale_editor_screen.dart:373-375، 446-448، 975-977`).
  - الحذف والمرتجع يعيدان إلى `sale['location_id']` القديم (`sql_database.dart:23243، 23780`).
- **الأثر:** يُخصم من المخزن «ب» ويُعاد إلى المخزن «أ»، فينتقل المخزون بين المخازن دون أي وثيقة تحويل.
- **الإصلاح:** إضافة `locationId` إلى `updateMaterialSale`، ومنع تغييره بعد الخصم.

### 2.7 🟠 حذف وثيقة محل بعد مرتجع جزئي يضخّم المخزون، والحذف غير ذرّي
- **الدليل:**
  - `deleteMaterialSale` (`sql_database.dart:23216-23320`) يعيد **كامل** `quantity` لكل سطر، بينما المرتجع (`returnMaterialSaleItems :23688`) سبق أن أعاد جزءاً.
  - وثيقة المرتجع تبقى فعّالة ومرتبطة بوثيقة محذوفة.
  - عكس المخزون يتم في معاملة، وتحديث `is_deleted/stock_deducted` في استدعاء منفصل (`:23290-23305`). انقطاع بينهما ثم إعادة محاولة يعني إعادة المخزون مرتين.
- **الإصلاح:** أعد فقط `sold - returned`، أو امنع حذف وثيقة لها مرتجعات. ضع العكس والتحديث في معاملة واحدة.

### 2.8 🟠 «المبلغ المسدد» قابل للتحرير مباشرةً دون حركة خزينة
- **الدليل:** حقل `_paidCtrl` قابل للتحرير (`material_sale_editor_screen.dart:2954-2975`) ويُحفظ في `paid_amount` عند الإنشاء والتعديل (`:242`، `:354`، `:905`). حركة الخزينة تُسجَّل فقط عبر زر «تسجيل دفعة» (`:769`).
- **الأثر:** وثيقة تظهر مدفوعة بينما الصندوق لا يحتوي المبلغ، فإغلاق اليوم والتقارير غير متطابقة.
- **الإصلاح:** اجعل الحقل للقراءة فقط ومشتقاً من مجموع الإيصالات، أو أنشئ حركة خزينة تلقائياً بالفرق.
- **ملاحظات مرافقة:**
  - إدراج الإيصال وتحديث `paid_amount` غير ذرّيين (`:769-794`).
  - حذف حركة الخزينة لاحقاً لا يُنقص `paid_amount` للوثيقة، لأن `deleteTreasury :14286` يعيد بناء دفتر الطلبيات فقط.

### 2.9 🟠 حجز مخزون الطلبية يُفسد خطة الفضلات للطلبية نفسها، ولا يحجز شيئاً فعلياً
- **الدليل:**
  - `setOrderStockReservation` (`sql_database.dart:4974-5020`) يضع الفضلات `status = 'reserved'`.
  - شاشة البضاعة المطلوبة تقرأ فقط `status = 'available'` (`readAvailableMaterialRemnants :17416-17418`، تُستدعى من `order_required_goods_screen.dart:4812`)، فتختفي الفضلات المحجوزة من خطة الطلبية نفسها.
  - `applyOrderInventoryIssue` يشترط `status = 'available'` (`:17680-17690`)، فيرمي «الفضلة غير متاحة» لفضلة محجوزة لهذه الطلبية.
  - الحجز لا يُنقص الكمية المتاحة لمبيعات المحل (`deductStockForMaterialSale` لا يعرف الحجز).
  - `stock_reserved_at` بتوقيت محلي وليس UTC (`:4983`).
- **الإصلاح:** اعتبر `reserved_order_id = orderId` متاحاً لهذه الطلبية في القراءة والاعتماد. أضف كمية محجوزة تُطرح من «المتاح» في كل مكان، ووحّد التوقيت إلى UTC.

### 2.10 🟠 تسوية أجور العامل الأسبوعية غير ذرّية وفيها سباق
- **الدليل:** `settleWorkerWeek` (`sql_database.dart:8925-9058`): ثلاثة استعلامات SUM، ثم ثلاثة `UPDATE … is_settled = 1`، ثم إدراجان وحركة خزينة، كل ذلك **خارج أي معاملة**.
- **الأثر:**
  - مهمة تصل من المزامنة (أو عملية أخرى) بين الحساب والتحديث تُعلَّم «مسوّاة» دون أن تُدفع.
  - انقطاع في المنتصف يترك حالة نصف مسوّاة.
  - الضغط مرتين يُنشئ ترحيلاً مكرراً.
- **الإصلاح:** معاملة واحدة، مع تحديد المعرّفات المسوّاة صراحةً (`WHERE id IN (…)` من نتيجة الحساب)، ومفتاح منع تكرار.

### 2.11 🟠 تكرار أرقام الطلبيات والزبائن بين الأجهزة
- **الدليل:** `_reserveNextOrderCode` (`:5140`) و`_reserveNextClientCode` (`:4855`) تعتمدان على تسلسل محلي (`OrderCodeSequence`/`ClientCodeSequence`). توجد مصالحة لأرقام المحل فقط (`reconcileMaterialSaleDisplayCodes :23056`).
- **الأثر:** جهازان دون اتصال ينتجان «طلبية #120» مرتين، وهذا خطير للفواتير الرسمية.
- **الإصلاح:** مصالحة مماثلة بعد التنزيل، أو حجز الأرقام من الخادم (انظر 1.4).

### 2.12 🟡 دفتر المورّد يشمل فواتير الشراء المحذوفة (في السلة)
- **الدليل:** `_rebuildSupplierPaymentLedger` (`:13966-13972`) يستعلم `Achats` بشرط `supplier_id = ?` فقط، دون `is_deleted = 0`. في المقابل، دفتر الزبون يستبعد المحذوف (`:13784`).
- **الأثر:** دفعات المورد تُخصَّص لفاتورة ملغاة، فتظهر الفاتورة الفعّالة غير مسدّدة.
- **الإصلاح:** إضافة شرط الاستبعاد.

### 2.13 🟡 رقم فاتورة الشراء التالي يقفز
- **الدليل:** `getNextAchatInvoiceNumber` (`:11359-11390`) يأخذ أكبر رقم يجده في **أي** `invoice_number`، بما فيها أرقام فواتير المورّدين مثل `FA-2026/004512`، فيصبح الرقم التالي `ACH-4513`.
- **الإصلاح:** اقتصر على النمط `^ACH-(\d+)`.

### 2.14 🟡 رسائل خطأ ونصوص تالفة الترميز (mojibake) تظهر للمستخدم
- `sql_database.dart:18910`: اسم افتراضي للصنف المجهول في المخزون `'â”˜Ã â•ªÂ¼…'` (أصله «مجهول»)، **يظهر في شاشة المخزون**.
- `sql_database.dart:11428`: رسالة `"?? ???? …"`.
- `sql_database.dart:19619` وتعليقات `11490/11507/13138`: تعليقات تالفة.
- `lib/items_produits/joint.backup.dart`: ملف نسخة قديمة داخل `lib/` فيه 14 سطراً تالفاً.
- **ملاحظة:** الأسطر `204-209`، و`1785-1797`، و`18113-18120`، و`client.dart:1218`، و`commande.dart:6359`، و`welcom_screen.dart:3929`، و`calculate_component.dart:1888`، و`treasury_screen.dart:1995`، و`supplier_details_screen.dart:133` **مقصودة**: هي خرائط لإصلاح بيانات قديمة تالفة. أما رسالة `importGlobalCatalog` فمذكورة في تقرير الأسعار.

### 2.15 🟡 كود ميت يخفي منطقاً مقصوداً (من `flutter analyze`)
- `add_commande.dart:2010`: بعد `return;` في `_recalculateProductSellingPrice` يوجد حوالي 150 سطراً لاستبعاد المقاطع `exclude_from_pricing` وحساب التسعير، وكلها لا تُنفَّذ. المطلوب التأكد أن شاشة `MaterialConsumptionScreen` تطبّق الاستبعاد نفسه، ثم حذف الكود.
- `login_screen.dart:1237/1271/1285/1899`: منطق Firestore قديم بعد `return`؛ وأيضاً `if (isNewAuthUser) signOut else signOut` (`:1235-1239`).
- `order_table_edit_screen.dart:685`، `window_painter.dart:6127/6238`، `show_system_francais.dart:21414/22305`، `calculate_component.dart:6064/6080`، `model.dart:20316`، `app_settings.dart:778/836`.

### 2.16 🟡 إشعار طلبية جديدة بلا اسم زبون
- `supabase_workshop_sync_service.dart:1393`: `final clientName = ' '.trim();` تعطي دائماً نصاً فارغاً.

### 2.17 🟢 ملاحظات منطقية صغيرة
- `deductStockForMaterialSale` يتحقق من كل سطر منفرداً مقابل كامل الرصيد (`:24030-24060`). صنف مكرر في سطرين قد يمرّ ثم يصبح المخزون سالباً. الواجهة تمنع التكرار (`_hasDuplicateItems`)، لكن الدالة نفسها غير آمنة؛ يُقترح تجميع الكميات قبل التحقق.
- حركة المرتجع `paid_amount = total` (`:23744`) دون أي حركة خزينة لاسترداد المبلغ للزبون، ولا خيار «رصيد دائن أو استرداد نقدي».
- `insertTreasury` يرسل إشعاراً بنص عربي ثابت `'حركة دفع جديدة'` و`'د.ج'` (`:14268-14275`) بغض النظر عن لغة المستلم.
- أسماء الصناديق مخزّنة كنصوص عربية ثابتة (`'صندوق المحل'`، `'الصندوق الرئيسي'`)، فتظهر بالعربية في الواجهة الفرنسية، وأي تغيير في الاسم يكسر الربط.
- 103 رسالة `StateError/Exception` بالعربية تُعرض للمستخدم كما هي (`'$e'`) دون ترجمة.

---

## 3. مشاكل الأداء

### 3.1 🔴 إعادة بناء بنية المزامنة مع كل كتابة
- `_ensureSyncTombstoneInfrastructure` (`sql_database.dart:14525-14700`) **بلا أي علامة «جاهز»**. في كل استدعاء تقوم بما يلي:
  - تنفّذ `CREATE TABLE IF NOT EXISTS` ثلاث مرات.
  - تستدعي `_ensureProfileColorsSyncIds` و`_ensureWorkshopPriceSchema`.
  - تقرأ `PRAGMA table_info` لـ**كل** جداول القاعدة (أكثر من 100 جدول).
  - تنفّذ `CREATE TRIGGER IF NOT EXISTS` أربع مرات لكل جدول.
- تُستدعى في `exportPendingCloudChanges` (`:14720`)، أي بعد **كل** كتابة محلية (debounce 250 ms في `supabase_workshop_sync_service.dart:81, 309-327`). وتُستدعى أيضاً في `deleteTreasury :14294`، و`deleteClient :5552`، وحذف الطلبيات `:9829/9925`، وغيرها (17 موضعاً).
- إضافة إلى ذلك، `exportPendingCloudChanges` يشغّل `PRAGMA quick_check` على **كامل** القاعدة في كل رفع (`:14721`)، وكذلك `exportAllData` (`:15041`) و`:16237`.
- **الإصلاح:**
  - علامة ثابتة لكل اتصال (كما في `_ensureRemnantInventorySchema`).
  - إنشاء المشغّلات مرة عند الفتح والترقية فقط.
  - `quick_check` عند الفتح أو مرة يومياً، لا في كل رفع.

### 3.2 🟠 أوامر `ALTER TABLE` فاشلة داخل دوال قراءة متكررة
كل `ALTER TABLE ADD COLUMN` لعمود موجود يرمي استثناء يُلتقط بصمت. هذا مكلف (تحليل المخطط وقفل الكتابة) ويحدث في كل قراءة:

| الدالة المستدعاة كثيراً | ما تنفّذه في كل مرة | الموقع |
|---|---|---|
| `readAccessories` و`insertAccessory` و`updateAccessory` | 12 أمر `ALTER TABLE Accessories` | `_ensureAccessoryRulesColumns :10644` ← `:12884` |
| `readCurrentStock` و`readAllPossibleStock` و`updateMinQty` | `ALTER TABLE CurrentStock` | `_ensureInventoryAlertSchema :17114` ← `:18895` |
| `readMaterialClients` و`ensureInternalWorkshopClient` و`ensureDiversMaterialClient` | `ALTER` **ثم `UPDATE Client` على كل الزبائن** | `_ensureClientBusinessSegment :5170` |
| `readCommandesWithClients` وسلة الطلبيات | حوالي 15 `ALTER TABLE Commandes`، و`CREATE TABLE Projects`، و`_backfillOrderCodes` | `_ensureOrderQueryInfrastructure :5806-5860` ← `:5870, 5924` |
| دوال التوصيل (5 دوال) | `CREATE TABLE` و`ALTER` | `_ensureDeliveriesLoadedColumn :10609` |
| كل إعادة بناء دفتر زبون أو مورد | `CREATE TABLE` و`INDEX` | `_ensurePaymentAllocationSchema :13684` |
| إنشاء زبون أو قراءة الأكواد | `ALTER` و`CREATE` | `_ensureClientCodeInfrastructure :4750` |
| `hasOrderInventoryIssue` وغيرها | `CREATE TABLE` | `_ensureOrderInventoryIssueSchema :17122` |
| `ensureTemperedGlassItemsTable` و`_ensureSectionSharingSchema` و`_ensureShutterColorTables` | `CREATE TABLE` و`INDEX` | `:21706`، `:2143`، `:1896` |

- يوجد 430 أمر `ALTER TABLE` و107 `CREATE TABLE IF NOT EXISTS` في `sql_database.dart`.
- **الإصلاح:** نقل كل الترحيلات إلى `onUpgrade` مع رقم إصدار (الإصدار الحالي 71، `:496/514`)، أو علامة `static bool _xReady` لكل دالة كما فُعل في `_ensureOrderPinningInfrastructure`.

### 3.3 🟠 استعلامات N+1
- `readCurrentStock` (`:18895-19020`): لكل صنف في المخزون استعلامان (لون، ثم اسم من الجدول المناسب)، أي 4000 استعلام لـ 2000 صنف.
  - لوحة التحكم تستدعيها **لكل مخزن** (`welcom_screen.dart:400-420`) لمجرد عدّ الأصناف تحت الحد الأدنى.
  - **الإصلاح:** استعلام واحد بـ `LEFT JOIN` على Sections/Accessories/… و Colors، و`SELECT COUNT` مباشر لتنبيه النقص.
- `achat_item_picker.dart:326, 361, 395`: `getLatestPurchasePrice` لكل ستارة وزجاج وجوان، أي مئات الاستعلامات عند فتح منتقي الأصناف. **الإصلاح:** استعلام واحد مجمّع (`GROUP BY item_id`).
- `client_ledger_screen.dart:83-85`: قراءة تفاصيل كل طلبية في حلقة. **الإصلاح:** `WHERE id_commandes IN (…)`.
- `series_table_config_screen.dart:598`، `bom_engine_v2.dart:236`، `catalogue_manager.dart:2534`: استعلام لكل عنصر في حلقة.
- `_backfillOrderCodes` (`:5063`) و`_uniqueMaterialSaleCode` (`:23030`، حلقة `while` باستعلام لكل محاولة).

### 3.4 🟠 فهارس مفقودة على أكثر الجداول استعلاماً
الفهارس الموجودة (21 فهرساً) كلها على جداول الكتالوج والمحل. **لا يوجد فهرس على:**
- `Commandes(client_id)`، و`Commandes(is_deleted, created_at)`.
- `Commandes_details(id_commandes)`، وهو أكثر جدول يُقرأ.
- `Treasury(entity_type, entity_id)`، و`Treasury(reference_id)`.
- `InventoryTransactions(item_type, item_id, color_id)`، و`(reference_id, transaction_type)`.
- `WorkerAllocations(worker_uid, is_settled)`، و`WorkerTransactions(worker_uid, is_settled)`.
- `Achat_items(achat_id)`، و`Achats(supplier_id)`.

إضافة إلى ذلك، `LEFT JOIN Client cl ON (c.client_id = cl.id OR CAST(c.client_id AS TEXT) = CAST(cl.id AS TEXT))` (`:5887، 5904، 5938`) يُبطل أي فهرس ويجعل قائمة الطلبيات O(طلبيات × زبائن). **الإصلاح:** توحيد نوع `client_id` بترحيل لمرة واحدة، ثم `ON c.client_id = cl.id`.

### 3.5 🟡 تحميل جداول كاملة بلا pagination
- `readCommandesWithClients` (`SELECT c.*` لكل الطلبيات)، و`readMaterialSales :23554`، و`readTreasury :13677`، و`readInventoryTransactions :19026`، و`readAllWorkerAllocations :7439`.
- لوحة التحكم تقرأ كل الطلبيات (`readCommande`) وتنفّذ `migrateAllPendingOrdersToNouveau` (UPDATE ورفع لكل طلبية) **في كل تحميل للإحصاءات** (`welcom_screen.dart:650`). هذه هجرة لمرة واحدة يجب نقلها إلى الترقية.
- **الإصلاح:** `LIMIT/OFFSET` أو keyset pagination في الشاشات، و`COUNT/SUM` في SQL للإحصاءات.

### 3.6 🟡 كثرة طلبات الشبكة في المزامنة
- `_startPermissionsRefreshFallback` يستعلم `workshop_members` و`isCurrentUserAdmin` **كل 10 ثوانٍ** لكل جهاز (`supabase_workshop_sync_service.dart:798-808`)، رغم الاشتراك اللحظي. ويبثّ حدث صلاحيات في كل مرة، فقد يعيد بناء الواجهات. **الإصلاح:** كل 2–5 دقائق، ولا بثّ إلا عند تغيّر البصمة.
- دورة الخلفية كل 3 دقائق تقرّر «تنزيلاً كاملاً» ما دام `bootstrapComplete` غير مُعلَّم. هذا لا يُعلَّم إذا كانت الورشة بلا بيانات أعمال (`:825-829`، `shouldCompleteFullBootstrap`)، فتجلب ورشة جديدة كل الجداول كل 3 دقائق.
- أحجام الدفعات صغيرة جداً: 5 صفوف لـ `Commandes_details` (`:1286`)، و10 صفوف للتنزيل التدريجي (`:1353`). آلاف الرحلات للخادم عند التهيئة.
- `loadAndApplyWorkshopCatalogConfiguration` في كل دورة خلفية.

### 3.7 🟡 ثقل الواجهات
- ملفات عملاقة بحالة واحدة: `show_system_francais.dart` (24,862 سطراً)، و`model.dart` (25,609)، و`calculate_component.dart` (11,918)، و`tempered_glass_work_screen.dart` (12,171)، و`welcom_screen.dart` (8,656). أي `setState` يعيد بناء أشجار ضخمة، والتحليل والبناء بطيئان.
- إعادة التسعير الجماعي تفتح شاشة `MaterialConsumptionScreen` كاملة (`Navigator.push`) **لكل منتج** في حلقة (`add_commande.dart:1977-2000`). يجب استخراج حساب التكلفة إلى خدمة بلا واجهة.
- 161 استدعاء لـ `withOpacity` المهجور (تخصيص `Color` في كل build)، واستبدالها بـ `withValues(alpha:)` أو ثوابت.

---

## 4. المزامنة والأمان والترجمة والتمرير

### 4.1 🔴 مؤشر المزامنة التدريجية يعتمد على ساعة العميل
- عند الرفع: `'updated_at': storedUpdatedAt` من الصف المحلي (`supabase_workshop_sync_service.dart:1923`، والحذف `:1899`)، لا `now()` الخادم.
- عند التنزيل: `.gt('updated_at', since)` حيث `since` هو أحدث `updated_at` شوهد (`:1359`، `:1478`).
- **الأثر:** تعديل أُجري دون اتصال صباحاً ورُفع مساءً، أو من جهاز ساعته متأخرة، يحمل `updated_at` أقدم من مؤشر بقية الأجهزة، فلا يُنزَّل لديها أبداً (إلا بتنزيل كامل يدوي). وهذا يتفاقم مع:
  - pagination بـ `range(offset)` على مجموعة تتغير أثناء القراءة (`:1353-1370`)، فقد يُتخطّى صف.
  - تساوي الطوابع الزمنية عند حدّ الصفحة.
- **الإصلاح:** عمود خادم `server_seq bigserial`، أو `synced_at timestamptz default now()` يُحدَّث بمشغّل `BEFORE INSERT OR UPDATE`. يُستعمل هو كمؤشر (`gt server_seq`) مع keyset pagination. يبقى `updated_at` للعميل لحل التعارض فقط.

### 4.2 🔴 RLS على `workshop_sync_rows` لا تميّز الأدوار ولا الحظر
- `supabase/catalog_sync.sql:1209-1275`: سياسات `select/insert/update/delete` تشترط فقط `workshop_id in (select workshop_id from workshop_members where user_id = auth.uid())`.
- **الأثر:**
  - عامل **محظور** (`blocked = true`) يحتفظ بالقراءة والكتابة الكاملة عبر REST.
  - أي عامل يستطيع عبر REST قراءة `Treasury` و`WorkerTransactions` (أجور زملائه) والأسعار، وحذف أي صف (حذف الطلبيات أو الخزينة) دون المرور بصلاحيات الواجهة.
  - الصلاحيات الحالية تُفرض فقط في Flutter (`app_settings.dart:433+`) ومن `SharedPreferences` (`user_role`)، وهذه قابلة للتعديل محلياً على الويندوز.
- **الإصلاح:**
  - أضف `and not m.blocked` لكل السياسات.
  - اجعل الحذف للمدراء فقط.
  - أنشئ دالة `can_access_table(workshop_id, table_name, op)` تقرأ `role/permissions`، وتمنع العامل من جداول `Treasury`، و`WorkerTransactions` لغيره، و`PaymentAllocations`، وجداول الأسعار.

### 4.3 🔴 بوابة الدفع والاشتراكات
- **المفتاح السري لـ Chargily:**
  - `savePaymentGatewayConfig` يحفظه في Firestore `app_config/payment_gateway` (`algerian_payment_service.dart:184-207`).
  - `getPaymentGatewayConfig` يقرؤه **كل عميل** لإنشاء جلسة الدفع (`:164-180`، `:218`، `:285`).
  - كل من يقرأ هذه الوثيقة يملك المفتاح السري للحساب التجاري.
  - مفتاح اختبار مضمّن في الكود (`_defaultTestSecretKey :89`)، و`baridi_mob_rip` افتراضي وهمي (`:178`).
- **التفعيل بعد الدفع:**
  - `activatePaidSubscription` (`:311-330`) يُنفَّذ من العميل ويستدعي `admin_set_workshop_subscription`.
  - هذا الـ RPC يرفض غير المدير (`supabase/catalog_sync.sql:215-220` «Only application administrators»).
  - **النتيجة:** المستخدم العادي يدفع ولا يُفعَّل اشتراكه آلياً (يحتاج تحقق تشغيلي). ولو سُمح بالـ RPC للعميل لصار التفعيل دون دفع ممكناً.
- **الإصلاح:** نقل إنشاء جلسة الدفع والتحقق إلى Edge Function بـ secret في متغيرات البيئة، والتفعيل عبر **Webhook** من Chargily موقَّع ومتحقَّق منه على الخادم.
- **بريد مدير مضمّن كباب خلفي:** `kouidrihamza45@gmail.com` في `app_settings.dart:17`، و`catalog_sync.sql:23`، و`send-worker-assignment/index.ts:47`. يُفضَّل الاعتماد على جدول `app_admins` فقط.

### 4.4 🔴 بيانات حقيقية وملفات ثقيلة مرفوعة في git
- 154 ملفاً متتبَّعاً من نوع `.exe/.db/.py/corrupt`، منها:
  - `diagnostics/phone_backups/Islem.db`، و`al_erp_backup_2026-07-25.db`، و`al_erp_backup_2026-08-22.db`، و`35al_erp_backup.db`: نسخ لقواعد ورش حقيقية فيها أسماء وهواتف زبائن وبيانات مالية.
  - `aluminum_database.db`، و`my_app.db`، و`test.db.corrupt_*`، و`innosetup.exe`، و`is_setup.exe`.
  - سكربتات `.gemini/.../scratch/*.py`.
- **الإصلاح:** حذفها من المستودع وإضافتها إلى `.gitignore`. إذا كان المستودع مشتركاً أو عاماً، يجب تنظيف التاريخ (`git filter-repo`). هذا قرار للمالك.

### 4.5 🟠 مخزون وأرصدة مشتقة تُزامَن كقيم مطلقة
- `workshopTables` (`sql_database.dart:294-345`) تتضمن `CurrentStock` و`PaymentAllocations`، بينما `Commandes.advance_payment` و`MaterialSales.paid_amount` قيم مشتقة.
- **الأثر:** جهازان يخصمان من الصنف نفسه دون اتصال، فتفوز آخر كتابة ويضيع خصم. الحقيقة موجودة في `InventoryTransactions` لكن الرصيد لا يُعاد حسابه منها.
- `UNIQUE(item_id, item_type, color_id, location_id)` (`:3053-3062`) لا يمنع التكرار عندما `color_id IS NULL`، لأن NULL مختلف دائماً في SQLite. والاستعلامات تأخذ `limit: 1`، فقد يتجزأ الرصيد على صفّين.
- **الإصلاح:**
  - إعادة حساب `CurrentStock` من `InventoryTransactions` بعد كل تنزيل يحتوي حركات مخزون، أو عدم مزامنته واشتقاقه محلياً.
  - فهرس فريد على `COALESCE(color_id, -1)`.
  - المبدأ نفسه لـ `PaymentAllocations`: تُبنى محلياً ولا تُزامَن.

### 4.6 🟠 معرّفات autoincrement في جداول تُزامَن
- `MaterialSaleItems` (`:23531`، `:23762`، `:23871`، `:23925`)، و`MaterialRemnants` (`:17939`)، و`StandardSheets` (`:17544`) تُدرج دون `_withDistributedId`.
- بعد مزامنة صف بمعرّف موزّع كبير X، يعطي SQLite لكلا الجهازين X+1، فيكتب صف أحدهما فوق صف الآخر في `workshop_sync_rows` (المفتاح `table_name, row_id`).
- `saveMaterialSaleWithItems` يحذف ويعيد إدراج كل الأسطر في كل حفظ، فينتج عنه tombstones ومعرّفات جديدة وحمل مزامنة زائد.
- **الإصلاح:** `_withDistributedId` في كل إدراج لجدول ورشة، وتحديث الأسطر بمعرّفها بدل حذفها وإعادة إدراجها.

### 4.7 🟠 التنزيل الكامل يمسح التعديلات المحلية غير المرفوعة
- `_startAsync` و`_runBackgroundSyncCycle` ينزّلان (كاملاً إن لزم) **قبل** `uploadPendingChanges` (`supabase_workshop_sync_service.dart:733-745، 825-836`).
- التنزيل الكامل يستدعي `importWorkshopData(replaceAllData: true)`، ثم `clearPendingCloudChanges()` (`:1449-1458`).
- **الأثر:** مستخدم عمل دون اتصال قبل اكتمال التهيئة (أو بعد مسح المؤشر) تُستبدل بياناته المحلية ويُمسح سجل تغييراته.
- **الإصلاح:** ارفع المعلّق أولاً (أو ادمج)، ولا تمسح `_sync_change_log` إلا للصفوف التي استُبدلت فعلاً.

### 4.8 🟡 مزامنة أخرى
- **ازدواجية الخلفيات:** Firebase (Firestore، Auth، إعدادات الدفع، سجلات الاشتراك، مسارات legacy في `deleteAchat :11490-11515`) مع Supabase. هذا يزيد التعقيد ونقاط الفشل؛ يُقترح خطة لإزالة Firestore نهائياً.
- **تزامن الأسعار:** راجع ملاحظة `price-sync-audit.md`. المتبقي غير المنفّذ: مفاتيح الأقسام على مستوى الورشة، ونقل الحذف، وتحديث `sectionPricesForSelectedColor`.
- `print(...)` في مسارات المزامنة (`:839`، `:762`) بدل `debugPrint`، تُطبع في نسخة الإنتاج.

### 4.9 🟡 الترجمة (العربية/الفرنسية/الإنجليزية)
- **74 نصاً عربياً ثابتاً في الواجهات دون `Localization.translate`**، أبرزها:
  - `worker_remnants_review_dialog.dart` (29 نصاً)، و`distribution_tracking_screen.dart` (6)، و`catalogue_manager.dart:2379`، و`map_picker_screen.dart` (5)، و`workers_management_screen.dart:536`.
  - `glass_fabrication_pdf_service.dart:424` (في PDF!)، و`main.dart:235`، و`window_3d_preview.dart:68`، و`welcom_screen.dart:1877`، و`subscription_checker.dart:818`، و`price_sync_banner.dart:484`.
- **رسائل من طبقة البيانات** بالعربية تُعرض كما هي: 103 `StateError/Exception`، ورسائل `SnackBar` داخل `sql_database.dart` (النسخ الاحتياطي)، ونصوص الإشعارات (`:14268`)، وملخصات المزامنة (`lastDownloadSummary :1488-1492`).
  - **الإصلاح:** رموز أخطاء (`error codes`) تُترجم في الواجهة.
- `material_sale_editor_screen.dart` يستعمل `_trans('عربي','Français')` بلغتين فقط، فلا توجد الإنجليزية.
- راجع أيضاً `untranslated_strings_report.txt` و`arabic_translation_audit*.md` الموجودة في الجذر.

### 4.10 🟢 تمرير الفأرة على الويندوز
- الوضع جيد عموماً: `DesktopScrollBehavior` عام (`main.dart:776`، `widgets/desktop_scroll_behavior.dart:582-640`) يضم الفأرة ضمن `dragDevices`، و`ClampingScrollPhysics` على الويندوز، ومنسّق تمرير للحواف.
- **ملاحظات صغيرة:**
  - `app_workspace_shell.dart:408` يعيد تعريف `dragDevices` بثلاثة أنواع فقط (يُسقط القلم وunknown)، وهذا غير متّسق مع البقية.
  - السحب بالفأرة كوسيلة تمرير يمنع **تحديد النص بالسحب** داخل القوائم والجداول، وقد يتعارض مع `ReorderableListView` وأشرطة التمرير. يُقترح استثناء الجداول النصية أو إتاحة تحديد عبر `SelectionArea` بزر معدِّل.
  - 61 `SingleChildScrollView` أفقياً، كثير منها بلا `Scrollbar/controller` ظاهر. على الويندوز لا تمرير أفقي بالعجلة إلا بـ Shift. يُقترح تحويل العجلة العمودية إلى أفقية عندما يكون الاتجاه الوحيد أفقياً (المنسّق يغطي جزءاً من هذا؛ يحتاج تحقق تشغيلي).
- يوجد اختبار `test/desktop_scroll_regression_test.dart` (لم يُشغَّل في هذا الفحص).

---

## 5. نتائج `flutter analyze`

- **537 ملاحظة:** 0 أخطاء، و172 تحذيراً، و365 معلومة (`ran in 164s`).
- **توزيع الأنواع:**

| النوع | العدد |
|---|---|
| `deprecated_member_use` (منها `withOpacity` 161، `value` 77، `groupValue/onChanged` لـ Radio 88، `scaled` 11، `Share/shareXFiles` 12) | 361 |
| `unused_element` (دوال وواجهات غير مستعملة) | 45 |
| `unused_local_variable` | 30 |
| `unnecessary_non_null_assertion` | 27 |
| `unused_field` | 23 |
| `dead_code` (انظر §2.15) | 15 |
| `unused_import` | 13 |
| `unnecessary_null_comparison` | 11 |
| `unnecessary_import` | 4 |
| `unused_element_parameter` | 3 |
| `dead_null_aware_expression` | 3 |
| `invalid_null_aware_operator` (`order_table_edit_screen.dart:853`) | 1 |
| `unreachable_switch_default` (`app_workspace_shell.dart:647`) | 1 |

- **تحذيرات تستحق المراجعة لأنها قد تخفي منطقاً خاطئاً:**
  - `calculate_component.dart:3023-3024` (`doorSingleSashCount/doorDoubleSashCount` محسوبة وغير مستعملة).
  - `:3062` (`pvcJointBrosseSum`)، و`:4633` (`slidingSashLateralPieces`).
  - `show_system_francais.dart:2530` (`shutterRules`)، و`:7588` (`slidingJointSpecs`).
  - `material_consumption_screen.dart:4427` (`isMotorKit`).
  - `commande.dart:6908` (`orderId`).
- **الإصلاح:** `dart fix --apply` للمهجور والاستيرادات، ثم مراجعة يدوية للمتغيرات المحسوبة غير المستعملة.

---

## 6. مشاكل صغيرة وجودة الكود

- `lib/Screen/all page.dart`: اسم ملف بمسافة. و`lib/scratch_firebase.dart` و`lib/items_produits/joint.backup.dart` ملفات تجريبية داخل `lib/` تُحلَّل وتُبنى.
- الجذر مزدحم بعشرات سكربتات Python وملفات `analyze_out*.txt` و`diff*.txt` و`test_invoice*.pdf` و`*.png`. يُنقل ما يلزم إلى `tool/` ويُحذف الباقي.
- `sql_database.dart` (24,622 سطراً): كائن واحد يجمع المخطط والترحيلات والمنطق المالي والمخزون والمزامنة والواجهة (`BuildContext`). يُقترح تقسيمه إلى مستودعات (`OrdersRepository`، `InventoryRepository`، `TreasuryRepository`، `MaterialSalesRepository`) مع ترحيلات مرقّمة.
- **ذرّية العمليات المركّبة:** كثير من العمليات تتم في عدة استدعاءات منفصلة بدل معاملة واحدة، منها:
  - إنشاء وثيقة المحل: `insert` ثم `saveItems` ثم `deduct` ثم `update status` (`material_sale_editor_screen.dart:340-380`).
  - تسجيل دفعة محل (§2.8)، وحذف وثيقة محل (§2.7)، وتسوية الأجور (§2.10).
  - يُفضَّل أن تقدّم طبقة البيانات عمليات «وحدة عمل» واحدة.
- `stock_reserved_at` محلي بينما بقية الطوابع UTC (§2.9).
- `getNextAchatInvoiceNumber` يقرأ كل الفواتير لإيجاد الرقم التالي (§2.13).
- `nextMaterialSaleCode` يقرأ كل أكواد السنة ويحللها بـ Regex (`:23012`). يكفي `MAX(CAST(substr(...)))`.
- `deleteAchat` يتحقق من الكمية في `location_id = 1` ثابتاً (`:11416`) بدل مخزن الفاتورة.
- `emptyAchatTrash` يبتلع الأخطاء دون إخبار المستخدم بالفاتورة التي فشلت (`:11792`).
- الاختبارات: يوجد حوالي 95 ملف اختبار، معظمها للحسابات الهندسية والواجهات. **لا توجد اختبارات** لـ: دفتر الزبون والمورد، ومبيعات المحل (خصم، تعديل، حذف، مرتجع)، والتسوية الأسبوعية، و`deleteAchat`. يُقترح إضافتها قبل إصلاح البنود 2.1–2.10.

---

## 7. خطة إصلاح مقترحة (بالترتيب)

1. **فوراً (أمان وبيانات):**
   - §4.4: إخراج القواعد الحقيقية من git.
   - §4.3: نقل مفتاح Chargily للخادم، وتفعيل الاشتراك عبر webhook.
   - §4.2: تشديد RLS (الحظر، والحذف للمدراء، وفصل الجداول المالية).
2. **سلامة الأرقام المالية:**
   - §2.2: فصل إيصالات المحل عن دفتر الطلبيات.
   - §2.4: صيغة TVA موحّدة مع ترحيل `net_payable`.
   - §2.8: ربط «المبلغ المسدد» بالخزينة.
   - §2.12: استبعاد المحذوف من دفتر المورد.
3. **سلامة المخزون:**
   - §2.1: إصلاح `deleteAchat`.
   - §2.5، §2.6، §2.7: تعديل وحذف وثائق المحل بالفروقات، داخل معاملة.
   - §2.9: الحجز.
   - §4.5: إعادة حساب `CurrentStock` من الحركات.
4. **المزامنة:**
   - §4.1: مؤشر خادم (`server_seq`).
   - §4.6: معرّفات موزّعة لكل جداول الورشة.
   - §4.7: الرفع قبل التنزيل الكامل.
   - §2.11: مصالحة أرقام الطلبيات والزبائن.
5. **الأداء:**
   - §3.1: علامة جاهزية للمشغّلات وإزالة `quick_check` من الرفع.
   - §3.2: نقل `ALTER` إلى `onUpgrade`.
   - §3.4: الفهارس.
   - §3.3: إزالة N+1 في المخزون ولوحة التحكم.
   - §3.6: تقليل الاستطلاع إلى كل 2–5 دقائق.
   - §3.5: pagination.
6. **النسخ الاحتياطي:** §2.3 إصلاحه على الويندوز، ثم §1.7 نسخ تلقائي مشفّر.
7. **الترجمة والتنظيف:**
   - §4.9 و§2.14: النصوص الثابتة والترميز.
   - §5: `dart fix` والكود الميت.
   - §6: تنظيف المستودع.
8. **الميزات الناقصة (§1)** حسب الأولوية التجارية: الطابع الجبائي، وTVA المرنة، وAvoir، والترقيم القانوني، وأعمار الديون، وتصدير Excel.
