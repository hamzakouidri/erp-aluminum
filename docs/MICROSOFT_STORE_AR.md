# نشر التطبيق في متجر مايكروسوفت (Microsoft Store)

المتجر يوقّع التطبيق بنفسه، فلا حاجة إلى شهادة توقيع مدفوعة، ولا يظهر تحذير Windows عند التثبيت.

## 1. حساب المطوّر (مرة واحدة)
1. افتح https://partner.microsoft.com/dashboard وسجّل بحساب مايكروسوفت.
2. اختر **حساب فردي (Individual)** وأكمل التحقق من الهوية.
   تسجيل الأفراد مجاني حسب آخر ما نعلمه؛ تأكد من ذلك في صفحة التسجيل.

## 2. حجز اسم التطبيق
1. في Partner Center: **Apps and games ← New product ← MSIX or PWA app**.
2. احجز اسمًا، مثلًا «ورشتي - ERP Aluminium».
3. افتح التطبيق ثم **Product management ← Product identity**، وانسخ قيمتين:
   - `Package/Identity/Name`
   - `Package/Identity/Publisher` (تبدأ بـ `CN=`)

## 3. وضع القيمتين في المشروع
في `pubspec.yaml`، داخل `msix_config`:
```yaml
  identity_name: <قيمة Package/Identity/Name>
  publisher: <قيمة Package/Identity/Publisher كاملة مع CN=>
```

## 4. صنع الحزمة (على كمبيوتر Windows)
داخل مجلد المشروع:
```
flutter pub get
dart run msix:create --store
```
الحزمة تُصنع في:
`build\windows\x64\runner\Release\database_data.msix`

## 5. الإرسال للمراجعة
في Partner Center: **Start your submission**، ثم:
- **Packages**: ارفع ملف `.msix`.
- **Store listings**: الوصف بالعربية والفرنسية، وصور شاشة (واحدة على الأقل).
- **Properties**: الفئة (Business / Productivity) و**رابط سياسة الخصوصية** (لازم لأن التطبيق يستعمل الميكروفون للمساعد الصوتي).
- **Age ratings**: أجب عن الاستبيان.
- **Pricing**: مجاني أو مدفوع.

ثم **Submit to the Store**. تستغرق المراجعة عادة من يوم إلى بضعة أيام.

## 6. التحديثات
1. ارفع الرقم في `msix_version` (مثلًا `1.0.1.0`). يجب أن يكبر في كل إرسال.
2. أعد `dart run msix:create --store`.
3. أنشئ إرسالًا جديدًا في Partner Center وارفع الحزمة الجديدة.

يصل التحديث تلقائيًا لكل من ثبّت التطبيق من المتجر.
